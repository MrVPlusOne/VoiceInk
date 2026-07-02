import Testing
@testable import VoiceInk

struct RecorderAudioBehaviorTests {
    @Test func standardRecordingAllowsMuteAndMediaPause() {
        #expect(RecorderAudioBehavior.standardRecording.allowsSystemMute)
        #expect(RecorderAudioBehavior.standardRecording.allowsMediaPause)
    }

    @Test func aiEditInstructionBehaviorAllowsMuteWithoutMediaPause() {
        #expect(RecorderAudioBehavior.muteSystemOutputOnly.allowsSystemMute)
        #expect(!RecorderAudioBehavior.muteSystemOutputOnly.allowsMediaPause)
    }

    @Test func preserveSystemOutputBehaviorSkipsMuteAndMediaPause() {
        #expect(!RecorderAudioBehavior.preserveSystemOutput.allowsSystemMute)
        #expect(!RecorderAudioBehavior.preserveSystemOutput.allowsMediaPause)
    }

    @Test func systemMuteRegisteredDefaultIsOff() {
        #expect(AppDefaults.registeredDefaults["isSystemMuteEnabled"] as? Bool == false)
    }
}
