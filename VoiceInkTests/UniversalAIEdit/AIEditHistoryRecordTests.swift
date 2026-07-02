import Foundation
import Testing
@testable import VoiceInk

struct AIEditHistoryRecordTests {
    @Test func storesFullModelPromptPayloadForDebugging() {
        let target = UniversalAIEditTargetSnapshot(
            appName: "Mail",
            bundleIdentifier: "com.apple.mail",
            processIdentifier: 42,
            focusedWindowTitle: "Reply",
            focusedWindowFrame: nil
        )
        let record = AIEditHistoryRecord(
            instruction: "Make it clearer",
            mode: .replaceSelection,
            sourceText: "Original",
            generatedText: "Clearer result",
            providerName: "OpenAI",
            modelName: "gpt-5.5",
            generationDuration: 1.5,
            target: target,
            aiRequestSystemMessage: "System instructions",
            aiRequestUserMessage: "<SELECTED_TEXT>\nOriginal\n</SELECTED_TEXT>"
        )

        #expect(record.fullRequestText.contains("System Prompt:\nSystem instructions"))
        #expect(record.fullRequestText.contains("User Payload:\n<SELECTED_TEXT>\nOriginal\n</SELECTED_TEXT>"))
        #expect(record.sourceText == "Original")
        #expect(record.targetDisplayName == "Mail")
    }

    @Test func recordsOutcomeTransitions() {
        let record = AIEditHistoryRecord(
            instruction: "Draft a reply",
            mode: .insertNew,
            generatedText: "Reply text",
            providerName: "OpenAI",
            modelName: "gpt-5.5",
            generationDuration: 0.8,
            target: UniversalAIEditTargetSnapshot(
                appName: nil,
                bundleIdentifier: nil,
                processIdentifier: nil,
                focusedWindowTitle: nil,
                focusedWindowFrame: nil
            )
        )

        #expect(record.outcome == .generated)

        record.recordOutcome(.copied, note: "Paste unavailable")

        #expect(record.outcome == .copied)
        #expect(record.outcomeNote == "Paste unavailable")
    }
}
