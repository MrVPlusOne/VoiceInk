import Testing
@testable import VoiceInk

struct RecorderAudioBehaviorTests {
    @Test func systemMuteRegisteredDefaultIsOff() {
        #expect(AppDefaults.registeredDefaults["isSystemMuteEnabled"] as? Bool == false)
    }
}
