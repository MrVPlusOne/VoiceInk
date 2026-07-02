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
        screenText: "Application: Mail\nWindow Content:\nThread context",
        diagnostics: []
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

    @Test func generateModeHidesSelectionOnlyDiagnostics() {
        let diagnostics: [UniversalAIEditCaptureDiagnostic] = [
            .selectedTextUnavailable,
            .selectedTextCaptureFailed,
            .screenRecordingPermissionMissing,
            .screenTextUnavailable
        ]

        let visible = UniversalAIEditDiagnosticVisibility.visibleDiagnostics(
            diagnostics,
            mode: .insertNew
        )

        #expect(!visible.contains(.selectedTextUnavailable))
        #expect(!visible.contains(.selectedTextCaptureFailed))
        #expect(visible.contains(.screenRecordingPermissionMissing))
        #expect(visible.contains(.screenTextUnavailable))
    }

    @Test func editModeKeepsSelectionDiagnostics() {
        let diagnostics: [UniversalAIEditCaptureDiagnostic] = [
            .selectedTextUnavailable,
            .selectedTextCaptureFailed
        ]

        let visible = UniversalAIEditDiagnosticVisibility.visibleDiagnostics(
            diagnostics,
            mode: .replaceSelection
        )

        #expect(visible == diagnostics)
    }

    @Test func textDiffMarksInsertedAndRemovedText() {
        let segments = UniversalAIEditDiffBuilder.segments(
            original: "Please make this shorter.",
            revised: "Please make this much shorter."
        )

        #expect(segments.contains(.init(kind: .unchanged, text: "Please make this ")))
        #expect(segments.contains(.init(kind: .inserted, text: "much ")))
        #expect(segments.contains(.init(kind: .unchanged, text: "shorter.")))
        #expect(!segments.contains { $0.kind == .removed })
    }

    @Test func textDiffFallsBackForLargeInputs() {
        let original = Array(repeating: "alpha", count: 250).joined(separator: " ")
        let revised = Array(repeating: "beta", count: 250).joined(separator: " ")

        let segments = UniversalAIEditDiffBuilder.segments(
            original: original,
            revised: revised
        )

        #expect(segments == [
            .init(kind: .removed, text: original),
            .init(kind: .inserted, text: revised)
        ])
    }
}
