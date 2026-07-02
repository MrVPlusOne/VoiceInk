import AppKit
import SwiftUI

struct UniversalAIEditPanelView: View {
    static let preferredContentSize = NSSize(width: 720, height: 680)

    @ObservedObject var manager: UniversalAIEditManager
    @FocusState private var instructionFocused: Bool
    @State private var contextDetailsExpanded = false
    @State private var previewMode: UniversalAIEditPreviewMode = .diff
    @State private var isScreenContextInspectorPresented = false

    var body: some View {
        VStack(spacing: 0) {
            compactHeader

            VStack(alignment: .leading, spacing: 12) {
                compactContextSummary
                instructionEditor
                voiceRecordingStatus
                statusArea
                previewArea
                actionBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(width: Self.preferredContentSize.width, height: Self.preferredContentSize.height)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.Surface.window)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.Border.card, lineWidth: 1)
        )
        .onAppear {
            instructionFocused = true
        }
        .sheet(isPresented: $isScreenContextInspectorPresented) {
            if let screenText = manager.context?.screenText, !screenText.isEmpty {
                AIEditScreenContextInspectorView(
                    contextText: screenText,
                    subtitle: screenContextInspectorSubtitle
                )
            }
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

            Picker("", selection: $manager.mode) {
                Text("Edit selection").tag(UniversalAIEditMode.replaceSelection)
                Text("Generate").tag(UniversalAIEditMode.insertNew)
            }
            .pickerStyle(.segmented)
            .frame(width: 214)
            .disabled(manager.phase.isBusy)

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
                        isActive: manager.context?.selectedText?.isEmpty == false
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

        if manager.context?.selectedText?.isEmpty == false, manager.mode == .replaceSelection {
            parts.append(String(localized: "selection captured"))
        } else {
            parts.append(manager.mode.displayName.lowercased())
        }

        if manager.context?.screenText?.isEmpty == false {
            parts.append(String(localized: "screen context"))
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
        if manager.context?.selectedText?.isEmpty == false {
            return String(localized: "Selection captured")
        }
        return String(localized: "No selection")
    }

    private var screenChipTitle: String {
        if diagnostics.contains(.screenContextDisabled) {
            return String(localized: "Screen off")
        }
        if diagnostics.contains(.screenRecordingPermissionMissing) {
            return String(localized: "Screen permission")
        }
        if diagnostics.contains(.screenCaptureFailed) {
            return String(localized: "Screen failed")
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
            return String(localized: "Captured from \(targetName) before this panel opened")
        }
        return String(localized: "Captured before this panel opened")
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

    @ViewBuilder
    private var screenContextChip: some View {
        if manager.context?.screenText?.isEmpty == false {
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

    private var instructionEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Instruction")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.Text.secondary)

                Spacer()

                Button {
                    manager.toggleVoiceInstruction()
                } label: {
                    Label(
                        manager.isVoiceRecording ? "Stop" : "Voice",
                        systemImage: manager.isVoiceRecording ? "stop.fill" : "mic.fill"
                    )
                    .font(.system(size: 12, weight: .medium))
                }
                .disabled(manager.phase == .generating || manager.phase == .applying)
            }

            TextEditor(text: $manager.instruction)
                .font(.system(size: 14))
                .focused($instructionFocused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(height: instructionEditorHeight)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppTheme.Surface.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(instructionFocused ? AppTheme.Accent.border : AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                )
        }
    }

    private var instructionEditorHeight: CGFloat {
        let text = manager.instruction
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { max(1, Int(ceil(Double($0.count) / 78.0))) }
            .reduce(0, +)
        let resolvedLines = max(1, lines)
        return min(118, max(44, CGFloat(resolvedLines) * 20 + 20))
    }

    @ViewBuilder
    private var voiceRecordingStatus: some View {
        if manager.isVoiceRecording {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppTheme.Accent.primary)
                    .frame(width: 8, height: 8)
                    .opacity(0.9)

                Text("Recording")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.Accent.primary)

                UniversalAIEditVoiceWaveform(
                    currentLevel: manager.voiceMeterLevel,
                    samples: manager.voiceMeterSamples
                )

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppTheme.Accent.fill.opacity(0.65))
            )
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        if shouldShowStatus, let status = manager.statusText {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusColor)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.Surface.subtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.Border.subtle, lineWidth: 1)
            )
        }
        .frame(maxHeight: .infinity)
        .layoutPriority(1)
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
            manager.context?.selectedText?.isEmpty == false &&
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

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Discard") {
                manager.discardPreview()
            }
            .disabled(manager.generatedText.isEmpty || manager.phase.isBusy)

            Spacer()

            Button("Copy") {
                manager.copyResult()
            }
            .disabled(manager.generatedText.isEmpty || manager.phase.isBusy)

            Button("Generate") {
                manager.generate()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!manager.canGenerate)

            Button("Apply") {
                manager.applyResult()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!manager.canApply)
        }
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
