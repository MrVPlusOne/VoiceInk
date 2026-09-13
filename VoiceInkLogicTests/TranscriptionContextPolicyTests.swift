import XCTest
@testable import VoiceInkLogic

final class TranscriptionContextPolicyTests: XCTestCase {
    func testBuiltInOpenAIContextDefaultsOnButHonorsExplicitOptOut() {
        XCTAssertTrue(TranscriptionContextPolicy.isEnabled(supported: true, isBuiltInOpenAI: true, explicitPreference: nil))
        XCTAssertFalse(TranscriptionContextPolicy.isEnabled(supported: true, isBuiltInOpenAI: true, explicitPreference: false))
        XCTAssertTrue(TranscriptionContextPolicy.isEnabled(supported: true, isBuiltInOpenAI: true, explicitPreference: true))
    }

    func testCustomModelsStillRequireOptInAndCapability() {
        XCTAssertFalse(TranscriptionContextPolicy.isEnabled(supported: true, isBuiltInOpenAI: false, explicitPreference: nil))
        XCTAssertTrue(TranscriptionContextPolicy.isEnabled(supported: true, isBuiltInOpenAI: false, explicitPreference: true))
        XCTAssertFalse(TranscriptionContextPolicy.isEnabled(supported: false, isBuiltInOpenAI: true, explicitPreference: true))
    }

    func testSupportedModelsExcludeWhisperAndUnknownModels() {
        for model in ["gpt-transcribe", "gpt-4o-transcribe", " GPT-4O-MINI-TRANSCRIBE "] {
            XCTAssertTrue(TranscriptionContextPolicy.isKnownOpenAIModel(model))
        }
        for model in ["whisper-1", "gpt-4o-transcribe-diarize", "unknown"] {
            XCTAssertFalse(TranscriptionContextPolicy.isKnownOpenAIModel(model))
        }
    }

    @MainActor
    func testWaitDoesNotReturnBeforeOCRAndScreenshotAreReady() async {
        let readiness = RecordingContextReadiness()
        readiness.started()
        readiness.started()
        var captureCompleted = false
        let completion = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            readiness.finished()
            try? await Task.sleep(for: .milliseconds(30))
            readiness.finished()
            captureCompleted = true
        }
        let ready = await readiness.wait(timeout: .seconds(1))
        XCTAssertTrue(ready)
        XCTAssertTrue(captureCompleted)
        await completion.value
    }

    @MainActor
    func testWaitTimesOutWithoutWaitingForHungCapture() async {
        let readiness = RecordingContextReadiness()
        readiness.started()
        let clock = ContinuousClock()
        let start = clock.now
        let ready = await readiness.wait(timeout: .milliseconds(30))
        XCTAssertFalse(ready)
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(1))
    }

    @MainActor
    func testWaitStopsOnCancellationAndNoCaptureReturnsImmediately() async {
        let readiness = RecordingContextReadiness()
        let initiallyReady = await readiness.wait()
        XCTAssertTrue(initiallyReady)
        readiness.started()
        let wait = Task { await readiness.wait() }
        wait.cancel()
        let ready = await wait.value
        XCTAssertFalse(ready)
    }
}
