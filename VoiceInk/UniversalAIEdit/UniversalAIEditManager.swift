import AppKit
import Foundation
import os
import SwiftUI

@MainActor
final class UniversalAIEditManager: ObservableObject {
    static let shared = UniversalAIEditManager()
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "UniversalAIEditLaunch")

    @Published private(set) var phase: UniversalAIEditPhase = .idle
    @Published private(set) var context: UniversalAIEditContext?
    @Published var mode: UniversalAIEditMode = .insertNew
    @Published var instruction = ""
    @Published private(set) var generatedText = ""
    @Published private(set) var statusText: String?
    @Published private(set) var lastResult: UniversalAIEditResult?
    @Published private(set) var isVoiceRecording = false
    @Published private(set) var voiceMeterLevel: Double = 0
    @Published private(set) var voiceMeterSamples: [Double] = []
    @Published private(set) var shouldFocusInstructionOnAppear = true
    @Published private(set) var instructionFocusRequest = 0
    @Published private(set) var promptTemplates: [UniversalAIEditPromptTemplate] = UniversalAIEditPromptTemplateStore.load()

    private let contextCaptureService = UniversalAIEditContextCaptureService()
    private let editService = UniversalAIEditService()
    private let instructionRecorder = Recorder()
    private var instructionAudioURL: URL?
    private var panel: UniversalAIEditPanel?
    private var hostingController: NSHostingController<UniversalAIEditPanelView>?
    private var voiceMeterTask: Task<Void, Never>?
    private weak var engine: VoiceInkEngine?
    private var targetApp: NSRunningApplication?
    private var currentHistoryRecord: AIEditHistoryRecord?
    private var generatedInputSnapshot: UniversalAIEditInputSnapshot?
    private var panelSessionID: UUID?
    private var activeGenerationID: UUID?
    private weak var instructionTextView: NSTextView?

    private init() {}

    var canGenerate: Bool {
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !phase.isBusy
    }

    var canApply: Bool {
        UniversalAIEditFlow.canApply(
            hasGeneratedText: hasGeneratedText,
            phase: phase,
            isResultFresh: isResultFresh
        )
    }

    var canCopyResult: Bool {
        !generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !phase.isBusy
    }

    var canDiscardPreview: Bool {
        !generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !phase.isBusy
    }

    var canRegenerate: Bool {
        canGenerate &&
            !generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            isResultFresh
    }

    var canRedoVoiceInstruction: Bool {
        !phase.isBusy &&
            !isVoiceRecording &&
            engine != nil &&
            !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canToggleVoiceInstruction: Bool {
        UniversalAIEditFlow.canToggleVoiceInstruction(
            phase: phase,
            isVoiceRecording: isVoiceRecording
        )
    }

    var canToggleMode: Bool {
        UniversalAIEditFlow.canToggleMode(phase: phase) && hasEditableSelection
    }

    var canInteractWithModePicker: Bool {
        UniversalAIEditFlow.canToggleMode(phase: phase)
    }

    var hasEditableSelection: Bool {
        UniversalAIEditFlow.hasEditableSelection(context?.selectedText)
    }

    var shouldShowPreview: Bool {
        UniversalAIEditFlow.shouldShowPreview(hasGeneratedText: hasGeneratedText)
    }

    var happyPathShortcutHint: String? {
        let shortcutDisplay = ShortcutStore.shortcut(for: .universalAIEdit)?.displayString
        let action = UniversalAIEditFlow.shortcutHintAction(
            phase: phase,
            isVoiceRecording: isVoiceRecording,
            canGenerate: canGenerate,
            hasGeneratedText: hasGeneratedText,
            isResultFresh: isResultFresh
        )
        return UniversalAIEditFlow.shortcutHintText(
            shortcutDisplay: shortcutDisplay,
            action: action
        )
    }

    var primaryAction: UniversalAIEditPrimaryAction {
        UniversalAIEditFlow.primaryAction(
            hasGeneratedText: hasGeneratedText,
            isResultFresh: isResultFresh
        )
    }

    var composerPrimaryAction: UniversalAIEditComposerPrimaryAction {
        UniversalAIEditFlow.composerPrimaryAction(
            phase: phase,
            isVoiceRecording: isVoiceRecording,
            hasGeneratedText: hasGeneratedText,
            isResultFresh: isResultFresh
        )
    }

    var canPerformPrimaryAction: Bool {
        switch primaryAction {
        case .generate:
            return canGenerate
        case .apply:
            return canApply
        }
    }

    var canPerformComposerPrimaryAction: Bool {
        switch composerPrimaryAction {
        case .generate:
            return canGenerate
        case .apply:
            return canApply
        }
    }

    var isResultFresh: Bool {
        guard !generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let generatedInputSnapshot,
              let currentInputSnapshot else {
            return false
        }

        return generatedInputSnapshot == currentInputSnapshot
    }

    var isResultStale: Bool {
        hasGeneratedText && !isResultFresh
    }

    private var hasGeneratedText: Bool {
        !generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentInputSnapshot: UniversalAIEditInputSnapshot? {
        guard let context else { return nil }

        return UniversalAIEditInputSnapshot(
            instruction: instruction,
            mode: mode,
            context: context
        )
    }

    func show(engine: VoiceInkEngine) {
        guard phase != .capturing else { return }
        guard panel?.isVisible != true else {
            panel?.makeKeyAndOrderFront(nil)
            return
        }

        self.engine = engine
        Task { @MainActor in
            await openPanel(
                engine: engine,
                startVoiceRecording: UniversalAIEditFlow.shouldStartVoiceInstructionOnOpen(panelIsVisible: false)
            )
        }
    }

    func performCommand(engine: VoiceInkEngine) {
        guard phase != .capturing else { return }

        if panel?.isVisible == true {
            panel?.makeKeyAndOrderFront(nil)
            performPrimaryCommandStep()
            return
        }

        self.engine = engine
        Task { @MainActor in
            await openPanel(
                engine: engine,
                startVoiceRecording: UniversalAIEditFlow.shouldStartVoiceInstructionOnOpen(panelIsVisible: false)
            )
        }
    }

    func performPrimaryAction() {
        switch primaryAction {
        case .generate:
            generate()
        case .apply:
            applyResult()
        }
    }

    func performComposerPrimaryAction() {
        switch composerPrimaryAction {
        case .generate, .apply:
            performPrimaryAction()
        }
    }

    func handleEscapeKey() {
        switch UniversalAIEditFlow.escapeAction(
            phase: phase,
            isVoiceRecording: isVoiceRecording,
            instruction: instruction
        ) {
        case .cancelVoiceRecordingAndFocusInstruction:
            cancelVoiceInstructionAndReturnToEditing(focusInstruction: true)
        case .closePanel:
            close()
        case .ignore:
            break
        }
    }

    func handleTabKey() {
        guard let nextMode = UniversalAIEditFlow.toggledMode(
            from: mode,
            phase: phase,
            hasSelection: hasEditableSelection
        ) else {
            return
        }

        mode = nextMode
    }

    func canSelectMode(_ requestedMode: UniversalAIEditMode) -> Bool {
        UniversalAIEditFlow.canSelectMode(
            requestedMode,
            phase: phase,
            hasSelection: hasEditableSelection
        )
    }

    func setMode(_ requestedMode: UniversalAIEditMode) {
        guard canSelectMode(requestedMode) else { return }
        mode = requestedMode
    }

    func registerInstructionTextView(_ textView: NSTextView) {
        instructionTextView = textView
    }

    func savePromptTemplate(id: UUID?, label: String, content: String) {
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLabel.isEmpty,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let now = Date()
        var updatedTemplates = promptTemplates
        if let id,
           let index = updatedTemplates.firstIndex(where: { $0.id == id }) {
            updatedTemplates[index].label = normalizedLabel
            updatedTemplates[index].content = content
            updatedTemplates[index].updatedAt = now
        } else {
            updatedTemplates.append(
                UniversalAIEditPromptTemplate(
                    label: normalizedLabel,
                    content: content,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        promptTemplates = updatedTemplates
        UniversalAIEditPromptTemplateStore.save(promptTemplates)
    }

    func deletePromptTemplate(_ template: UniversalAIEditPromptTemplate) {
        promptTemplates.removeAll { $0.id == template.id }
        UniversalAIEditPromptTemplateStore.save(promptTemplates)
    }

    @discardableResult
    func activatePromptTemplate(_ template: UniversalAIEditPromptTemplate, runAfterInsert: Bool = false) -> Bool {
        guard promptTemplates.contains(where: { $0.id == template.id }) else { return false }
        insertPromptTemplateContent(template.content, runAfterInsert: runAfterInsert)
        return true
    }

    @discardableResult
    func activatePromptTemplateShortcut(number: Int) -> Bool {
        guard number >= 1,
              number <= promptTemplates.count else {
            return false
        }

        return activatePromptTemplate(promptTemplates[number - 1], runAfterInsert: false)
    }

    func updatePanelSize(showingPreview: Bool) {
        guard let panel else { return }

        let size = UniversalAIEditPanelView.contentSize(showingPreview: showingPreview)
        hostingController?.view.frame = NSRect(origin: .zero, size: size)
        panel.contentMinSize = size

        let frameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        var frame = panel.frame
        frame.origin.y = frame.maxY - frameSize.height
        frame.size = frameSize
        panel.setFrame(frame, display: true, animate: false)
    }

    func close() {
        if isVoiceRecording {
            Task { @MainActor in
                await cancelVoiceInstruction()
                discardPendingHistoryRecordIfNeeded(note: String(localized: "Panel closed"))
                hidePanel()
            }
        } else {
            discardPendingHistoryRecordIfNeeded(note: String(localized: "Panel closed"))
            hidePanel()
        }
    }

    func discardPreview() {
        discardPendingHistoryRecordIfNeeded(note: String(localized: "Preview discarded"))
        generatedText = ""
        lastResult = nil
        generatedInputSnapshot = nil
        phase = .ready
        statusText = nil
    }

    func generate() {
        guard canGenerate else { return }
        guard let engine,
              let enhancementService = engine.enhancementService,
              let context else {
            fail(UniversalAIEditError.missingEnhancementService)
            return
        }
        guard let panelSessionID else { return }

        let generationID = UUID()
        activeGenerationID = generationID
        let requestInstruction = instruction
        let requestMode = mode
        let requestContext = context
        let requestInputSnapshot = UniversalAIEditInputSnapshot(
            instruction: requestInstruction,
            mode: requestMode,
            context: requestContext
        )

        Task { @MainActor in
            guard isCurrentGeneration(sessionID: panelSessionID, generationID: generationID) else {
                return
            }
            generatedInputSnapshot = nil
            phase = .generating
            statusText = String(localized: "Generating...")
            do {
                let result = try await editService.generate(
                    instruction: requestInstruction,
                    mode: requestMode,
                    context: requestContext,
                    enhancementService: enhancementService,
                    modelContext: engine.modelContext
                )
                guard isCurrentGeneration(sessionID: panelSessionID, generationID: generationID) else {
                    return
                }
                activeGenerationID = nil
                generatedText = result.text
                lastResult = result
                generatedInputSnapshot = requestInputSnapshot
                discardPendingHistoryRecordIfNeeded(note: String(localized: "Regenerated"))
                currentHistoryRecord = persistHistoryRecord(
                    result: result,
                    instruction: requestInstruction,
                    mode: requestMode,
                    context: requestContext
                )
                phase = .preview
                statusText = String(format: String(localized: "Generated with %@"), result.modelName)
            } catch {
                guard isCurrentGeneration(sessionID: panelSessionID, generationID: generationID) else {
                    return
                }
                activeGenerationID = nil
                fail(error)
            }
        }
    }

    func copyResult() {
        guard canCopyResult else { return }
        _ = ClipboardManager.copyToClipboard(generatedText)
        updateCurrentHistoryRecord(outcome: .copied, clearCurrentRecord: false)
        NotificationManager.shared.showNotification(
            title: String(localized: "AI Edit result copied"),
            type: .success
        )
    }

    func applyResult() {
        guard canApply else { return }

        phase = .applying
        statusText = String(localized: "Applying...")
        let text = generatedText
        let shouldReplaceFocusedInput = UniversalAIEditFlow.shouldReplaceFocusedInputOnApply(
            generatedInputSnapshot: generatedInputSnapshot,
            currentInputSnapshot: currentInputSnapshot
        )

        Task { @MainActor in
            guard let targetApp else {
                _ = ClipboardManager.copyToClipboard(text)
                updateCurrentHistoryRecord(outcome: .copied, note: UniversalAIEditError.targetUnavailable.localizedDescription)
                NotificationManager.shared.showNotification(
                    title: UniversalAIEditError.targetUnavailable.localizedDescription,
                    type: .warning,
                    duration: 5.0
                )
                hidePanel()
                return
            }

            guard AXIsProcessTrusted() else {
                _ = ClipboardManager.copyToClipboard(text)
                updateCurrentHistoryRecord(outcome: .copied, note: UniversalAIEditError.pasteUnavailable.localizedDescription)
                NotificationManager.shared.showNotification(
                    title: UniversalAIEditError.pasteUnavailable.localizedDescription,
                    type: .warning,
                    duration: 5.0,
                    actionButton: (String(localized: "Open Settings"), Self.openAccessibilitySettings)
                )
                hidePanel()
                return
            }

            hidePanel(reactivateTarget: false)
            targetApp.activate(options: [])
            try? await Task.sleep(nanoseconds: 180_000_000)

            if let validationError = validateTargetFocus(targetApp: targetApp, snapshot: context?.target) {
                _ = ClipboardManager.copyToClipboard(text)
                updateCurrentHistoryRecord(outcome: .copied, note: validationError.localizedDescription)
                NotificationManager.shared.showNotification(
                    title: validationError.localizedDescription,
                    type: .warning,
                    duration: 5.0
                )
                return
            }

            if shouldReplaceFocusedInput {
                guard let context,
                      replaceFocusedInputValue(text, context: context, targetApp: targetApp) else {
                    _ = ClipboardManager.copyToClipboard(text)
                    updateCurrentHistoryRecord(outcome: .copied, note: UniversalAIEditError.pasteUnavailable.localizedDescription)
                    NotificationManager.shared.showNotification(
                        title: UniversalAIEditError.pasteUnavailable.localizedDescription,
                        type: .warning,
                        duration: 5.0
                    )
                    return
                }

                updateCurrentHistoryRecord(outcome: .applied)
                return
            }

            let pasteResult = await CursorPaster.pasteAtCursorAndWaitUntilPosted(text)
            if pasteResult.didPostPasteCommand {
                updateCurrentHistoryRecord(outcome: .applied)
            } else {
                _ = ClipboardManager.copyToClipboard(text)
                updateCurrentHistoryRecord(outcome: .copied, note: UniversalAIEditError.pasteUnavailable.localizedDescription)
                NotificationManager.shared.showNotification(
                    title: UniversalAIEditError.pasteUnavailable.localizedDescription,
                    type: .warning,
                    duration: 5.0
                )
            }
        }
    }

    func cancelVoiceInstructionForManualInput() {
        guard isVoiceRecording else { return }

        Task { @MainActor in
            await cancelVoiceInstruction()
            phase = .ready
            statusText = nil
        }
    }

    func cancelVoiceInstructionAndReturnToEditing(focusInstruction: Bool = false) {
        guard isVoiceRecording else { return }

        Task { @MainActor in
            await cancelVoiceInstruction()
            phase = .ready
            statusText = nil
            if focusInstruction {
                requestInstructionFocus()
            }
        }
    }

    func redoVoiceInstruction() {
        guard canRedoVoiceInstruction else { return }

        Task { @MainActor in
            instruction = ""
            generatedText = ""
            lastResult = nil
            generatedInputSnapshot = nil
            statusText = nil
            await startVoiceInstruction()
        }
    }

    func toggleVoiceInstruction() {
        guard canToggleVoiceInstruction else { return }

        Task { @MainActor in
            if isVoiceRecording {
                await stopVoiceInstruction()
            } else {
                await startVoiceInstruction()
            }
        }
    }

    private func performPrimaryCommandStep() {
        switch phase {
        case .idle, .capturing, .transcribingInstruction, .generating, .applying:
            return
        case .listening:
            Task { @MainActor in
                await stopVoiceInstruction()
            }
        case .ready, .failed:
            if canGenerate {
                generate()
            } else {
                Task { @MainActor in
                    await startVoiceInstruction()
                }
            }
        case .preview:
            performPrimaryAction()
        }
    }

    private func insertPromptTemplateContent(_ content: String, runAfterInsert: Bool) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let selectedRange = instructionTextView?.selectedRange()
        let result = UniversalAIEditPromptTemplateInsertion.insert(
            content,
            into: instruction,
            selectedRange: selectedRange
        )
        instruction = result.text
        requestInstructionFocus()

        DispatchQueue.main.async { [weak self] in
            guard let textView = self?.instructionTextView else { return }
            let location = min(result.caretLocation, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        }

        guard runAfterInsert else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.canGenerate else {
                return
            }
            self.generate()
        }
    }

    private func openPanel(engine: VoiceInkEngine, startVoiceRecording: Bool = false) async {
        let launchStart = Date()
        phase = .capturing
        statusText = String(localized: "Capturing context...")
        generatedText = ""
        lastResult = nil
        generatedInputSnapshot = nil
        currentHistoryRecord = nil
        panelSessionID = UUID()
        activeGenerationID = nil
        instruction = ""
        let configuration = resolvedEnhancementConfiguration(engine: engine)
        let launchContext = await contextCaptureService.captureLaunchContext(configuration: configuration)
        context = launchContext
        mode = launchContext.mode
        targetApp = launchContext.target.processIdentifier.flatMap { pid in
            NSRunningApplication(processIdentifier: pid)
        }
        showPanel(autoFocusInstruction: !startVoiceRecording)
        Self.logger.info(
            "AI Edit panel shown after launch context elapsedMs=\(self.elapsedMilliseconds(since: launchStart), privacy: .public) hasSelection=\(launchContext.selectedText != nil, privacy: .public)"
        )
        statusText = contextCaptureStatusText(for: launchContext, configuration: configuration)

        let sessionID = panelSessionID
        let completedContext = await contextCaptureService.captureDeferredScreenContext(
            for: launchContext,
            configuration: configuration
        )
        guard panelSessionID == sessionID,
              panel?.isVisible == true else {
            return
        }

        context = completedContext
        mode = completedContext.mode
        targetApp = completedContext.target.processIdentifier.flatMap { pid in
            NSRunningApplication(processIdentifier: pid)
        }
        statusText = nil
        phase = .ready
        Self.logger.info(
            "AI Edit context ready elapsedMs=\(self.elapsedMilliseconds(since: launchStart), privacy: .public) hasScreenText=\(completedContext.screenText != nil, privacy: .public) hasScreenshot=\(completedContext.screenshotContext != nil, privacy: .public)"
        )
        if UniversalAIEditFlow.shouldStartVoiceInstructionAfterContextCapture(
            requested: startVoiceRecording,
            instruction: instruction,
            panelIsVisible: panel?.isVisible == true
        ) {
            await startVoiceInstruction()
        }
    }

    private func contextCaptureStatusText(
        for context: UniversalAIEditContext,
        configuration: EnhancementRuntimeConfiguration?
    ) -> String {
        if configuration?.useScreenCaptureContext == true {
            return String(localized: "Capturing screen context...")
        }

        return context.selectedText == nil
            ? String(localized: "Finishing capture...")
            : String(localized: "Preparing AI Edit...")
    }

    private func resolvedEnhancementConfiguration(engine: VoiceInkEngine) -> EnhancementRuntimeConfiguration? {
        guard let enhancementService = engine.enhancementService,
              let aiService = enhancementService.getAIService() else {
            return nil
        }

        return ModeRuntimeResolver.currentEnhancementConfiguration(
            enhancementService: enhancementService,
            aiService: aiService
        )
    }

    private func showPanel(autoFocusInstruction: Bool) {
        shouldFocusInstructionOnAppear = autoFocusInstruction
        let size = UniversalAIEditPanelView.contentSize(showingPreview: shouldShowPreview)
        let newPanel = UniversalAIEditPanel(manager: self, size: size)
        let view = UniversalAIEditPanelView(manager: self)
        let controller = NSHostingController(rootView: view)
        controller.view.frame = NSRect(origin: .zero, size: size)
        newPanel.contentView = controller.view
        newPanel.contentMinSize = size
        newPanel.setContentSize(size)
        hostingController = controller
        panel = newPanel
        newPanel.makeKeyAndOrderFront(nil)
    }

    private func hidePanel(reactivateTarget: Bool = true) {
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        panelSessionID = nil
        activeGenerationID = nil
        if reactivateTarget {
            targetApp?.activate(options: [])
        }
        generatedInputSnapshot = nil
        shouldFocusInstructionOnAppear = true
        phase = .idle
        isVoiceRecording = false
        stopVoiceMetering(reset: true)
        instructionAudioURL = nil
        statusText = nil
    }

    private func startVoiceInstruction() async {
        guard !phase.isBusy else { return }
        guard let engine else { return }
        guard ModeRuntimeResolver.transcriptionConfiguration(
            transcriptionModelManager: engine.transcriptionModelManager
        ) != nil else {
            fail(UniversalAIEditError.transcriptionModelMissing)
            return
        }

        let url = engine.recordingsDirectory.appendingPathComponent("ai_edit_instruction_\(UUID().uuidString).wav")
        do {
            try await instructionRecorder.startRecording(
                toOutputFile: url,
                audioBehavior: .muteSystemOutputOnly
            )
            instructionAudioURL = url
            isVoiceRecording = true
            startVoiceMetering()
            phase = .listening
            statusText = String(localized: "Listening...")
        } catch {
            fail(error)
        }
    }

    private func stopVoiceInstruction() async {
        guard isVoiceRecording else { return }
        isVoiceRecording = false
        stopVoiceMetering(reset: true)
        await instructionRecorder.stopRecording()

        guard let engine,
              let audioURL = instructionAudioURL else {
            phase = .ready
            return
        }

        phase = .transcribingInstruction
        statusText = String(localized: "Transcribing instruction...")
        do {
            guard let transcriptionConfiguration = ModeRuntimeResolver.transcriptionConfiguration(
                transcriptionModelManager: engine.transcriptionModelManager
            ) else {
                throw UniversalAIEditError.transcriptionModelMissing
            }

            let enhancementConfiguration = resolvedEnhancementConfiguration(engine: engine)
            let recognitionSnapshot = RecordingContextSnapshot(
                selectedText: context?.selectedText,
                clipboardText: context?.clipboardText,
                screenText: context?.screenText
            )
            let requestContext = TranscriptionRequestContext(
                language: transcriptionConfiguration.language,
                prompt: UniversalAIEditInstructionTranscriptionProcessor.transcriptionPrompt,
                recognitionContext: transcriptionConfiguration.requestContext(
                    recordingContextSnapshot: recognitionSnapshot,
                    sourceSettings: .enhancement(enhancementConfiguration)
                ).recognitionContext
            )
            let text = try await engine.serviceRegistry.transcribe(
                audioURL: audioURL,
                model: transcriptionConfiguration.model,
                context: requestContext
            )
            let locallyCleaned = UniversalAIEditInstructionTranscriptionProcessor.process(
                text,
                modelContext: engine.modelContext
            )
            let trimmed = await enhanceVoiceInstructionIfAvailable(
                locallyCleaned,
                enhancementConfiguration: enhancementConfiguration,
                contextSnapshot: recognitionSnapshot,
                engine: engine
            )
            if !trimmed.isEmpty {
                if instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    instruction = trimmed
                } else {
                    instruction += " " + trimmed
                }
            }
            try? FileManager.default.removeItem(at: audioURL)
            instructionAudioURL = nil
            phase = .ready
            statusText = nil
        } catch {
            try? FileManager.default.removeItem(at: audioURL)
            instructionAudioURL = nil
            fail(error)
        }
    }

    private func enhanceVoiceInstructionIfAvailable(
        _ text: String,
        enhancementConfiguration: EnhancementRuntimeConfiguration?,
        contextSnapshot: RecordingContextSnapshot,
        engine: VoiceInkEngine
    ) async -> String {
        guard !text.isEmpty,
              let enhancementService = engine.enhancementService,
              let enhancementConfiguration,
              enhancementConfiguration.isEnabled else {
            return text
        }

        let instructionConfiguration = enhancementConfiguration.replacingPrompt(
            UniversalAIEditInstructionTranscriptionProcessor.enhancementPrompt
        )
        guard enhancementService.isConfigured(for: instructionConfiguration) else {
            return text
        }

        let savedThreshold = UserDefaults.standard.integer(forKey: "ShortEnhancementWordThreshold")
        let shortEnhancementWordThreshold = savedThreshold > 0 ? savedThreshold : 3
        guard !UniversalAIEditInstructionTranscriptionProcessor.shouldSkipEnhancement(
            text: text,
            isSkipShortEnhancementEnabled: UserDefaults.standard.bool(forKey: "SkipShortEnhancement"),
            wordThreshold: shortEnhancementWordThreshold
        ) else {
            return text
        }

        statusText = String(localized: "Enhancing instruction...")
        do {
            let (enhancedText, _, _) = try await enhancementService.enhance(
                text,
                configuration: instructionConfiguration,
                contextSnapshot: contextSnapshot
            )
            let cleaned = UniversalAIEditInstructionTranscriptionProcessor.localCleanup(enhancedText)
            return cleaned.isEmpty ? text : cleaned
        } catch {
            let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let shortReason = String(errorDescription.prefix(80))
            NotificationManager.shared.showNotification(
                title: String(format: String(localized: "Instruction enhancement failed: %@"), shortReason),
                type: .warning
            )
            return text
        }
    }

    private func cancelVoiceInstruction() async {
        guard isVoiceRecording else { return }
        isVoiceRecording = false
        stopVoiceMetering(reset: true)
        await instructionRecorder.stopRecording()
        if let instructionAudioURL {
            try? FileManager.default.removeItem(at: instructionAudioURL)
        }
        instructionAudioURL = nil
    }

    private func fail(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        isVoiceRecording = false
        stopVoiceMetering(reset: true)
        phase = .failed(message)
        statusText = message
        NotificationManager.shared.showNotification(title: message, type: .error, duration: 5.0)
    }

    private func startVoiceMetering() {
        voiceMeterTask?.cancel()
        voiceMeterSamples = []
        voiceMeterLevel = 0

        voiceMeterTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.isVoiceRecording {
                let level = min(1, max(0, self.instructionRecorder.audioMeter.peakPower))
                self.voiceMeterLevel = level
                self.voiceMeterSamples.append(level)
                if self.voiceMeterSamples.count > 40 {
                    self.voiceMeterSamples.removeFirst(self.voiceMeterSamples.count - 40)
                }

                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    private func stopVoiceMetering(reset: Bool) {
        voiceMeterTask?.cancel()
        voiceMeterTask = nil
        if reset {
            voiceMeterLevel = 0
            voiceMeterSamples = []
        }
    }

    private func requestInstructionFocus() {
        instructionFocusRequest &+= 1
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1000))
    }

    private func isCurrentGeneration(sessionID: UUID, generationID: UUID) -> Bool {
        panelSessionID == sessionID &&
            activeGenerationID == generationID &&
            panel?.isVisible == true
    }

    private func persistHistoryRecord(
        result: UniversalAIEditResult,
        instruction: String,
        mode: UniversalAIEditMode,
        context: UniversalAIEditContext
    ) -> AIEditHistoryRecord? {
        guard let engine else { return nil }
        let record = AIEditHistoryRecord(
            instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: mode,
            sourceText: context.selectedText,
            generatedText: result.text,
            providerName: result.provider.rawValue,
            modelName: result.modelName,
            generationDuration: result.duration,
            target: context.target,
            aiRequestSystemMessage: result.aiRequestSystemMessage,
            aiRequestUserMessage: result.aiRequestUserMessage,
            screenshotContext: result.screenshotContextForHistory
        )

        engine.modelContext.insert(record)
        saveHistoryRecord(record)
        return record
    }

    private func updateCurrentHistoryRecord(
        outcome: AIEditHistoryOutcome,
        note: String? = nil,
        clearCurrentRecord: Bool = true
    ) {
        guard let currentHistoryRecord else { return }
        currentHistoryRecord.recordOutcome(outcome, note: note)
        saveHistoryRecord(currentHistoryRecord)
        if clearCurrentRecord {
            self.currentHistoryRecord = nil
        }
    }

    private func discardPendingHistoryRecordIfNeeded(note: String) {
        guard currentHistoryRecord?.outcome == .generated else { return }
        updateCurrentHistoryRecord(outcome: .discarded, note: note)
    }

    private func saveHistoryRecord(_ record: AIEditHistoryRecord) {
        guard let engine else { return }
        do {
            try engine.modelContext.save()
            NotificationCenter.default.post(name: .aiEditHistoryChanged, object: record)
        } catch {
            print("Error saving AI Edit history record: \(error.localizedDescription)")
        }
    }

    private func validateTargetFocus(
        targetApp: NSRunningApplication,
        snapshot: UniversalAIEditTargetSnapshot?
    ) -> UniversalAIEditError? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier else {
            return .targetUnavailable
        }

        guard let snapshot else {
            return .targetUncertain(String(localized: "missing target details"))
        }

        let capturedTitle = snapshot.focusedWindowTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let capturedFrame = snapshot.focusedWindowFrame
        guard capturedTitle?.isEmpty == false || capturedFrame != nil else {
            return .targetUncertain(String(localized: "window identity was not captured"))
        }

        let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
        guard let focusedWindow = copyAXElementAttribute(kAXFocusedWindowAttribute, from: appElement) else {
            return .targetUncertain(String(localized: "focused window is unavailable"))
        }

        if let capturedTitle, !capturedTitle.isEmpty {
            let currentTitle = copyStringAttribute(kAXTitleAttribute, from: focusedWindow)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard currentTitle == capturedTitle else {
                return .targetUncertain(String(localized: "focused window title changed"))
            }
        }

        if let capturedFrame {
            guard let currentPosition = copyCGPointAttribute(kAXPositionAttribute, from: focusedWindow),
                  let currentSize = copyCGSizeAttribute(kAXSizeAttribute, from: focusedWindow) else {
                return .targetUncertain(String(localized: "focused window frame is unavailable"))
            }

            let currentFrame = CGRect(origin: currentPosition, size: currentSize)
            guard frameDistance(currentFrame, capturedFrame) <= 64 else {
                return .targetUncertain(String(localized: "focused window moved or changed"))
            }
        }

        return nil
    }

    private func replaceFocusedInputValue(
        _ replacementText: String,
        context: UniversalAIEditContext,
        targetApp: NSRunningApplication
    ) -> Bool {
        guard let focusedInput = context.focusedInput,
              let capturedText = context.selectedText,
              focusedInput.text == capturedText else {
            return false
        }

        let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
        guard let focusedElement = copyAXElementAttribute(kAXFocusedUIElementAttribute, from: appElement) else {
            return false
        }

        let role = copyStringAttribute(kAXRoleAttribute, from: focusedElement)
        guard UniversalAIEditFlow.isSupportedFocusedInputRole(role) else {
            return false
        }

        guard let currentText = copyStringAttribute(kAXValueAttribute, from: focusedElement) else {
            return false
        }

        let currentFocusedInput = UniversalAIEditFocusedInputSnapshot(
            text: currentText,
            role: role,
            identifier: normalized(copyStringAttribute(kAXIdentifierAttribute, from: focusedElement)),
            frame: elementFrame(focusedElement),
            isFullTextSelected: isFullTextSelected(in: focusedElement, text: currentText)
        )
        guard UniversalAIEditFlow.focusedInputIdentityMatches(
            captured: focusedInput,
            current: currentFocusedInput
        ) else {
            return false
        }

        return AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            replacementText as CFString
        ) == .success
    }

    private func frameDistance(_ first: CGRect, _ second: CGRect) -> CGFloat {
        abs(first.origin.x - second.origin.x) +
            abs(first.origin.y - second.origin.y) +
            abs(first.size.width - second.size.width) +
            abs(first.size.height - second.size.height)
    }

    private func copyAXElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? String
    }

    private func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isFullTextSelected(in element: AXUIElement, text: String) -> Bool {
        let fullLength = (text as NSString).length
        if let selectedRange = copyCFRangeAttribute(kAXSelectedTextRangeAttribute, from: element),
           selectedRange.location == 0,
           selectedRange.length == fullLength {
            return true
        }

        return copyStringAttribute(kAXSelectedTextAttribute, from: element) == text
    }

    private func copyCGPointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue((value as! AXValue), .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func copyCGSizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue((value as! AXValue), .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func elementFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = copyCGPointAttribute(kAXPositionAttribute, from: element),
              let size = copyCGSizeAttribute(kAXSizeAttribute, from: element) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func copyCFRangeAttribute(_ attribute: String, from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue((value as! AXValue), .cfRange, &range) else {
            return nil
        }

        return range
    }

    private static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

final class UniversalAIEditPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private weak var manager: UniversalAIEditManager?

    init(manager: UniversalAIEditManager, size: NSSize) {
        self.manager = manager
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2 + 44
        )
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.keyCode == 53 {
            manager?.handleEscapeKey()
            return
        }

        if event.type == .keyDown,
           handlePromptTemplateShortcut(event) {
            return
        }

        if event.type == .keyDown,
           event.keyCode == 48,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            manager?.handleTabKey()
            return
        }

        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            manager?.handleEscapeKey()
        } else if handlePromptTemplateShortcut(event) {
            return
        } else if event.keyCode == 48,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            manager?.handleTabKey()
        } else {
            super.keyDown(with: event)
        }
    }

    private func handlePromptTemplateShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers == .command,
              let number = UniversalAIEditPromptTemplateShortcut.number(forKeyCode: event.keyCode) else {
            return false
        }

        return manager?.activatePromptTemplateShortcut(number: number) ?? false
    }
}
