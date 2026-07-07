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

    @Test func exposesSentScreenContextFromStoredPayload() {
        let target = UniversalAIEditTargetSnapshot(
            appName: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 42,
            focusedWindowTitle: "Takode",
            focusedWindowFrame: nil
        )
        let record = AIEditHistoryRecord(
            instruction: "Summarize this",
            mode: .insertNew,
            generatedText: "Summary",
            providerName: "OpenAI",
            modelName: "gpt-5.5",
            generationDuration: 1.2,
            target: target,
            aiRequestUserMessage: """
            <CURRENT_WINDOW_CONTEXT>
            A Chrome tab is open.
            The page includes a quest detail.
            </CURRENT_WINDOW_CONTEXT>

            <CUSTOM_VOCABULARY>
            VoiceInk
            </CUSTOM_VOCABULARY>
            """
        )

        #expect(record.sentScreenContext == "A Chrome tab is open.\nThe page includes a quest detail.")
    }

    @Test func ignoresMissingScreenContextPayloadBlock() {
        let target = UniversalAIEditTargetSnapshot(
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            processIdentifier: 42,
            focusedWindowTitle: nil,
            focusedWindowFrame: nil
        )
        let record = AIEditHistoryRecord(
            instruction: "Rewrite",
            mode: .replaceSelection,
            generatedText: "Rewritten",
            providerName: "OpenAI",
            modelName: "gpt-5.5",
            generationDuration: 0.8,
            target: target,
            aiRequestUserMessage: "<USER_INSTRUCTION>\nRewrite\n</USER_INSTRUCTION>"
        )

        #expect(record.sentScreenContext == nil)
    }

    @Test func exposesScreenshotContextMetadataForInspection() {
        let target = UniversalAIEditTargetSnapshot(
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            processIdentifier: 42,
            focusedWindowTitle: "Project",
            focusedWindowFrame: nil
        )
        let record = AIEditHistoryRecord(
            instruction: "Keep formatting",
            mode: .replaceSelection,
            generatedText: "Formatted result",
            providerName: "OpenAI",
            modelName: "gpt-5.5",
            generationDuration: 1.0,
            target: target,
            aiRequestUserMessage: """
            <ATTACHED_SCREENSHOT_CONTEXT>
            Attached screenshot retained in local AI Edit history/debug storage.
            Media Type: image/jpeg
            Dimensions: 1200x800
            </ATTACHED_SCREENSHOT_CONTEXT>
            """
        )

        #expect(record.sentScreenContext == nil)
        #expect(record.sentScreenshotContextMetadata?.contains("Attached screenshot retained") == true)
        #expect(record.sentScreenContextForInspection?.contains("Dimensions: 1200x800") == true)
    }

    @Test func retainsCompressedScreenshotContextForLocalHistoryInspection() {
        let target = UniversalAIEditTargetSnapshot(
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            processIdentifier: 42,
            focusedWindowTitle: "Project",
            focusedWindowFrame: nil
        )
        let screenshot = UniversalAIEditScreenshotContext(
            data: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            mediaType: "image/jpeg",
            width: 1200,
            height: 800,
            byteCount: 4,
            sourceWidth: 2400,
            sourceHeight: 1600,
            detail: "high",
            applicationName: "Slack",
            windowTitle: "Project"
        )
        let record = AIEditHistoryRecord(
            instruction: "Keep formatting",
            mode: .replaceSelection,
            generatedText: "Formatted result",
            providerName: "OpenAI",
            modelName: "gpt-5.5",
            generationDuration: 1.0,
            target: target,
            screenshotContext: screenshot
        )

        #expect(record.hasRetainedScreenshotContext)
        #expect(record.hasInspectableScreenContext)
        #expect(record.screenshotContextData == screenshot.data)
        #expect(record.screenshotContextMediaType == "image/jpeg")
        #expect(record.screenshotContextWidth == 1200)
        #expect(record.screenshotContextHeight == 800)
        #expect(record.screenshotContextByteCount == 4)
        #expect(record.retainedScreenshotContextMetadata?.contains("Compressed Bytes: 4") == true)
        #expect(record.retainedScreenshotContextMetadata?.contains("Application: Slack") == true)
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
