import Testing
@testable import VoiceInk

struct RecorderAudioBehaviorTests {
    @Test func defaultRecordingBehaviorInterruptsSystemOutput() {
        #expect(RecorderAudioBehavior.interruptSystemOutput.interruptsSystemOutput)
    }

    @Test func aiEditInstructionBehaviorPreservesSystemOutput() {
        #expect(!RecorderAudioBehavior.preserveSystemOutput.interruptsSystemOutput)
    }
}
