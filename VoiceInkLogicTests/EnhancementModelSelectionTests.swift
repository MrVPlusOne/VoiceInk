import XCTest
@testable import VoiceInkLogic

final class EnhancementModelSelectionTests: XCTestCase {
    func testCustomModelSurvivesPresetRefresh() {
        let selected = "vendor/New-Model:preview"

        for presets in [[], ["older-model"], ["another-model", "older-model"]] {
            XCTAssertEqual(
                EnhancementModelSelection.resolve(
                    selected, availableModels: presets, fallback: "older-model", allowsCustom: true
                ),
                selected
            )
        }
    }

    func testPresetSelectionIsPreserved() {
        XCTAssertEqual(
            EnhancementModelSelection.resolve(
                "second-model", availableModels: ["first-model", "second-model"],
                fallback: "first-model", allowsCustom: true
            ),
            "second-model"
        )
    }

    func testConfiguredEndpointStillRequiresKnownModel() {
        XCTAssertEqual(
            EnhancementModelSelection.resolve(
                "unconfigured-model", availableModels: ["configured-endpoint-model"],
                fallback: "configured-endpoint-model", allowsCustom: false
            ),
            "configured-endpoint-model"
        )
    }

    func testMissingOrBlankSelectionUsesFallback() {
        for selected: String? in [nil, "", " \n\t"] {
            XCTAssertEqual(
                EnhancementModelSelection.resolve(
                    selected, availableModels: ["first-model"], fallback: "default-model", allowsCustom: true
                ),
                "default-model"
            )
        }
    }

    func testExistingSelectionSurvivesUnloadedModelList() {
        XCTAssertEqual(
            EnhancementModelSelection.resolve(
                "saved-model", availableModels: [], fallback: "default-model", allowsCustom: false
            ),
            "saved-model"
        )
    }
}
