import Foundation

enum UniversalAIEditInstructionTranscript {
    static func normalized(_ rawText: String) -> String {
        rawText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func appended(_ rawText: String, to existingInstruction: String) -> String {
        let transcript = normalized(rawText)
        guard !transcript.isEmpty else { return existingInstruction }
        guard !existingInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return transcript
        }
        return existingInstruction + " " + transcript
    }
}
