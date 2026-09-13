import XCTest
@testable import VoiceInkLogic

final class TranscriptionRequestDiagnosticsTests: XCTestCase {
    private func request(transport: String = "File", prompt: String? = nil, context: String? = nil) -> TranscriptionRequestDiagnostics {
        TranscriptionRequestDiagnostics(
            model: "speech-model", provider: "Custom", transport: transport,
            language: "en", prompt: prompt, recognitionContext: context, notes: "Recorded inputs"
        )
    }

    func testFullPromptAndContextSurvivePersistenceWithoutTruncation() throws {
        let context = "<CURRENT_WINDOW_CONTEXT>\n" + String(repeating: "einsum ", count: 2000) + "\n</CURRENT_WINDOW_CONTEXT>"
        let original = request(prompt: "Transcribe accurately\n\n" + context, context: context)
        let recorder = TranscriptionDiagnosticsRecorder()
        recorder.record(original)
        let json = try XCTUnwrap(recorder.encodedRequests)
        let decoded = try JSONDecoder().decode([TranscriptionRequestDiagnostics].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, [original])
        XCTAssertTrue(decoded[0].inspectionText.contains(context))
    }

    func testStreamingAndFallbackKeepSeparateInputsInOrder() {
        let recorder = TranscriptionDiagnosticsRecorder()
        recorder.record(request(transport: "Streaming"))
        recorder.record(request(prompt: "File fallback prompt"))
        XCTAssertEqual(recorder.requests.map(\.transport), ["Streaming", "File"])
        XCTAssertNil(recorder.requests[0].prompt)
        XCTAssertEqual(recorder.requests[1].prompt, "File fallback prompt")
    }

    func testRecordingsDoNotShareDiagnostics() {
        let first = TranscriptionDiagnosticsRecorder()
        let second = TranscriptionDiagnosticsRecorder()
        first.record(request(prompt: "First recording only"))
        XCTAssertTrue(second.requests.isEmpty)
        XCTAssertEqual(second.encodedRequests, "[]")
    }

    func testAbsentPromptIsExplicitRatherThanInventingSystemInstructions() {
        let text = request().inspectionText
        XCTAssertTrue(text.contains("No separate system message supplied by VoiceInk"))
        XCTAssertTrue(text.contains("No transcription prompt supplied"))
        XCTAssertTrue(text.contains("No screen, selection, or clipboard text supplied"))
    }

    func testConcurrentReportingDoesNotLoseAttempts() {
        let recorder = TranscriptionDiagnosticsRecorder()
        let sample = request()
        DispatchQueue.concurrentPerform(iterations: 100) { _ in recorder.record(sample) }
        XCTAssertEqual(recorder.requests.count, 100)
    }
}
