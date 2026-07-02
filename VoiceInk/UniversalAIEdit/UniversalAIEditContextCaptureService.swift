import AppKit
import ApplicationServices
import Foundation

@MainActor
final class UniversalAIEditContextCaptureService {
    func capture(configuration: EnhancementRuntimeConfiguration?) async -> UniversalAIEditContext {
        let target = targetSnapshot()
        async let selectedText = SelectedTextService.fetchSelectedText()
        let clipboardText = configuration?.useClipboardContext == true
            ? NSPasteboard.general.string(forType: .string)
            : nil
        let screenText: String?

        if configuration?.useScreenCaptureContext == true, CGPreflightScreenCaptureAccess() {
            screenText = await ScreenCaptureService().captureAndExtractText()
        } else {
            screenText = nil
        }

        return UniversalAIEditContext(
            capturedAt: Date(),
            target: target,
            selectedText: await selectedText,
            clipboardText: normalized(clipboardText),
            screenText: normalized(screenText)
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
}
