import Foundation

enum RecorderAudioBehavior: Equatable {
    case standardRecording
    case muteSystemOutputOnly
    case preserveSystemOutput

    var allowsSystemMute: Bool {
        switch self {
        case .standardRecording, .muteSystemOutputOnly:
            return true
        case .preserveSystemOutput:
            return false
        }
    }

    var allowsMediaPause: Bool {
        self == .standardRecording
    }
}
