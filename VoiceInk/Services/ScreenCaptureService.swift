import Foundation
import AppKit
import ImageIO
import Vision
import ScreenCaptureKit
import ApplicationServices
import UniformTypeIdentifiers

struct ActiveWindowCaptureResult {
    let contextText: String
    let screenshotContext: UniversalAIEditScreenshotContext?
}

@MainActor
class ScreenCaptureService: ObservableObject {
    @Published var isCapturing = false
    @Published var lastCapturedText: String?

    private struct FocusedWindowHint: Sendable {
        let processID: pid_t
        let title: String?
        let frame: CGRect?
    }

    private static let captureTimeout: TimeInterval = 3.0
    private static let maximumCaptureDimension: CGFloat = 2800
    private static let screenshotContextMaxDimension: CGFloat = 1920
    private static let screenshotContextJPEGQuality: CGFloat = 0.85
    private static let screenshotContextDetail = "high"
    private static let focusedWindowFrameTolerance: CGFloat = 96

    static func requestScreenCapturePermissionRegistration() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        if CGRequestScreenCaptureAccess() {
            return true
        }

        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            return CGPreflightScreenCaptureAccess()
        }

        return CGPreflightScreenCaptureAccess()
    }

    func captureAndExtractText() async -> String? {
        await captureWindowContext(includeScreenshot: false)?.contextText
    }

    func captureWindowContext(includeScreenshot: Bool) async -> ActiveWindowCaptureResult? {
        guard !isCapturing else { return nil }

        isCapturing = true
        defer {
            isCapturing = false
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let focusedWindowHint = makeFocusedWindowHint(excluding: currentPID)

        guard let result = await Self.withTimeout(seconds: Self.captureTimeout, operation: {
            await Self.captureWindowContext(
                focusedWindowHint: focusedWindowHint,
                currentPID: currentPID,
                includeScreenshot: includeScreenshot
            )
        }) else {
            return nil
        }

        lastCapturedText = result.contextText
        return result
    }

    private func makeFocusedWindowHint(excluding currentPID: pid_t) -> FocusedWindowHint? {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              frontmostPID != currentPID else {
            return nil
        }

        var focusedTitle: String?
        var focusedFrame: CGRect?

        if AXIsProcessTrusted() {
            let appElement = AXUIElementCreateApplication(frontmostPID)
            if let focusedWindow = copyAXElementAttribute(kAXFocusedWindowAttribute, from: appElement) {
                focusedTitle = normalized(copyStringAttribute(kAXTitleAttribute, from: focusedWindow))

                if let position = copyCGPointAttribute(kAXPositionAttribute, from: focusedWindow),
                   let size = copyCGSizeAttribute(kAXSizeAttribute, from: focusedWindow) {
                    focusedFrame = CGRect(origin: position, size: size)
                }
            }
        }

        return FocusedWindowHint(
            processID: frontmostPID,
            title: focusedTitle,
            frame: focusedFrame
        )
    }

    private nonisolated static func captureWindowContext(
        focusedWindowHint: FocusedWindowHint?,
        currentPID: pid_t,
        includeScreenshot: Bool
    ) async -> ActiveWindowCaptureResult? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let window = findActiveWindow(
                in: content.windows,
                focusedWindowHint: focusedWindowHint,
                currentPID: currentPID
            ) else {
                return nil
            }

            let title = window.title ?? window.owningApplication?.applicationName ?? "Unknown"
            let appName = window.owningApplication?.applicationName ?? "Unknown"

            let filter = SCContentFilter(desktopIndependentWindow: window)

            let configuration = SCStreamConfiguration()
            let captureScale = captureScale(for: window.frame.size)
            configuration.width = max(1, Int(window.frame.width * captureScale))
            configuration.height = max(1, Int(window.frame.height * captureScale))

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

            var contextText = """
            Active Window: \(title)
            Application: \(appName)

            """

            let extractedText = extractText(from: cgImage)
            if let extractedText, !extractedText.isEmpty {
                contextText += "Window Content:\n\(extractedText)"
            } else {
                contextText += "Window Content:\nNo text detected via OCR"
            }

            let screenshotContext = includeScreenshot
                ? makeScreenshotContext(from: cgImage, appName: appName, windowTitle: title)
                : nil

            return ActiveWindowCaptureResult(
                contextText: contextText,
                screenshotContext: screenshotContext
            )

        } catch {
            return nil
        }
    }

    private nonisolated static func findActiveWindow(
        in windows: [SCWindow],
        focusedWindowHint: FocusedWindowHint?,
        currentPID: pid_t
    ) -> SCWindow? {
        let candidates = windows.filter { window in
            guard let processID = window.owningApplication?.processID else {
                return false
            }

            return processID != currentPID &&
                window.windowLayer == 0 &&
                window.isOnScreen &&
                window.frame.width > 0 &&
                window.frame.height > 0
        }

        guard let focusedWindowHint else {
            return candidates.first
        }

        let appWindows = candidates.filter {
            $0.owningApplication?.processID == focusedWindowHint.processID
        }

        guard !appWindows.isEmpty else {
            return candidates.first
        }

        if let focusedFrame = focusedWindowHint.frame,
           let closestWindow = closestFrameMatch(to: focusedFrame, in: appWindows),
           frameDistance(closestWindow.frame, focusedFrame) <= focusedWindowFrameTolerance {
            return closestWindow
        }

        if let focusedTitle = focusedWindowHint.title,
           let titledWindow = appWindows.first(where: { normalized($0.title) == focusedTitle }) {
            return titledWindow
        }

        return appWindows.first
    }

    private nonisolated static func closestFrameMatch(to frame: CGRect, in windows: [SCWindow]) -> SCWindow? {
        windows.min {
            frameDistance($0.frame, frame) < frameDistance($1.frame, frame)
        }
    }

    private nonisolated static func frameDistance(_ first: CGRect, _ second: CGRect) -> CGFloat {
        abs(first.origin.x - second.origin.x) +
            abs(first.origin.y - second.origin.y) +
            abs(first.size.width - second.size.width) +
            abs(first.size.height - second.size.height)
    }

    private nonisolated static func captureScale(for size: CGSize) -> CGFloat {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else {
            return 1
        }

        return min(2, maximumCaptureDimension / longestSide)
    }

    private nonisolated static func extractText(from cgImage: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try requestHandler.perform([request])
            guard let observations = request.results else {
                return nil
            }
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    private nonisolated static func makeScreenshotContext(
        from cgImage: CGImage,
        appName: String,
        windowTitle: String
    ) -> UniversalAIEditScreenshotContext? {
        guard let encoded = encodeJPEGForScreenshotContext(cgImage) else {
            return nil
        }

        return UniversalAIEditScreenshotContext(
            data: encoded.data,
            mediaType: "image/jpeg",
            width: encoded.width,
            height: encoded.height,
            byteCount: encoded.data.count,
            sourceWidth: cgImage.width,
            sourceHeight: cgImage.height,
            detail: screenshotContextDetail,
            applicationName: appName,
            windowTitle: windowTitle
        )
    }

    private nonisolated static func encodeJPEGForScreenshotContext(_ cgImage: CGImage) -> (data: Data, width: Int, height: Int)? {
        let sourceWidth = cgImage.width
        let sourceHeight = cgImage.height
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let longestSide = max(sourceWidth, sourceHeight)
        let scale = min(1, screenshotContextMaxDimension / CGFloat(longestSide))
        let outputWidth = max(1, Int((CGFloat(sourceWidth) * scale).rounded()))
        let outputHeight = max(1, Int((CGFloat(sourceHeight) * scale).rounded()))

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: outputWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

        guard let outputImage = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: CFDictionary = [
            kCGImageDestinationLossyCompressionQuality: screenshotContextJPEGQuality
        ] as CFDictionary

        CGImageDestinationAddImage(destination, outputImage, options)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return (data as Data, outputWidth, outputHeight)
    }

    private nonisolated static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
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
              CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cgPoint else {
            return nil
        }

        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func copyCGSizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cgSize else {
            return nil
        }

        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private nonisolated static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalized(_ text: String?) -> String? {
        Self.normalized(text)
    }
}
