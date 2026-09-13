import Foundation
import SwiftData

enum TranscriptionStatus: String, Codable {
    case pending
    case completed
    case failed
    case canceled
}

enum TranscriptionScreenshotContextStatus: String, Codable {
    case used
    case fallback

    var displayName: String {
        switch self {
        case .used:
            return String(localized: "Screenshot sent to enhancement")
        case .fallback:
            return String(localized: "Screenshot attempted, OCR fallback used")
        }
    }
}

@Model
final class Transcription {
    static let canceledTranscriptionText = "The transcription was canceled."

    var id: UUID = UUID()
    var text: String = ""
    var enhancedText: String?
    var timestamp: Date = Date()
    var duration: TimeInterval = 0
    var audioFileURL: String?
    var transcriptionModelName: String?
    var aiEnhancementModelName: String?
    var promptName: String?
    var transcriptionDuration: TimeInterval?
    var enhancementDuration: TimeInterval?
    var aiRequestSystemMessage: String?
    var aiRequestUserMessage: String?
    var transcriptionRequestDiagnosticsJSON: String?
    var enhancementDebugStatus: String?
    var screenshotContextData: Data?
    var screenshotContextMediaType: String?
    var screenshotContextWidth: Int?
    var screenshotContextHeight: Int?
    var screenshotContextByteCount: Int?
    var screenshotContextSourceWidth: Int?
    var screenshotContextSourceHeight: Int?
    var screenshotContextDetail: String?
    var screenshotContextApplicationName: String?
    var screenshotContextWindowTitle: String?
    var screenshotContextStatusRawValue: String?
    var screenshotContextFallbackReason: String?
    @Attribute(originalName: "powerModeName")
    var modeName: String?
    @Attribute(originalName: "powerModeEmoji")
    var modeEmoji: String?
    var transcriptionStatus: String?

    init(text: String,
         duration: TimeInterval,
         enhancedText: String? = nil,
         audioFileURL: String? = nil,
         transcriptionModelName: String? = nil,
         aiEnhancementModelName: String? = nil,
         promptName: String? = nil,
         transcriptionDuration: TimeInterval? = nil,
         enhancementDuration: TimeInterval? = nil,
         aiRequestSystemMessage: String? = nil,
         aiRequestUserMessage: String? = nil,
         screenshotContext: UniversalAIEditScreenshotContext? = nil,
         screenshotContextStatus: TranscriptionScreenshotContextStatus? = nil,
         screenshotContextFallbackReason: String? = nil,
         modeName: String? = nil,
         modeEmoji: String? = nil,
         transcriptionStatus: TranscriptionStatus = .pending) {
        self.id = UUID()
        self.text = text
        self.enhancedText = enhancedText
        self.timestamp = Date()
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.transcriptionModelName = transcriptionModelName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.promptName = promptName
        self.transcriptionDuration = transcriptionDuration
        self.enhancementDuration = enhancementDuration
        self.aiRequestSystemMessage = aiRequestSystemMessage
        self.aiRequestUserMessage = aiRequestUserMessage
        recordScreenshotContext(
            screenshotContext,
            status: screenshotContextStatus,
            fallbackReason: screenshotContextFallbackReason
        )
        self.modeName = modeName
        self.modeEmoji = modeEmoji
        self.transcriptionStatus = transcriptionStatus.rawValue
    }

    func markAsCanceledTranscription(
        duration: TimeInterval? = nil,
        modelName: String? = nil
    ) {
        text = Self.canceledTranscriptionText
        enhancedText = nil
        transcriptionStatus = TranscriptionStatus.canceled.rawValue
        if let duration {
            self.duration = duration
        }
        if let modelName {
            transcriptionModelName = modelName
        }
        transcriptionDuration = nil
        enhancementDuration = nil
        aiEnhancementModelName = nil
        promptName = nil
        // Keep diagnostics for requests already attempted, even when delivery is canceled.
    }

    var screenshotContextStatus: TranscriptionScreenshotContextStatus? {
        guard let screenshotContextStatusRawValue else { return nil }
        return TranscriptionScreenshotContextStatus(rawValue: screenshotContextStatusRawValue)
    }

    var hasRetainedScreenshotContext: Bool {
        screenshotContextData?.isEmpty == false
    }

    var transcriptionRequestDiagnostics: [TranscriptionRequestDiagnostics]? {
        guard let json = transcriptionRequestDiagnosticsJSON else { return nil }
        return try? JSONDecoder().decode([TranscriptionRequestDiagnostics].self, from: Data(json.utf8))
    }

    @MainActor
    func recordEnhancementRequest(from service: AIEnhancementService) {
        aiRequestSystemMessage = service.lastSystemMessageSent
        aiRequestUserMessage = service.lastUserMessageSent
        recordScreenshotContext(service.lastScreenshotContextForHistory)
        enhancementDebugStatus = "Enhancement attempted."
    }

    var recognitionContextForInspection: String? {
        let parts = (transcriptionRequestDiagnostics ?? []).enumerated().compactMap { index, request -> String? in
            guard let context = request.recognitionContext, !context.isEmpty else { return nil }
            return "Speech recognition attempt \(index + 1) (\(request.transport)):\n\(context)"
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    var screenContextForInspection: String {
        var parts: [String] = []
        if let recognition = recognitionContextForInspection { parts.append(recognition) }
        if let enhancement = sentCurrentWindowContext {
            parts.append("AI enhancement screen text:\n\(enhancement)")
        }
        if let screenshot = sentScreenshotContextMetadata { parts.append(screenshot) }
        if parts.isEmpty {
            if hasRetainedScreenshotContext {
                return "Screenshot retained for AI enhancement. No screen text was sent to speech recognition."
            }
            return transcriptionRequestDiagnosticsJSON == nil
                ? "Screen context was not saved for this older record. It cannot be reconstructed from current settings."
                : "No screen context was supplied by VoiceInk to the recorded requests."
        }
        return parts.joined(separator: "\n\n")
    }

    var sentCurrentWindowContext: String? {
        if let system = aiRequestSystemMessage,
           let context = Self.taggedContent(named: "CURRENT_WINDOW_CONTEXT", in: system) {
            return context
        }
        if let user = aiRequestUserMessage,
           let context = Self.taggedContent(named: "CURRENT_WINDOW_CONTEXT", in: user) {
            return context
        }
        return nil
    }

    var sentScreenshotContextMetadata: String? {
        guard let userMessage = aiRequestUserMessage else { return nil }
        return Self.taggedContent(named: "ATTACHED_SCREENSHOT_CONTEXT", in: userMessage)
            ?? Self.taggedContent(named: "SCREENSHOT_CONTEXT_FALLBACK", in: userMessage)
    }

    var retainedScreenshotContextMetadata: String? {
        guard hasRetainedScreenshotContext else { return nil }

        var lines: [String] = []
        if let status = screenshotContextStatus {
            lines.append("Status: \(status.displayName)")
        }
        if let fallbackReason = screenshotContextFallbackReason {
            lines.append("Fallback: \(fallbackReason)")
        }
        if let mediaType = screenshotContextMediaType {
            lines.append("Media Type: \(mediaType)")
        }
        if let width = screenshotContextWidth, let height = screenshotContextHeight {
            lines.append("Dimensions: \(width)x\(height)")
        }
        if let sourceWidth = screenshotContextSourceWidth, let sourceHeight = screenshotContextSourceHeight {
            lines.append("Source Dimensions: \(sourceWidth)x\(sourceHeight)")
        }
        if let byteCount = screenshotContextByteCount {
            lines.append("Compressed Bytes: \(byteCount)")
        }
        if let detail = screenshotContextDetail {
            lines.append("Detail: \(detail)")
        }
        if let applicationName = screenshotContextApplicationName {
            lines.append("Application: \(applicationName)")
        }
        if let windowTitle = screenshotContextWindowTitle {
            lines.append("Window: \(windowTitle)")
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    func recordScreenshotContext(_ history: AIEnhancementScreenshotContextHistory?) {
        guard let history else {
            clearScreenshotContext()
            return
        }

        recordScreenshotContext(
            history.screenshotContext,
            status: history.status,
            fallbackReason: history.fallbackReason
        )
    }

    private func recordScreenshotContext(
        _ screenshotContext: UniversalAIEditScreenshotContext?,
        status: TranscriptionScreenshotContextStatus?,
        fallbackReason: String?
    ) {
        guard let screenshotContext else {
            clearScreenshotContext()
            return
        }

        screenshotContextData = screenshotContext.data
        screenshotContextMediaType = Self.normalized(screenshotContext.mediaType)
        screenshotContextWidth = screenshotContext.width
        screenshotContextHeight = screenshotContext.height
        screenshotContextByteCount = screenshotContext.byteCount
        screenshotContextSourceWidth = screenshotContext.sourceWidth
        screenshotContextSourceHeight = screenshotContext.sourceHeight
        screenshotContextDetail = Self.normalized(screenshotContext.detail)
        screenshotContextApplicationName = Self.normalized(screenshotContext.applicationName)
        screenshotContextWindowTitle = Self.normalized(screenshotContext.windowTitle)
        screenshotContextStatusRawValue = status?.rawValue
        screenshotContextFallbackReason = Self.normalized(fallbackReason)
    }

    private func clearScreenshotContext() {
        screenshotContextData = nil
        screenshotContextMediaType = nil
        screenshotContextWidth = nil
        screenshotContextHeight = nil
        screenshotContextByteCount = nil
        screenshotContextSourceWidth = nil
        screenshotContextSourceHeight = nil
        screenshotContextDetail = nil
        screenshotContextApplicationName = nil
        screenshotContextWindowTitle = nil
        screenshotContextStatusRawValue = nil
        screenshotContextFallbackReason = nil
    }

    private static func taggedContent(named tagName: String, in text: String) -> String? {
        let openTag = "<\(tagName)>"
        let closeTag = "</\(tagName)>"
        guard let openRange = text.range(of: openTag),
              let closeRange = text.range(of: closeTag, range: openRange.upperBound..<text.endIndex) else {
            return nil
        }

        var content = String(text[openRange.upperBound..<closeRange.lowerBound])
        if content.first == "\n" {
            content.removeFirst()
        }
        if content.last == "\n" {
            content.removeLast()
        }

        return normalized(content)
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }
}
