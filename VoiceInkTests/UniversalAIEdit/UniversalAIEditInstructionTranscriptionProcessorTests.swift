import Testing
@testable import VoiceInk

struct UniversalAIEditInstructionTranscriptionProcessorTests {
    @Test func localCleanupNormalizesWhitespaceWithoutRewritingCommand() {
        let cleaned = UniversalAIEditInstructionTranscriptionProcessor.localCleanup(
            "  Make   the reply\nconcise.  "
        )

        #expect(cleaned == "Make the reply concise.")
    }

    @Test func localCleanupPreservesStructuredInstructionTargets() {
        let cleaned = UniversalAIEditInstructionTranscriptionProcessor.localCleanup(
            " replace [TODO] with done, remove (beta) from the title, keep {draft}, and change <code> tags to backticks "
        )

        #expect(cleaned == "replace [TODO] with done, remove (beta) from the title, keep {draft}, and change <code> tags to backticks")
    }

    @Test func directTranscriptFillsEmptyInstructionFieldWithoutPromptEnhancement() {
        let instruction = UniversalAIEditInstructionTranscriptionProcessor.instructionByAppendingTranscript(
            "  Make   this shorter.  ",
            to: ""
        )

        #expect(instruction == "Make this shorter.")
    }

    @Test func directTranscriptAppendsToExistingInstructionField() {
        let instruction = UniversalAIEditInstructionTranscriptionProcessor.instructionByAppendingTranscript(
            "and keep [TODO] literal",
            to: "Make this shorter."
        )

        #expect(instruction == "Make this shorter. and keep [TODO] literal")
    }

    @Test func emptyTranscriptDoesNotChangeExistingInstructionField() {
        let instruction = UniversalAIEditInstructionTranscriptionProcessor.instructionByAppendingTranscript(
            "  \n ",
            to: "Keep this instruction"
        )

        #expect(instruction == "Keep this instruction")
    }

    @Test func instructionTranscriptionDoesNotApplyWordReplacements() {
        #expect(!UniversalAIEditInstructionTranscriptionProcessor.appliesWordReplacements)
    }

    @Test func transcriptionPromptPreservesSpokenLanguage() {
        let prompt = UniversalAIEditInstructionTranscriptionProcessor.transcriptionPrompt

        #expect(prompt.contains("original spoken language"))
        #expect(prompt.contains("Do not translate unless"))
        #expect(prompt.contains("literal operands"))
    }
}
