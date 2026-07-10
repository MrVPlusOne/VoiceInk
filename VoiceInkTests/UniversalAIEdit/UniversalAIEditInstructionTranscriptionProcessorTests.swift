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

    @Test func instructionTranscriptionDoesNotUseModeAIEnhancement() {
        #expect(!UniversalAIEditInstructionTranscriptionProcessor.usesAIEnhancement)
    }

    @Test func instructionTranscriptionDoesNotApplyWordReplacements() {
        #expect(!UniversalAIEditInstructionTranscriptionProcessor.appliesWordReplacements)
    }
}
