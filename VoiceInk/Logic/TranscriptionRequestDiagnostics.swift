import Foundation

/// Inputs supplied by VoiceInk to a speech-to-text adapter. Never contains credentials or audio.
struct TranscriptionRequestDiagnostics: Codable, Equatable, Sendable {
    let model: String
    let provider: String
    let transport: String
    let language: String?
    let prompt: String?
    let recognitionContext: String?
    let notes: String

    var inspectionText: String {
        """
        Model: \(model)
        Provider: \(provider)
        Transport: \(transport)
        Language setting: \(language ?? "auto")
        System prompt: No separate system message supplied by VoiceInk.

        Transcription prompt:
        \(prompt?.isEmpty == false ? prompt! : "No transcription prompt supplied on this path.")

        Recognition context:
        \(recognitionContext ?? "No screen, selection, or clipboard text supplied to speech recognition.")

        \(notes)
        """
    }
}

/// A recording owns its recorder, including streaming and any file fallback attempts.
/// Services can report from any executor without touching SwiftData off the main actor.
final class TranscriptionDiagnosticsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TranscriptionRequestDiagnostics] = []

    func record(_ request: TranscriptionRequestDiagnostics) {
        lock.withLock { storage.append(request) }
    }

    var requests: [TranscriptionRequestDiagnostics] {
        lock.withLock { storage }
    }

    var encodedRequests: String? {
        guard let data = try? JSONEncoder().encode(requests) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
