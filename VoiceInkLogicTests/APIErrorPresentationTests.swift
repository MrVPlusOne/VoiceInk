import XCTest
@testable import VoiceInkLogic

final class APIErrorPresentationTests: XCTestCase {
    func testInsufficientQuotaIsNotPresentedAsTemporaryRateLimit() {
        let error = APIErrorPresentation(statusCode: 429, responseBody: #"{"error":{"message":"Check your plan and billing details.","type":"insufficient_quota","code":"insufficient_quota"}}"#)
        XCTAssertEqual(error.title, "API quota exhausted")
        XCTAssertTrue(error.guidance.contains("billing"))
        XCTAssertTrue(error.details.contains("HTTP 429"))
        XCTAssertTrue(error.details.contains("Check your plan and billing details."))
    }

    func testSpecificBillingCodeTakesPriorityOverQuotaType() {
        let cases = [
            "credit_balance_exhausted": "API credits exhausted",
            "project_spend_limit_exceeded": "Project spending limit reached",
            "organization_spend_limit_exceeded": "API spending limit reached",
            "organization_usage_limit_exceeded": "API usage limit reached"
        ]
        for (code, title) in cases {
            let error = APIErrorPresentation(statusCode: 429, responseBody: "{\"error\":{\"code\":\"\(code)\",\"type\":\"insufficient_quota\"}}")
            XCTAssertEqual(error.title, title)
        }
    }

    func testRateLimitIncludesFullProviderDelayMessage() {
        let error = APIErrorPresentation(statusCode: 429, responseBody: #"{"error":{"message":"Please try again in 20 seconds.","code":"rate_limit_exceeded"}}"#)
        XCTAssertEqual(error.title, "Too many API requests")
        XCTAssertTrue(error.copyableText.contains("Please try again in 20 seconds."))
        XCTAssertTrue(error.guidance.contains("Wait"))
    }

    func testUnknown429DoesNotGuessBillingOrTemporaryCause() {
        for (body, expectedDetail) in [
            ("", "No response body was provided."),
            ("<html>Too many requests</html>", "<html>Too many requests</html>"),
            (#"{"error":"Limit exceeded"}"#, "Limit exceeded")
        ] {
            let error = APIErrorPresentation(statusCode: 429, responseBody: body)
            XCTAssertEqual(error.title, "API limit reached")
            XCTAssertTrue(error.guidance.contains("rate limit or an account quota"))
            XCTAssertTrue(error.details.contains(expectedDetail))
        }
    }

    func testAuthenticationErrorRedactsEchoedCredentials() {
        let error = APIErrorPresentation(statusCode: 401, responseBody: #"{"error":{"message":"Invalid key sk-proj-123456789abcdef, Authorization: Bearer secretToken123"}}"#)
        XCTAssertEqual(error.title, "API authentication failed")
        XCTAssertFalse(error.copyableText.contains("sk-proj-"))
        XCTAssertFalse(error.copyableText.contains("secretToken123"))
        XCTAssertTrue(error.details.contains("[redacted API key]"))
    }

    func testLongResponseIsNotTruncated() {
        let body = String(repeating: "Detailed provider explanation. ", count: 200) + "END"
        let error = APIErrorPresentation(statusCode: 400, responseBody: body)
        XCTAssertEqual(error.title, "API request failed")
        XCTAssertTrue(error.details.hasSuffix(body))
        XCTAssertTrue(error.copyableText.hasSuffix("END"))
    }

    func testNonHTTPErrorRetainsMessage() {
        let error = APIErrorPresentation(message: "No microphone permission. Enable it in System Settings.")
        XCTAssertEqual(error.guidance, "No microphone permission. Enable it in System Settings.")
        XCTAssertTrue(error.copyableText.contains(error.guidance))
    }

    func testServiceAndAccessFailures() {
        XCTAssertEqual(APIErrorPresentation(statusCode: 503, responseBody: "Unavailable").title, "API service unavailable")
        XCTAssertEqual(APIErrorPresentation(statusCode: 403, responseBody: "Denied").title, "API access denied")
        XCTAssertEqual(APIErrorPresentation(statusCode: 404, responseBody: "Missing").title, "API model or endpoint unavailable")
    }
}
