import AppKit
import SwiftUI

struct UniversalAIEditPanelView: View {
    static let preferredContentSize = NSSize(width: 640, height: 540)
    static let composerOnlyContentSize = NSSize(width: 640, height: 320)
    static let previewBoxHeight: CGFloat = 220
    static let composerActionClusterWidth: CGFloat = 168
    static let instructionEditorApproximateCharactersPerLine = 54

    static func contentSize(showingPreview: Bool) -> NSSize {
        showingPreview ? preferredContentSize : composerOnlyContentSize
    }

    @ObservedObject var manager: UniversalAIEditManager
    @FocusState private var instructionFocused: Bool
    @State private var contextDetailsExpanded = false
    @State private var previewMode: UniversalAIEditPreviewMode = .diff
    @State private var isScreenContextInspectorPresented = false
    @State private var promptTemplateEditor: PromptTemplateEditorPresentation?
    @State private var recordingPulse = false

    var body: some View {
        VStack(spacing: 0) {
            compactHeader

            VStack(alignment: .leading, spacing: 12) {
                compactContextSummary
                composerArea

                if manager.shouldShowPreview {
                    previewArea
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(
            width: Self.contentSize(showingPreview: manager.shouldShowPreview).width,
            height: Self.contentSize(showingPreview: manager.shouldShowPreview).height
        )
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.Surface.window)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.Border.card, lineWidth: 1)
        )
        .onAppear {
            instructionFocused = manager.shouldFocusInstructionOnAppear
            recordingPulse = manager.isVoiceRecording
        }
        .onChange(of: instructionFocused) { _, isFocused in
            guard isFocused else { return }
            manager.cancelVoiceInstructionForManualInput()
        }
        .onChange(of: manager.instructionFocusRequest) { _, _ in
            focusInstructionEditor()
        }
        .onChange(of: manager.instruction) { _, _ in
            manager.cancelVoiceInstructionForManualInput()
        }
        .onChange(of: manager.isVoiceRecording) { _, isRecording in
            recordingPulse = isRecording
        }
        .onChange(of: manager.shouldShowPreview) { _, shouldShowPreview in
            manager.updatePanelSize(showingPreview: shouldShowPreview)
        }
        .sheet(isPresented: $isScreenContextInspectorPresented) {
            if liveScreenContextInspectionText != nil || liveScreenshotContextData != nil {
                AIEditScreenContextInspectorView(
                    contextText: liveScreenContextInspectionText,
                    screenshotData: liveScreenshotContextData,
                    screenshotMetadata: liveScreenshotContextMetadata,
                    subtitle: screenContextInspectorSubtitle
                )
            }
        }
        .sheet(item: $promptTemplateEditor) { presentation in
            UniversalAIEditPromptTemplateEditorSheet(
                template: presentation.template,
                onSave: { id, label, content in
                    manager.savePromptTemplate(id: id, label: label, content: content)
                },
                onDelete: { template in
                    manager.deletePromptTemplate(template)
                }
            )
        }
    }

    private func focusInstructionEditor() {
        DispatchQueue.main.async {
            instructionFocused = true
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.Accent.primary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(AppTheme.Accent.fill))

            Text("AI Edit")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.Text.primary)

            Text(manager.context?.target.displayName ?? String(localized: "Target app"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.Text.secondary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Picker("", selection: modeSelection) {
                Text("Edit selection").tag(UniversalAIEditMode.replaceSelection)
                    .disabled(!manager.canSelectMode(.replaceSelection))
                Text("Generate").tag(UniversalAIEditMode.insertNew)
            }
            .pickerStyle(.segmented)
            .frame(width: 214)
            .disabled(!manager.canInteractWithModePicker)

            Button {
                manager.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(Divider().opacity(0.45), alignment: .bottom)
    }

    private var compactContextSummary: some View {
        DisclosureGroup(isExpanded: $contextDetailsExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    contextChip(
                        title: selectionChipTitle,
                        systemImage: "text.cursor",
                        isActive: manager.hasEditableSelection
                    )
                    screenContextChip
                    contextChip(
                        title: manager.context?.clipboardText == nil ? "Clipboard off" : "Clipboard",
                        systemImage: "doc.on.clipboard",
                        isActive: manager.context?.clipboardText?.isEmpty == false
                    )
                }

                diagnosticsView
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Label(contextSummaryText, systemImage: "info.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.Text.secondary)
                    .lineLimit(1)

                if !visibleDiagnostics.isEmpty {
                    Text(String(format: String(localized: "%lld diagnostics"), Int64(visibleDiagnostics.count)))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(hasWarningDiagnostics ? AppTheme.Status.warningStrong : AppTheme.Text.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill((hasWarningDiagnostics ? AppTheme.Status.warningStrong : AppTheme.Surface.controlActive).opacity(0.12))
                        )
                }

                Spacer()
            }
        }
        .tint(AppTheme.Text.secondary)
    }

    private var diagnostics: [UniversalAIEditCaptureDiagnostic] {
        manager.context?.diagnostics ?? []
    }

    private var visibleDiagnostics: [UniversalAIEditCaptureDiagnostic] {
        UniversalAIEditDiagnosticVisibility.visibleDiagnostics(diagnostics, mode: manager.mode)
    }

    private var hasWarningDiagnostics: Bool {
        visibleDiagnostics.contains { $0.isWarning }
    }

    private var contextSummaryText: String {
        var parts: [String] = []

        if manager.hasEditableSelection, manager.mode == .replaceSelection {
            parts.append(
                manager.context?.editTargetSource == .focusedInput
                    ? String(localized: "input captured")
                    : String(localized: "selection captured")
            )
        } else {
            parts.append(manager.mode.displayName.lowercased())
        }

        if manager.context?.screenshotContext != nil {
            parts.append(String(localized: "screenshot context"))
        } else if manager.context?.screenText?.isEmpty == false {
            parts.append(String(localized: "screen context"))
        } else if manager.hasPendingScreenContext,
                  let source = manager.pendingScreenContextSourceDescription {
            parts.append(String(format: String(localized: "%@ context source"), source))
        }

        if manager.context?.clipboardText?.isEmpty == false {
            parts.append(String(localized: "clipboard"))
        }

        return parts.joined(separator: " · ")
    }

    private var selectionChipTitle: String {
        if manager.mode == .insertNew {
            return String(localized: "Generate mode")
        }
        if diagnostics.contains(.accessibilityPermissionMissing) {
            return String(localized: "Accessibility needed")
        }
        if diagnostics.contains(.selectedTextCaptureFailed) {
            return String(localized: "Selection failed")
        }
        if manager.hasEditableSelection {
            return manager.context?.editTargetSource == .focusedInput
                ? String(localized: "Input captured")
                : String(localized: "Selection captured")
        }
        return String(localized: "No selection")
    }

    private var screenChipTitle: String {
        if manager.hasPendingScreenContext,
           let source = manager.pendingScreenContextSourceDescription {
            return String(format: String(localized: "Will use %@"), source)
        }
        if diagnostics.contains(.screenContextDisabled) {
            return String(localized: "Screen off")
        }
        if diagnostics.contains(.screenRecordingPermissionMissing) {
            return String(localized: "Screen permission")
        }
        if diagnostics.contains(.screenCaptureFailed) {
            return String(localized: "Screen failed")
        }
        if diagnostics.contains(.screenshotContextUnsupported) {
            return String(localized: "OCR fallback")
        }
        if diagnostics.contains(.screenshotContextUnavailable) {
            return String(localized: "OCR fallback")
        }
        if manager.context?.screenshotContext != nil {
            return String(localized: "Screenshot context")
        }
        if diagnostics.contains(.screenTextUnavailable) {
            return String(localized: "No screen text")
        }
        if manager.context?.screenText?.isEmpty == false {
            return String(localized: "Screen context")
        }
        return String(localized: "No screen context")
    }

    private var screenContextInspectorSubtitle: String {
        if let targetName = manager.context?.target.displayName {
            return String(localized: "Captured from the \(targetName) window targeted by AI Edit")
        }
        return String(localized: "Captured from the window targeted by AI Edit")
    }

    private var liveScreenContextInspectionText: String? {
        guard let screenText = manager.context?.screenText, !screenText.isEmpty else {
            return nil
        }
        return screenText
    }

    private var liveScreenshotContextData: Data? {
        manager.context?.screenshotContext?.data
    }

    private var liveScreenshotContextMetadata: String? {
        manager.context?.screenshotContext?.redactedMetadata
    }

    @ViewBuilder
    private var diagnosticsView: some View {
        if !visibleDiagnostics.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleDiagnostics) { diagnostic in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: diagnostic.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(diagnostic.isWarning ? AppTheme.Status.warningStrong : AppTheme.Text.secondary)
                            .frame(width: 14)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(diagnostic.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppTheme.Text.primary)
                            Text(diagnostic.message)
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.Text.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        if let urlString = diagnostic.settingsURLString,
                           let url = URL(string: urlString) {
                            Button("Open Settings") {
                                NSWorkspace.shared.open(url)
                            }
                            .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill((diagnostic.isWarning ? AppTheme.Status.warningStrong : AppTheme.Surface.controlActive).opacity(diagnostic.isWarning ? 0.12 : 0.5))
                    )
                }
            }
        }
    }

    private var modeSelection: Binding<UniversalAIEditMode> {
        Binding(
            get: { manager.mode },
            set: { manager.setMode($0) }
        )
    }

    @ViewBuilder
    private var screenContextChip: some View {
        if liveScreenContextInspectionText != nil || liveScreenshotContextData != nil {
            Button {
                isScreenContextInspectorPresented = true
            } label: {
                contextChipLabel(
                    title: screenChipTitle,
                    systemImage: "rectangle.on.rectangle",
                    isActive: true
                )
            }
            .buttonStyle(.plain)
            .help("View screen context")
        } else {
            contextChip(
                title: screenChipTitle,
                systemImage: "rectangle.on.rectangle",
                isActive: false
            )
        }
    }

    private func contextChip(title: String, systemImage: String, isActive: Bool) -> some View {
        contextChipLabel(title: title, systemImage: systemImage, isActive: isActive)
    }

    private func contextChipLabel(title: String, systemImage: String, isActive: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isActive ? AppTheme.Text.primary : AppTheme.Text.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isActive ? AppTheme.Selection.fill : AppTheme.Surface.subtle)
            )
    }

    private var composerArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            composerHeaderRow
            promptTemplateRow

            HStack(alignment: .bottom, spacing: 10) {
                instructionTextEditor

                VStack(alignment: .trailing, spacing: 8) {
                    secondaryActionCluster
                    composerPrimaryButton
                }
                .frame(width: Self.composerActionClusterWidth, alignment: .trailing)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Surface.control.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Border.control.opacity(0.55), lineWidth: 1)
        )
    }

    private var composerHeaderRow: some View {
        HStack(spacing: 8) {
            Text("Instruction")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.Text.secondary)

            composerStatusPill

            Spacer(minLength: 8)

            if let hint = manager.happyPathShortcutHint {
                Text(hint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.Accent.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(minHeight: 24)
    }

    private var promptTemplateRow: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(manager.promptTemplates.enumerated()), id: \.element.id) { index, template in
                        UniversalAIEditPromptTemplateButton(
                            template: template,
                            shortcutDisplayNumber: UniversalAIEditPromptTemplateShortcut.displayNumber(forButtonIndex: index),
                            onClick: {
                                manager.activatePromptTemplate(template, runAfterInsert: true)
                            }
                        )
                        .frame(height: 24)
                        .fixedSize(horizontal: true, vertical: false)
                        .contextMenu {
                            Button("Edit") {
                                promptTemplateEditor = PromptTemplateEditorPresentation(template: template)
                            }
                            Button("Delete", role: .destructive) {
                                manager.deletePromptTemplate(template)
                            }
                        }
                    }
                }
            }

            Button {
                promptTemplateEditor = PromptTemplateEditorPresentation(template: nil)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .background(
                Circle()
                    .fill(AppTheme.Surface.controlActive.opacity(0.55))
            )
            .overlay(
                Circle()
                    .stroke(AppTheme.Border.control.opacity(0.55), lineWidth: 1)
            )
            .help("New prompt template")
        }
        .frame(minHeight: 26)
    }

    private var instructionTextEditor: some View {
        TextEditor(text: $manager.instruction)
            .font(.system(size: 14))
            .modelBoundTextInput { textView in
                manager.registerInstructionTextView(textView)
            }
            .focused($instructionFocused)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(height: instructionEditorHeight)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppTheme.Surface.window)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(instructionFocused ? AppTheme.Accent.border : AppTheme.Border.control.opacity(0.55), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if manager.isVoiceRecording {
                    recordingInlineStatus
                        .padding(.horizontal, 10)
                        .allowsHitTesting(false)
                }
            }
    }

    private var instructionEditorHeight: CGFloat {
        UniversalAIEditFlow.instructionEditorHeight(
            text: manager.instruction,
            approximateCharactersPerLine: Self.instructionEditorApproximateCharactersPerLine
        )
    }

    @ViewBuilder
    private var recordingInlineStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppTheme.Accent.primary)
                .frame(width: 7, height: 7)
                .opacity(0.9)

            Text("Recording")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.Accent.primary)

            UniversalAIEditVoiceWaveform(
                currentLevel: manager.voiceMeterLevel,
                samples: manager.voiceMeterSamples
            )

            Text("Esc cancels, typing switches to manual")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.Text.muted)
        }
    }

    @ViewBuilder
    private var composerStatusPill: some View {
        if shouldShowStatus, let status = manager.statusText {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(statusColor.opacity(0.10))
            )
        }
    }

    private var shouldShowStatus: Bool {
        switch manager.phase {
        case .capturing, .transcribingInstruction, .generating, .applying, .failed:
            return true
        case .idle, .ready, .listening, .preview:
            return false
        }
    }

    private var statusColor: Color {
        switch manager.phase {
        case .failed:
            return AppTheme.Status.error
        case .capturing, .transcribingInstruction, .generating, .applying:
            return AppTheme.Accent.primary
        case .idle, .ready, .listening, .preview:
            return AppTheme.Text.secondary
        }
    }

    private var previewArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Preview")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)

                if let result = manager.lastResult {
                    Text(result.modelName)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Text.muted)
                        .lineLimit(1)
                }

                if manager.isResultStale {
                    Label("Stale", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.Status.warningStrong)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(AppTheme.Status.warningStrong.opacity(0.12))
                        )
                        .help("Generate again before applying")
                }

                Spacer()

                if canShowDiffToggle {
                    Picker("", selection: $previewMode) {
                        Text("Diff").tag(UniversalAIEditPreviewMode.diff)
                        Text("New text").tag(UniversalAIEditPreviewMode.newText)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 156)
                }
            }

            ScrollView {
                previewContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, minHeight: Self.previewBoxHeight, maxHeight: Self.previewBoxHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.Surface.subtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.Border.subtle, lineWidth: 1)
            )
        }
        .layoutPriority(0)
    }

    @ViewBuilder
    private var previewContent: some View {
        if manager.generatedText.isEmpty {
            Text("Generated text will appear here.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.Text.muted)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        } else if previewMode == .diff, canShowDiffToggle {
            diffPreview
        } else {
            Text(manager.generatedText)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundColor(AppTheme.Text.primary)
                .textSelection(.enabled)
        }
    }

    private var canShowDiffToggle: Bool {
        manager.mode == .replaceSelection &&
            manager.hasEditableSelection &&
            !manager.generatedText.isEmpty
    }

    private var diffLines: [UniversalAIEditDiffLine] {
        UniversalAIEditDiffBuilder.lines(
            original: manager.context?.selectedText ?? "",
            revised: manager.generatedText
        )
    }

    private var diffPreview: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(diffPrefix(for: line.kind))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(diffAccentColor(for: line.kind))
                        .frame(width: 14, alignment: .trailing)

                    Text(attributedText(for: line))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(AppTheme.Text.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(diffRowBackground(for: line.kind))
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attributedText(for line: UniversalAIEditDiffLine) -> AttributedString {
        var result = AttributedString()
        let spans = line.spans.isEmpty || line.text.isEmpty
            ? [UniversalAIEditDiffSpan(kind: .unchanged, text: " ")]
            : line.spans

        for span in spans {
            var attributedSpan = AttributedString(span.text)
            attributedSpan.foregroundColor = AppTheme.Text.primary

            switch span.kind {
            case .unchanged:
                break
            case .removed:
                attributedSpan.backgroundColor = AppTheme.Status.error.opacity(0.22)
            case .inserted:
                attributedSpan.backgroundColor = AppTheme.Status.positive.opacity(0.22)
            }

            result += attributedSpan
        }

        return result
    }

    private func diffPrefix(for kind: UniversalAIEditDiffLine.Kind) -> String {
        switch kind {
        case .unchanged:
            return " "
        case .removed:
            return "-"
        case .inserted:
            return "+"
        }
    }

    private func diffAccentColor(for kind: UniversalAIEditDiffLine.Kind) -> Color {
        switch kind {
        case .unchanged:
            return AppTheme.Text.muted
        case .removed:
            return AppTheme.Status.error
        case .inserted:
            return AppTheme.Status.positive
        }
    }

    private func diffRowBackground(for kind: UniversalAIEditDiffLine.Kind) -> Color {
        switch kind {
        case .unchanged:
            return AppTheme.Surface.clear
        case .removed:
            return AppTheme.Status.error.opacity(0.08)
        case .inserted:
            return AppTheme.Status.positive.opacity(0.08)
        }
    }

    @ViewBuilder
    private var secondaryActionCluster: some View {
        HStack(spacing: 8) {
            voiceControlButton

            if !manager.isVoiceRecording {
                if manager.canRedoVoiceInstruction {
                    Button {
                        manager.redoVoiceInstruction()
                    } label: {
                        Label("Redo Voice", systemImage: "arrow.counterclockwise")
                    }
                    .help("Clear the current instruction and record it again")
                }

                if manager.canCopyResult {
                    Button("Copy") {
                        manager.copyResult()
                    }
                }

                if manager.canRegenerate {
                    Button("Regenerate") {
                        manager.generate()
                    }
                    .disabled(!manager.canRegenerate)
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .controlSize(.small)
        .lineLimit(1)
    }

    private var composerPrimaryButton: some View {
        Button {
            manager.performComposerPrimaryAction()
        } label: {
            Text(manager.composerPrimaryAction.title)
                .frame(maxWidth: .infinity)
        }
        .keyboardShortcut(.return, modifiers: [])
        .disabled(!manager.canPerformComposerPrimaryAction)
        .frame(width: 108)
        .buttonStyle(.borderedProminent)
    }

    private var voiceControlButton: some View {
        Button {
            manager.toggleVoiceInstruction()
        } label: {
            ZStack {
                if manager.isVoiceRecording {
                    Circle()
                        .stroke(AppTheme.Accent.primary.opacity(0.32), lineWidth: 2)
                        .scaleEffect(recordingPulse ? 1.18 : 0.96)
                        .opacity(recordingPulse ? 0.56 : 0.18)
                        .animation(
                            .easeInOut(duration: 0.95).repeatForever(autoreverses: true),
                            value: recordingPulse
                        )
                }

                Circle()
                    .fill(manager.isVoiceRecording ? AppTheme.Accent.fill : AppTheme.Surface.controlActive.opacity(0.55))
                    .overlay(
                        Circle()
                            .stroke(
                                manager.isVoiceRecording ? AppTheme.Accent.primary.opacity(0.42) : AppTheme.Border.control.opacity(0.5),
                                lineWidth: 1
                            )
                    )

                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(manager.isVoiceRecording ? AppTheme.Accent.primary : AppTheme.Text.secondary)
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!manager.canToggleVoiceInstruction)
        .help(manager.isVoiceRecording ? "Stop recording" : "Record instruction")
        .accessibilityLabel(manager.isVoiceRecording ? "Stop recording" : "Record instruction")
    }
}

private struct PromptTemplateEditorPresentation: Identifiable {
    let id = UUID()
    let template: UniversalAIEditPromptTemplate?
}

private struct UniversalAIEditPromptTemplateButton: NSViewRepresentable {
    let template: UniversalAIEditPromptTemplate
    let shortcutDisplayNumber: String?
    let onClick: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configure(button)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.onClick = onClick
        configure(nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onClick: onClick)
    }

    private func configure(_ button: NSButton) {
        button.attributedTitle = attributedTitle
        button.toolTip = tooltip
        button.sendAction(on: [.leftMouseUp])
    }

    private var tooltip: String {
        if let shortcutDisplayNumber {
            return String(format: String(localized: "Click to run %@. Command+%@ inserts it."), template.label, shortcutDisplayNumber)
        }
        return String(format: String(localized: "Click to run %@"), template.label)
    }

    private var attributedTitle: NSAttributedString {
        let title = NSMutableAttributedString()

        if let shortcutDisplayNumber {
            title.append(
                NSAttributedString(
                    string: "\(shortcutDisplayNumber) ",
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                )
            )
        }

        title.append(
            NSAttributedString(
                string: template.label,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
            )
        )

        return title
    }

    final class Coordinator: NSObject {
        var onClick: () -> Void

        init(onClick: @escaping () -> Void) {
            self.onClick = onClick
        }

        @objc func handleClick(_ sender: NSButton) {
            let clickCount = NSApp.currentEvent?.clickCount ?? 1
            guard UniversalAIEditPromptTemplateMouseActivation.shouldActivate(clickCount: clickCount) else { return }
            onClick()
        }
    }
}

private struct UniversalAIEditPromptTemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let template: UniversalAIEditPromptTemplate?
    let onSave: (UUID?, String, String) -> Void
    let onDelete: (UniversalAIEditPromptTemplate) -> Void

    @State private var label: String
    @State private var content: String

    init(
        template: UniversalAIEditPromptTemplate?,
        onSave: @escaping (UUID?, String, String) -> Void,
        onDelete: @escaping (UniversalAIEditPromptTemplate) -> Void
    ) {
        self.template = template
        self.onSave = onSave
        self.onDelete = onDelete
        _label = State(initialValue: template?.label ?? "")
        _content = State(initialValue: template?.content ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(template == nil ? "New Template" : "Edit Template")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.Text.primary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Label")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.Text.secondary)
                TextField("Polish", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Content")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.Text.secondary)
                TextEditor(text: $content)
                    .font(.system(size: 13))
                    .modelBoundTextInput()
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 130)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.Surface.window)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppTheme.Border.control.opacity(0.55), lineWidth: 1)
                    )
            }

            HStack {
                if let template {
                    Button("Delete", role: .destructive) {
                        onDelete(template)
                        dismiss()
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    onSave(template?.id, label, content)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(18)
        .frame(width: 430)
    }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private enum UniversalAIEditPreviewMode: Hashable {
    case diff
    case newText
}

private struct UniversalAIEditVoiceWaveform: View {
    let currentLevel: Double
    let samples: [Double]

    var body: some View {
        HStack(alignment: .center, spacing: 1) {
            ForEach(Array(waveformValues.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(level >= 0.95 ? AppTheme.Status.error : AppTheme.Accent.primary)
                    .frame(width: 2, height: max(2, CGFloat(2 + level * 12)))
                    .opacity(max(0.18, 0.35 + level * 0.55))
            }
        }
        .frame(width: 104, height: 18)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppTheme.Accent.primary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(AppTheme.Accent.primary.opacity(0.18), lineWidth: 1)
        )
        .accessibilityLabel("Current and recent input level")
    }

    private var waveformValues: [Double] {
        let visibleCount = 34
        let visibleSamples = samples.suffix(visibleCount - 1).map(clamped)
        let padding = Array(repeating: 0.0, count: max(0, visibleCount - 1 - visibleSamples.count))
        return padding + visibleSamples + [clamped(currentLevel)]
    }

    private func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
