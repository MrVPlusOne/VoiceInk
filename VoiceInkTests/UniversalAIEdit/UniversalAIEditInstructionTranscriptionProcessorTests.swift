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

    @Test func instructionTranscriptionUsesDedicatedInstructionEnhancement() {
        #expect(UniversalAIEditInstructionTranscriptionProcessor.supportsDedicatedInstructionEnhancement)
        #expect(UniversalAIEditInstructionTranscriptionProcessor.enhancementPrompt.title == "AI Edit instruction cleanup")
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

    @Test func enhancementPromptPreservesLanguageAndInstructionOperands() {
        let prompt = UniversalAIEditInstructionTranscriptionProcessor.enhancementPrompt.promptText

        #expect(prompt.contains("Preserve the original spoken language"))
        #expect(prompt.contains("do not translate unless"))
        #expect(prompt.contains("rewrite ambiguous wording as an instruction"))
        #expect(prompt.contains("square-bracket TODO markers"))
        #expect(prompt.contains("angle-bracket code names"))
    }

    @Test func shortInstructionEnhancementFollowsNormalSkipSetting() {
        #expect(UniversalAIEditInstructionTranscriptionProcessor.shouldSkipEnhancement(
            text: "润色",
            isSkipShortEnhancementEnabled: true,
            wordThreshold: 3
        ))
        #expect(!UniversalAIEditInstructionTranscriptionProcessor.shouldSkipEnhancement(
            text: "润色",
            isSkipShortEnhancementEnabled: false,
            wordThreshold: 3
        ))
        #expect(!UniversalAIEditInstructionTranscriptionProcessor.shouldSkipEnhancement(
            text: "Please make this paragraph warmer and shorter.",
            isSkipShortEnhancementEnabled: true,
            wordThreshold: 3
        ))
    }
}
