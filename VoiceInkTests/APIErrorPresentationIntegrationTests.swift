import XCTest
import LLMkit
@testable import VoiceInk

final class APIErrorPresentationIntegrationTests: XCTestCase {
    func testCloudTranscriptionErrorKeepsProviderDetailsSeparateFromSummary() {
        let body = #"{"error":{"code":"insufficient_quota","message":"Billing details from provider"}}"#
        let error = CloudTranscriptionError.apiRequestFailed(statusCode: 429, message: body)
        let presentation = APIErrorPresentation(error: error)
        XCTAssertEqual(presentation.title, "API quota exhausted")
        XCTAssertTrue(presentation.details.contains("Billing details from provider"))
        XCTAssertFalse(error.localizedDescription.contains("{\"error\""))
    }

    func testLLMKitHTTPErrorUsesTheSamePresentation() {
        let error = LLMKitError.httpError(statusCode: 429, message: #"{"error":{"code":"rate_limit_exceeded"}}"#)
        let presentation = APIErrorPresentation(error: error)
        XCTAssertEqual(presentation.title, "Too many API requests")
        XCTAssertTrue(presentation.details.contains("HTTP 429"))
    }
}
