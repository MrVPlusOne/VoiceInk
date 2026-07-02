import Foundation
import Testing
@testable import VoiceInk

struct UniversalAIEditPromptBuilderTests {
    @Test func replaceSelectionPromptUsesDedicatedTargetAndInstructionBlocks() {
        let context = UniversalAIEditContext(
            capturedAt: Date(timeIntervalSince1970: 0),
            target: UniversalAIEditTargetSnapshot(
                appName: "Mail",
                bundleIdentifier: "com.apple.mail",
                processIdentifier: 42,
                focusedWindowTitle: "Reply",
                focusedWindowFrame: nil
            ),
            selectedText: "Original draft",
            clipboardText: nil,
            screenText: "Application: Mail\nWindow Content:\nThread context"
        )

        let payload = UniversalAIEditPromptBuilder.userPayload(
            instruction: "Make it shorter",
            mode: .replaceSelection,
            context: context,
            customVocabulary: "VoiceInk"
        )

        #expect(payload.contains("<EDIT_MODE>\nreplace_selection\n</EDIT_MODE>"))
        #expect(payload.contains("<USER_INSTRUCTION>\nMake it shorter\n</USER_INSTRUCTION>"))
        #expect(payload.contains("<SELECTED_TEXT>\nOriginal draft\n</SELECTED_TEXT>"))
        #expect(payload.contains("<CURRENT_WINDOW_CONTEXT>"))
        #expect(payload.contains("<CUSTOM_VOCABULARY>\nVoiceInk\n</CUSTOM_VOCABULARY>"))
        #expect(!payload.contains("<CLIPBOARD_CONTEXT>"))
    }

    @Test func systemPromptTreatsContextAsUntrustedSourceMaterial() {
        let prompt = UniversalAIEditPromptBuilder.systemPrompt(mode: .insertNew)

        #expect(prompt.contains("insert_new"))
        #expect(prompt.contains("untrusted source material"))
        #expect(prompt.contains("Return only the final text to paste"))
    }
}
