import Foundation

enum TranscriptionContextPolicy {
    static func isKnownOpenAIModel(_ name: String) -> Bool {
        ["gpt-transcribe", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"].contains(
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    static func isEnabled(supported: Bool, isBuiltInOpenAI: Bool, explicitPreference: Bool?) -> Bool {
        supported && (explicitPreference ?? isBuiltInOpenAI)
    }
}

/// Waits for a recording's capture work without blocking the main actor or waiting indefinitely.
@MainActor
final class RecordingContextReadiness {
    private var pendingCount = 0

    func started() { pendingCount += 1 }
    func finished() { pendingCount = max(0, pendingCount - 1) }

    @discardableResult
    func wait(timeout: Duration = .milliseconds(3500)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while pendingCount > 0 {
            guard !Task.isCancelled, clock.now < deadline else { return false }
            do {
                try await Task.sleep(for: min(.milliseconds(20), clock.now.duration(to: deadline)))
            } catch {
                return false
            }
        }
        return true
    }
}
