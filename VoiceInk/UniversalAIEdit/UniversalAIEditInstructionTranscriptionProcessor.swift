import Foundation

enum UniversalAIEditInstructionTranscriptionProcessor {
    static let transcriptionPrompt = String(localized: "The speaker is telling a writing assistant how to write or change some text. Transcribe exactly what they say, in the language they speak.")

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
