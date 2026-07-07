import Foundation
import ApplicationServices
import os
import SelectedTextKit

@MainActor
final class SelectedTextService {
    enum CaptureResult: Equatable {
        case captured(String)
        case noSelection
        case accessibilityMissing
        case failed(String)

        var text: String? {
            switch self {
            case .captured(let text):
                return text
            case .noSelection, .accessibilityMissing, .failed:
                return nil
            }
        }
    }

    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SelectedTextService")
    private static let textManager = SelectedTextManager.shared
    private static let selectedTextStrategies: [TextStrategy] = [
        .accessibility,
        .menuAction,
        .appleScript
    ]

    static func fetchSelectedText() async -> String? {
        await captureSelectedText().text
    }

    static func captureSelectedText() async -> CaptureResult {
        guard AXIsProcessTrusted() else {
            logger.debug("Accessibility is not trusted; selected text capture skipped")
            return .accessibilityMissing
        }

        do {
            if let text = normalized(try await textManager.getSelectedText(strategies: selectedTextStrategies)) {
                return .captured(text)
            }
            return .noSelection
        } catch {
            logger.debug("SelectedTextKit failed to capture selected text: \(error, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
