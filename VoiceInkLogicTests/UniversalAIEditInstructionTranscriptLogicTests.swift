import XCTest
@testable import VoiceInkLogic

final class UniversalAIEditInstructionTranscriptLogicTests: XCTestCase {
    func testDirectTranscriptFillsEmptyInstructionAfterWhitespaceNormalization() {
        XCTAssertEqual(
            UniversalAIEditInstructionTranscript.appended(
                "  Make   this shorter.\n ",
                to: ""
            ),
            "Make this shorter."
        )
    }

    func testDirectTranscriptAppendsWithoutRewritingLiteralOperands() {
        XCTAssertEqual(
            UniversalAIEditInstructionTranscript.appended(
                "and keep [TODO], (beta), {draft}, and <code> literal",
                to: "Make this shorter."
            ),
            "Make this shorter. and keep [TODO], (beta), {draft}, and <code> literal"
        )
    }

    func testEmptyTranscriptDoesNotChangeExistingInstruction() {
        XCTAssertEqual(
            UniversalAIEditInstructionTranscript.appended("  \n ", to: "Keep this instruction"),
            "Keep this instruction"
        )
    }
}
