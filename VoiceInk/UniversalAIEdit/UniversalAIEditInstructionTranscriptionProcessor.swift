import Foundation

enum UniversalAIEditInstructionTranscriptionProcessor {
    static let transcriptionPrompt = String(localized: "Transcribe the speech in the original spoken language as a concise AI Edit instruction. Do not translate unless the speaker explicitly asks for translation. Preserve command intent, requested tone, length, audience, formatting changes, and literal operands.")

    /// AI Edit instructions are commands, not final prose. Keep post-STT cleanup minimal
    /// so literal command targets like "[TODO]", "(beta)", or "<code>" survive.
    static func process(_ rawText: String) -> String {
        localCleanup(rawText)
    }

    static func instructionByAppendingTranscript(
        _ rawText: String,
        to existingInstruction: String
    ) -> String {
        UniversalAIEditInstructionTranscript.appended(rawText, to: existingInstruction)
    }

    static func localCleanup(_ rawText: String) -> String {
        UniversalAIEditInstructionTranscript.normalized(rawText)
    }

    static var appliesWordReplacements: Bool {
        false
    }
}
