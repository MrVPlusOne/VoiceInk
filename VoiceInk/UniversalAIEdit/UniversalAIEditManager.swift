import AppKit
import Foundation
import SwiftUI

@MainActor
final class UniversalAIEditManager: ObservableObject {
    static let shared = UniversalAIEditManager()

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

    var primaryAction: UniversalAIEditPrimaryAction {
        UniversalAIEditFlow.primaryAction(
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
            await openPanel(engine: engine)
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
            await openPanel(engine: engine, startVoiceRecording: true)
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

    func cancelVoiceInstructionAndReturnToEditing() {
        guard isVoiceRecording else { return }

        Task { @MainActor in
            await cancelVoiceInstruction()
            phase = .ready
            statusText = nil
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

    private func openPanel(engine: VoiceInkEngine, startVoiceRecording: Bool = false) async {
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
        let capturedContext = await contextCaptureService.capture(configuration: configuration)
        context = capturedContext
        mode = capturedContext.mode
        targetApp = capturedContext.target.processIdentifier.flatMap { pid in
            NSRunningApplication(processIdentifier: pid)
        }
        statusText = nil
        phase = .ready
        showPanel(autoFocusInstruction: !startVoiceRecording)
        if startVoiceRecording {
            await startVoiceInstruction()
        }
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
        let size = UniversalAIEditPanelView.preferredContentSize
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
            try await instructionRecorder.startRecording(toOutputFile: url)
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

            let requestContext = TranscriptionRequestContext(
                language: transcriptionConfiguration.language,
                prompt: String(localized: "Transcribe this as a concise editing instruction. Preserve requested tone, length, audience, and formatting changes.")
            )
            let text = try await engine.serviceRegistry.transcribe(
                audioURL: audioURL,
                model: transcriptionConfiguration.model,
                context: requestContext
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
            aiRequestUserMessage: result.aiRequestUserMessage
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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            manager?.close()
        } else {
            super.keyDown(with: event)
        }
    }
}
