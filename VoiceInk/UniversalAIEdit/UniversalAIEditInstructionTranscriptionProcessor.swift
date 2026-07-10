import Foundation
import SwiftData

enum UniversalAIEditInstructionTranscriptionProcessor {
    /// AI Edit instructions are commands, not final prose. Keep post-STT cleanup minimal
    /// so literal command targets like "[TODO]", "(beta)", or "<code>" survive.
    static func process(_ rawText: String, modelContext _: ModelContext) -> String {
        localCleanup(rawText)
    }

    static func localCleanup(_ rawText: String) -> String {
        rawText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var usesAIEnhancement: Bool {
        false
    }

    static var appliesWordReplacements: Bool {
        false
    }
}
