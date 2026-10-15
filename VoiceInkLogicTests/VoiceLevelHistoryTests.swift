import XCTest
@testable import VoiceInkLogic

final class VoiceLevelHistoryTests: XCTestCase {
    func testDecibelsMapLinearlyFromMinus50ToZero() {
        XCTAssertEqual(VoiceLevelHistory.level(forDecibels: -160), 0)
        XCTAssertEqual(VoiceLevelHistory.level(forDecibels: -50), 0)
        XCTAssertEqual(VoiceLevelHistory.level(forDecibels: -25), 0.5, accuracy: 0.0001)
        XCTAssertEqual(VoiceLevelHistory.level(forDecibels: 0), 1)
        XCTAssertEqual(VoiceLevelHistory.level(forDecibels: 6), 1)
    }

    func testEveryThreeReadingsAddTheirAverageAsNewestLevel() {
        var history = VoiceLevelHistory()
        XCTAssertFalse(history.addReading(decibels: -50))
        XCTAssertFalse(history.addReading(decibels: -25))
        XCTAssertTrue(history.addReading(decibels: 0))
        XCTAssertEqual(history.levels.count, VoiceLevelHistory.count)
        XCTAssertEqual(history.levels.last ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(history.levels.first, 0)
    }

    func testResetClearsLevelsAndPendingReadings() {
        var history = VoiceLevelHistory()
        _ = history.addReading(decibels: 0)
        _ = history.addReading(decibels: 0)
        history.reset()
        XCTAssertFalse(history.addReading(decibels: 0))
        XCTAssertEqual(history.levels, Array(repeating: 0, count: VoiceLevelHistory.count))
    }
}
