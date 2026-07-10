import AppKit
import ApplicationServices
import Foundation

@MainActor
final class UniversalAIEditContextCaptureService {
    private static let selectAllEventDelay: TimeInterval = 0.01
    private static let postSelectAllCaptureDelay: TimeInterval = 0.15

    func capture(configuration: EnhancementRuntimeConfiguration?) async -> UniversalAIEditContext {
        let target = targetSnapshot()
        var selectedTextResult = await SelectedTextService.captureSelectedText()
        var diagnostics: [UniversalAIEditCaptureDiagnostic] = []

        switch selectedTextResult {
        case .captured:
            break
        case .noSelection:
            if UniversalAIEditFlow.shouldAttemptCommandASelection(
                after: selectionOutcome(from: selectedTextResult)
            ),
               await selectAllWithCommandA(in: target) {
                let targetAfterSelectAll = targetSnapshot()
                if UniversalAIEditFlow.targetContinuityMaintained(
                    before: target,
                    after: targetAfterSelectAll
                ) {
                    selectedTextResult = await SelectedTextService.captureSelectedText()
                } else {
                    diagnostics.append(.selectedTextUnavailable)
                }
            } else {
                diagnostics.append(.selectedTextUnavailable)
            }
        case .accessibilityMissing:
            diagnostics.append(.accessibilityPermissionMissing)
        case .failed:
            diagnostics.append(.selectedTextCaptureFailed)
        }

        let clipboardText = configuration?.useClipboardContext == true
            ? NSPasteboard.general.string(forType: .string)
            : nil
        let screenText: String?
        let screenshotContext: UniversalAIEditScreenshotContext?

        if configuration?.useScreenCaptureContext == true {
            if CGPreflightScreenCaptureAccess() {
                let shouldUseScreenshot = Self.shouldUseScreenshotContext(configuration: configuration)
                if UniversalAIEditScreenshotContextSettings.isEnabled && !shouldUseScreenshot {
                    diagnostics.append(.screenshotContextUnsupported)
                }

                let captureResult = await ScreenCaptureService().captureWindowContext(includeScreenshot: shouldUseScreenshot)
                screenText = captureResult?.contextText
                screenshotContext = captureResult?.screenshotContext

                if captureResult == nil {
                    diagnostics.append(.screenCaptureFailed)
                } else if shouldUseScreenshot && screenshotContext == nil {
                    diagnostics.append(.screenshotContextUnavailable)
                } else if !shouldUseScreenshot && screenText?.contains("No text detected via OCR") == true {
                    diagnostics.append(.screenTextUnavailable)
                }
            } else {
                screenText = nil
                screenshotContext = nil
                diagnostics.append(.screenRecordingPermissionMissing)
            }
        } else {
            screenText = nil
            screenshotContext = nil
            diagnostics.append(.screenContextDisabled)
        }

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

        return UniversalAIEditContext(
            capturedAt: Date(),
            target: target,
            selectedText: selectedText,
            editTargetSource: editTargetSource,
            focusedInput: nil,
            clipboardText: modelBoundText(clipboardText),
            screenText: modelBoundText(screenText),
            screenshotContext: screenshotContext,
            diagnostics: diagnostics
        )
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

    private func selectAllWithCommandA(in target: UniversalAIEditTargetSnapshot) async -> Bool {
        guard let targetProcessIdentifier = target.processIdentifier,
              AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == targetProcessIdentifier else {
            return false
        }

        let source = CGEventSource(stateID: .privateState)
        guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let aDown = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: true),
              let aUp = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
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

    private func wait(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}
