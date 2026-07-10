import Foundation
import Testing
@testable import VoiceInk

struct UniversalAIEditPromptTemplateTests {
    @Test func promptTemplateStoreRoundTripsAndFiltersInvalidEntries() throws {
        let suiteName = "UniversalAIEditPromptTemplateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let valid = UniversalAIEditPromptTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
            label: " Polish ",
            content: "  Keep exact content.  ",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let blankLabel = UniversalAIEditPromptTemplate(label: " ", content: "Content")
        let blankContent = UniversalAIEditPromptTemplate(label: "Label", content: " \n")

        UniversalAIEditPromptTemplateStore.save([valid, blankLabel, blankContent], defaults: defaults)

        let loaded = UniversalAIEditPromptTemplateStore.load(defaults: defaults)
        #expect(loaded == [
            UniversalAIEditPromptTemplate(
                id: valid.id,
                label: "Polish",
                content: "  Keep exact content.  ",
                createdAt: valid.createdAt,
                updatedAt: valid.updatedAt
            )
        ])
    }

    @Test func registeredDefaultsIncludeEmptyPromptTemplateStore() {
        #expect(AppDefaults.registeredDefaults[UniversalAIEditPromptTemplateStore.userDefaultsKey] as? Data == Data())
    }

    @Test func insertionUsesCaretWithoutReplacingWholeInstruction() {
        let result = UniversalAIEditPromptTemplateInsertion.insert(
            "polish ",
            into: "Please this",
            selectedRange: NSRange(location: 7, length: 0)
        )

        #expect(result.text == "Please polish this")
        #expect(result.caretLocation == 14)
    }

    @Test func insertionReplacesOnlyCurrentEditorSelection() {
        let result = UniversalAIEditPromptTemplateInsertion.insert(
            "make concise",
            into: "Please make formal and friendly",
            selectedRange: NSRange(location: 7, length: 11)
        )

        #expect(result.text == "Please make concise and friendly")
        #expect(result.caretLocation == 19)
    }

    @Test func insertionCanReplaceWholeInstructionWhenSelectionCoversAll() {
        let original = "Please make formal"
        let result = UniversalAIEditPromptTemplateInsertion.insert(
            "Polish this for clarity.",
            into: original,
            selectedRange: NSRange(location: 0, length: (original as NSString).length)
        )

        #expect(result.text == "Polish this for clarity.")
        #expect(result.caretLocation == ("Polish this for clarity." as NSString).length)
    }

    @Test func insertionFallsBackToEndForMissingSelection() {
        let result = UniversalAIEditPromptTemplateInsertion.insert(
            " now",
            into: "Polish",
            selectedRange: nil
        )

        #expect(result.text == "Polish now")
        #expect(result.caretLocation == ("Polish now" as NSString).length)
    }

    @Test func commandNumberShortcutMapsVisibleButtonOrder() {
        #expect(UniversalAIEditPromptTemplateShortcut.number(forButtonIndex: 0) == 1)
        #expect(UniversalAIEditPromptTemplateShortcut.number(forButtonIndex: 8) == 9)
        #expect(UniversalAIEditPromptTemplateShortcut.number(forButtonIndex: 9) == 10)
        #expect(UniversalAIEditPromptTemplateShortcut.number(forButtonIndex: 10) == nil)

        #expect(UniversalAIEditPromptTemplateShortcut.number(forKeyCode: 18) == 1)
        #expect(UniversalAIEditPromptTemplateShortcut.number(forKeyCode: 25) == 9)
        #expect(UniversalAIEditPromptTemplateShortcut.number(forKeyCode: 29) == 10)
        #expect(UniversalAIEditPromptTemplateShortcut.number(forKeyCode: 0) == nil)
    }
}
