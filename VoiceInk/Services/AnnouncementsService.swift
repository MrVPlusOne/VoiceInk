import Foundation

/// Announcements are intentionally disabled so the app does not poll VoiceInk-owned
/// endpoints in the background.
final class AnnouncementsService {
    static let shared = AnnouncementsService()

    private init() {}

    func start() {}
    func stop() {}
}

