import Foundation
import SwiftData

enum UniversalAIEditInstructionTranscriptionProcessor {
    static let transcriptionPrompt = String(localized: "Transcribe the speech in the original spoken language as a concise AI Edit instruction. Do not translate unless the speaker explicitly asks for translation. Preserve command intent, requested tone, length, audience, formatting changes, and literal operands.")

    static let enhancementPrompt = CustomPrompt(
        title: "AI Edit instruction cleanup",
        promptText: """
        Clean up this transcribed instruction for AI Edit.
        Preserve the original spoken language; do not translate unless the instruction explicitly asks for translation.
        Preserve command intent and rewrite ambiguous wording as an instruction for AI Edit.
        Fix only transcription errors, punctuation, spacing, grammar, and obvious spoken self-corrections.
        Preserve literal command operands exactly, including square-bracket TODO markers, parenthesized labels, braced placeholders, angle-bracket code names, replacement strings, labels, and user-named targets.
        """,
        useSystemInstructions: true
    )

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

    static var supportsDedicatedInstructionEnhancement: Bool {
        true
    }

    static var appliesWordReplacements: Bool {
        false
    }

    static func shouldSkipEnhancement(
        text: String,
        isSkipShortEnhancementEnabled: Bool,
        wordThreshold: Int
    ) -> Bool {
        isSkipShortEnhancementEnabled &&
            WordCounter.count(in: text) <= wordThreshold
    }
}
