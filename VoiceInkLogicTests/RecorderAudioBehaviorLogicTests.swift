import XCTest
@testable import VoiceInkLogic

final class RecorderAudioBehaviorLogicTests: XCTestCase {
    func testStandardRecordingAllowsMuteAndMediaPause() {
        XCTAssertTrue(RecorderAudioBehavior.standardRecording.allowsSystemMute)
        XCTAssertTrue(RecorderAudioBehavior.standardRecording.allowsMediaPause)
    }

    func testAIEditInstructionBehaviorAllowsMuteWithoutMediaPause() {
        XCTAssertTrue(RecorderAudioBehavior.muteSystemOutputOnly.allowsSystemMute)
        XCTAssertFalse(RecorderAudioBehavior.muteSystemOutputOnly.allowsMediaPause)
    }

    func testPreserveSystemOutputBehaviorSkipsMuteAndMediaPause() {
        XCTAssertFalse(RecorderAudioBehavior.preserveSystemOutput.allowsSystemMute)
        XCTAssertFalse(RecorderAudioBehavior.preserveSystemOutput.allowsMediaPause)
    }
}
