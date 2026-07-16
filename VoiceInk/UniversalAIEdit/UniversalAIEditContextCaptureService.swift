import AppKit
import ApplicationServices
import Foundation
import os

@MainActor
final class UniversalAIEditContextCaptureService {
    private static let selectAllEventDelay: TimeInterval = 0.01
    private static let postSelectAllCaptureDelay: TimeInterval = 0.15
    private static let postSelectionCollapseDelay: TimeInterval = 0.08
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "UniversalAIEditCapture")

    func capture(configuration: EnhancementRuntimeConfiguration?) async -> UniversalAIEditContext {
        let launchContext = await captureLaunchContext(configuration: configuration)
        return await captureDeferredScreenContext(for: launchContext, configuration: configuration)
    }

    func captureLaunchContext(configuration: EnhancementRuntimeConfiguration?) async -> UniversalAIEditContext {
        let captureStart = Date()
        let target = targetSnapshot()
        var targetForContext = target
        let focusedSelectionPresence = focusedSelectionPresence(in: target)
        Self.logger.info(
            "AI Edit capture target app=\(target.appName ?? "nil", privacy: .public) bundle=\(target.bundleIdentifier ?? "nil", privacy: .public) pid=\(target.processIdentifier ?? -1, privacy: .public) focusedSelection=\(String(describing: focusedSelectionPresence), privacy: .public)"
        )
        let initialSelectionStart = Date()
        var selectedTextResult = await SelectedTextService.captureSelectedText()
        Self.logger.info(
            "AI Edit initial selected text capture outcome=\(self.describe(selectedTextResult), privacy: .public) elapsedMs=\(self.elapsedMilliseconds(since: initialSelectionStart), privacy: .public)"
        )
        var diagnostics: [UniversalAIEditCaptureDiagnostic] = []
        var didPostCommandA = false

        switch selectedTextResult {
        case .captured:
            break
        case .noSelection, .failed:
            let commandAStart = Date()
            if UniversalAIEditFlow.shouldAttemptCommandASelection(
                after: selectionOutcome(from: selectedTextResult),
                focusedSelectionPresence: focusedSelectionPresence
            ),
               await selectAllWithCommandA(in: target) {
                didPostCommandA = true
                let targetAfterSelectAll = targetSnapshot()
                let continuityMaintained = UniversalAIEditFlow.targetContinuityMaintained(
                    before: target,
                    after: targetAfterSelectAll
                )
                Self.logger.info(
                    "AI Edit Command-A posted; target continuity=\(continuityMaintained, privacy: .public) afterApp=\(targetAfterSelectAll.appName ?? "nil", privacy: .public) afterBundle=\(targetAfterSelectAll.bundleIdentifier ?? "nil", privacy: .public) afterPid=\(targetAfterSelectAll.processIdentifier ?? -1, privacy: .public)"
                )
                if continuityMaintained {
                    selectedTextResult = await SelectedTextService.captureSelectedText()
                    Self.logger.info(
                        "AI Edit post-Command-A selected text capture outcome=\(self.describe(selectedTextResult), privacy: .public) elapsedMs=\(self.elapsedMilliseconds(since: commandAStart), privacy: .public)"
                    )
                } else {
                    diagnostics.append(.selectedTextUnavailable)
                }
            } else {
                Self.logger.info(
                    "AI Edit skipped Command-A; outcome=\(self.describe(selectedTextResult), privacy: .public) focusedSelection=\(String(describing: focusedSelectionPresence), privacy: .public)"
                )
                diagnostics.append(.selectedTextUnavailable)
            }
        case .accessibilityMissing:
            diagnostics.append(.accessibilityPermissionMissing)
        }

        if UniversalAIEditFlow.shouldClearUnacceptedCommandASelection(
            didPostCommandA: didPostCommandA,
            selectionWasAccepted: selectedTextResult.text != nil
        ) {
            let didClearSelection = await collapseSelectionAfterCommandA(in: target)
            Self.logger.info(
                "AI Edit Command-A selection not accepted; cleanup posted=\(didClearSelection, privacy: .public)"
            )
            if !didClearSelection {
                targetForContext = copyOnlyTarget(from: target)
                Self.logger.info("AI Edit using copy-only target after unaccepted Command-A selection")
            }
        }

        let clipboardText = configuration?.useClipboardContext == true
            ? NSPasteboard.general.string(forType: .string)
            : nil

        let selectedText = selectedTextResult.text
        var editTargetSource: UniversalAIEditEditTargetSource?

        switch selectedTextResult {
        case .captured:
            editTargetSource = .explicitSelection
        case .noSelection:
            if !diagnostics.contains(.selectedTextUnavailable) {
                diagnostics.append(.selectedTextUnavailable)
            }
        case .failed:
            if !diagnostics.contains(.selectedTextCaptureFailed) {
                diagnostics.append(.selectedTextCaptureFailed)
            }
        case .accessibilityMissing:
            if !diagnostics.contains(.accessibilityPermissionMissing) {
                diagnostics.append(.accessibilityPermissionMissing)
            }
        }

        let context = UniversalAIEditContext(
            capturedAt: Date(),
            target: targetForContext,
            selectedText: selectedText,
            editTargetSource: editTargetSource,
            focusedInput: nil,
            clipboardText: modelBoundText(clipboardText),
            screenText: nil,
            screenshotContext: nil,
            diagnostics: diagnostics
        )
        Self.logger.info(
            "AI Edit launch context captured elapsedMs=\(self.elapsedMilliseconds(since: captureStart), privacy: .public) hasSelection=\(context.selectedText != nil, privacy: .public)"
        )
        return context
    }

    func captureDeferredScreenContext(
        for context: UniversalAIEditContext,
        configuration: EnhancementRuntimeConfiguration?
    ) async -> UniversalAIEditContext {
        let screenStart = Date()
        let result = await captureScreenContext(
            configuration: configuration,
            target: context.target
        )
        let diagnostics = context.diagnostics.mergingUnique(result.diagnostics)
        let diagnosticValues = result.diagnostics.map(\.rawValue).joined(separator: ",")
        Self.logger.info(
            "AI Edit deferred screen context captured elapsedMs=\(self.elapsedMilliseconds(since: screenStart), privacy: .public) hasScreenText=\(result.screenText != nil, privacy: .public) hasScreenshot=\(result.screenshotContext != nil, privacy: .public) diagnostics=\(diagnosticValues, privacy: .public)"
        )

        return UniversalAIEditContext(
            capturedAt: context.capturedAt,
            target: context.target,
            selectedText: context.selectedText,
            editTargetSource: context.editTargetSource,
            focusedInput: context.focusedInput,
            clipboardText: context.clipboardText,
            screenText: modelBoundText(result.screenText),
            screenshotContext: result.screenshotContext,
            diagnostics: diagnostics
        )
    }

    func contextWithScreenContextDisabled(_ context: UniversalAIEditContext) -> UniversalAIEditContext {
        UniversalAIEditContext(
            capturedAt: context.capturedAt,
            target: context.target,
            selectedText: context.selectedText,
            editTargetSource: context.editTargetSource,
            focusedInput: context.focusedInput,
            clipboardText: context.clipboardText,
            screenText: context.screenText,
            screenshotContext: context.screenshotContext,
            diagnostics: context.diagnostics.mergingUnique([.screenContextDisabled])
        )
    }

    private func describe(_ result: SelectedTextService.CaptureResult) -> String {
        switch result {
        case .captured(let text):
            return "captured(length=\(text.count))"
        case .noSelection:
            return "noSelection"
        case .accessibilityMissing:
            return "accessibilityMissing"
        case .failed(let message):
            return "failed(\(message))"
        }
    }

    private func selectionOutcome(
        from result: SelectedTextService.CaptureResult
    ) -> UniversalAIEditSelectionCaptureOutcome {
        switch result {
        case .captured:
            return .captured
        case .noSelection:
            return .noSelection
        case .accessibilityMissing:
            return .accessibilityMissing
        case .failed:
            return .failed
        }
    }

    private static func shouldUseScreenshotContext(configuration: EnhancementRuntimeConfiguration?) -> Bool {
        guard UniversalAIEditScreenshotContextSettings.isEnabled,
              configuration?.useScreenCaptureContext == true,
              let provider = configuration?.provider else {
            return false
        }

        let modelName = configuration?.modelName ?? provider.defaultModel
        return UniversalAIEditScreenshotCapability.supportsScreenshotContext(
            provider: provider,
            modelName: modelName
        )
    }

    private struct ScreenCaptureOutcome {
        let screenText: String?
        let screenshotContext: UniversalAIEditScreenshotContext?
        let diagnostics: [UniversalAIEditCaptureDiagnostic]
    }

    private func captureScreenContext(
        configuration: EnhancementRuntimeConfiguration?,
        target: UniversalAIEditTargetSnapshot
    ) async -> ScreenCaptureOutcome {
        var diagnostics: [UniversalAIEditCaptureDiagnostic] = []

        guard configuration?.useScreenCaptureContext == true else {
            return ScreenCaptureOutcome(
                screenText: nil,
                screenshotContext: nil,
                diagnostics: [.screenContextDisabled]
            )
        }

        guard CGPreflightScreenCaptureAccess() else {
            return ScreenCaptureOutcome(
                screenText: nil,
                screenshotContext: nil,
                diagnostics: [.screenRecordingPermissionMissing]
            )
        }

        guard target.processIdentifier != nil else {
            return ScreenCaptureOutcome(
                screenText: nil,
                screenshotContext: nil,
                diagnostics: [.screenCaptureFailed]
            )
        }

        let shouldUseScreenshot = Self.shouldUseScreenshotContext(configuration: configuration)
        if UniversalAIEditScreenshotContextSettings.isEnabled && !shouldUseScreenshot {
            diagnostics.append(.screenshotContextUnsupported)
        }

        let captureResult: ActiveWindowCaptureResult?
        if let hint = screenCaptureHint(from: target) {
            captureResult = await ScreenCaptureService().captureWindowContext(
                includeScreenshot: shouldUseScreenshot,
                targetWindowHint: hint
            )
        } else {
            captureResult = await ScreenCaptureService().captureWindowContext(includeScreenshot: shouldUseScreenshot)
        }

        let screenText = captureResult?.contextText
        let screenshotContext = captureResult?.screenshotContext

        if captureResult == nil {
            diagnostics.append(.screenCaptureFailed)
        } else if shouldUseScreenshot && screenshotContext == nil {
            diagnostics.append(.screenshotContextUnavailable)
        } else if !shouldUseScreenshot && screenText?.contains("No text detected via OCR") == true {
            diagnostics.append(.screenTextUnavailable)
        }

        return ScreenCaptureOutcome(
            screenText: screenText,
            screenshotContext: screenshotContext,
            diagnostics: diagnostics
        )
    }

    private func screenCaptureHint(from target: UniversalAIEditTargetSnapshot) -> ScreenCaptureWindowHint? {
        guard let processIdentifier = target.processIdentifier else {
            return nil
        }

        return ScreenCaptureWindowHint(
            processID: processIdentifier,
            title: target.focusedWindowTitle,
            frame: target.focusedWindowFrame
        )
    }

    private func targetSnapshot() -> UniversalAIEditTargetSnapshot {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let appForTarget = frontmostApp?.processIdentifier == currentPID ? nil : frontmostApp
        var focusedTitle: String?
        var focusedFrame: CGRect?

        if let appForTarget, AXIsProcessTrusted() {
            let appElement = AXUIElementCreateApplication(appForTarget.processIdentifier)
            if let focusedWindow = copyAXElementAttribute(kAXFocusedWindowAttribute, from: appElement) {
                focusedTitle = normalized(copyStringAttribute(kAXTitleAttribute, from: focusedWindow))

                if let position = copyCGPointAttribute(kAXPositionAttribute, from: focusedWindow),
                   let size = copyCGSizeAttribute(kAXSizeAttribute, from: focusedWindow) {
                    focusedFrame = CGRect(origin: position, size: size)
                }
            }
        }

        return UniversalAIEditTargetSnapshot(
            appName: appForTarget?.localizedName,
            bundleIdentifier: appForTarget?.bundleIdentifier,
            processIdentifier: appForTarget?.processIdentifier,
            focusedWindowTitle: focusedTitle,
            focusedWindowFrame: focusedFrame
        )
    }

    private func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func modelBoundText(_ text: String?) -> String? {
        guard let text else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
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

    private func focusedSelectionPresence(in target: UniversalAIEditTargetSnapshot) -> UniversalAIEditSelectionPresence {
        guard let targetProcessIdentifier = target.processIdentifier,
              AXIsProcessTrusted() else {
            return .unknown
        }

        let appElement = AXUIElementCreateApplication(targetProcessIdentifier)
        guard let focusedElement = copyAXElementAttribute(kAXFocusedUIElementAttribute, from: appElement) else {
            return .unknown
        }

        if let selectedText = copyStringAttribute(kAXSelectedTextAttribute, from: focusedElement) {
            return selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .noSelection : .hasSelection
        }

        if let selectedRange = copyCFRangeAttribute(kAXSelectedTextRangeAttribute, from: focusedElement) {
            return selectedRange.length > 0 ? .hasSelection : .noSelection
        }

        return .unknown
    }

    private func copyOnlyTarget(from target: UniversalAIEditTargetSnapshot) -> UniversalAIEditTargetSnapshot {
        UniversalAIEditTargetSnapshot(
            appName: target.appName,
            bundleIdentifier: target.bundleIdentifier,
            processIdentifier: nil,
            focusedWindowTitle: target.focusedWindowTitle,
            focusedWindowFrame: target.focusedWindowFrame
        )
    }

    private func selectAllWithCommandA(in target: UniversalAIEditTargetSnapshot) async -> Bool {
        guard let targetProcessIdentifier = target.processIdentifier else {
            Self.logger.info("AI Edit Command-A not posted; missing target process")
            return false
        }

        guard AXIsProcessTrusted() else {
            Self.logger.info("AI Edit Command-A not posted; Accessibility unavailable")
            return false
        }

        let frontmostProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard frontmostProcessIdentifier == targetProcessIdentifier else {
            Self.logger.info(
                "AI Edit Command-A not posted; target pid=\(targetProcessIdentifier, privacy: .public) frontmost pid=\(frontmostProcessIdentifier ?? -1, privacy: .public)"
            )
            return false
        }

        let source = CGEventSource(stateID: .privateState)
        guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let aDown = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: true),
              let aUp = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            Self.logger.info("AI Edit Command-A not posted; failed to create keyboard events")
            return false
        }

        commandDown.flags = .maskCommand
        aDown.flags = .maskCommand
        aUp.flags = .maskCommand

        commandDown.post(tap: .cghidEventTap)
        await wait(Self.selectAllEventDelay)
        aDown.post(tap: .cghidEventTap)
        await wait(Self.selectAllEventDelay)
        aUp.post(tap: .cghidEventTap)
        await wait(Self.selectAllEventDelay)
        commandUp.post(tap: .cghidEventTap)
        await wait(Self.postSelectAllCaptureDelay)
        return true
    }

    private func collapseSelectionAfterCommandA(in target: UniversalAIEditTargetSnapshot) async -> Bool {
        guard let targetProcessIdentifier = target.processIdentifier,
              AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == targetProcessIdentifier else {
            Self.logger.info(
                "AI Edit Command-A cleanup skipped; target is not frontmost or Accessibility unavailable"
            )
            return false
        }

        let source = CGEventSource(stateID: .privateState)
        guard let rightArrowDown = CGEvent(keyboardEventSource: source, virtualKey: 0x7C, keyDown: true),
              let rightArrowUp = CGEvent(keyboardEventSource: source, virtualKey: 0x7C, keyDown: false) else {
            return false
        }

        rightArrowDown.post(tap: .cghidEventTap)
        await wait(Self.selectAllEventDelay)
        rightArrowUp.post(tap: .cghidEventTap)
        await wait(Self.postSelectionCollapseDelay)
        return true
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

    private func wait(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1000))
    }
}

private extension Array where Element == UniversalAIEditCaptureDiagnostic {
    func mergingUnique(_ other: [UniversalAIEditCaptureDiagnostic]) -> [UniversalAIEditCaptureDiagnostic] {
        var result = self
        for diagnostic in other where !result.contains(diagnostic) {
            result.append(diagnostic)
        }
        return result
    }
}
