import Foundation
import XCTest
@testable import VoiceInkLogic

final class GPTTranscribeRequestTests: XCTestCase {
    func testRequestUsesNewModelAndArrayLanguageHints() throws {
        let audio = Data([0, 1, 2, 255])
        let request = GPTTranscribeRequest.make(
            audioData: audio, apiKey: "test-key", language: "zh",
            prompt: "Technical discussion", keywords: ["VoiceInk", "OpenAI"], boundary: "test-boundary"
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=test-boundary")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertNotNil(body.range(of: audio))
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"model\"\r\n\r\ngpt-transcribe\r\n"))
        XCTAssertTrue(text.contains("name=\"languages[]\"\r\n\r\nzh\r\n"))
        XCTAssertFalse(text.contains("name=\"language\""))
        XCTAssertTrue(text.contains("name=\"prompt\"\r\n\r\nTechnical discussion\r\n"))
        XCTAssertTrue(text.contains("name=\"keywords[]\"\r\n\r\nVoiceInk\r\n"))
        XCTAssertTrue(text.contains("name=\"keywords[]\"\r\n\r\nOpenAI\r\n"))
        XCTAssertTrue(text.hasSuffix("--test-boundary--\r\n"))
    }

    func testAutoDetectionOmitsLanguageAndEmptyHints() throws {
        for language in [nil, "", "auto"] as [String?] {
            let request = GPTTranscribeRequest.make(
                audioData: Data(), apiKey: "test-key", language: language,
                prompt: "", keywords: ["", "  "]
            )
            let text = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
            XCTAssertFalse(text.contains("name=\"languages[]\""))
            XCTAssertFalse(text.contains("name=\"prompt\""))
            XCTAssertFalse(text.contains("name=\"keywords[]\""))
        }
    }
}
