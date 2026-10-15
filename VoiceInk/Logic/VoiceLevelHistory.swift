import Foundation

/// Recent microphone input levels for the recording indicators, newest last. Each level is the input's RMS
/// power mapped linearly from -50 dBFS (silence) to 0 dBFS (loud), and one is added every 50 ms, so the bars
/// scroll and show how loud you actually are.
struct VoiceLevelHistory: Equatable {
    static let count = 34
    /// Meter readings averaged into one level, at the recorder's ~17 ms meter rate: about 50 ms per level.
    static let readingsPerLevel = 3

    private(set) var levels: [Double] = Array(repeating: 0, count: VoiceLevelHistory.count)
    private var pending: [Double] = []

    static func level(forDecibels decibels: Float) -> Double {
        Double(max(0, min(1, (decibels + 50) / 50)))
    }

    /// Adds one meter reading. Returns true when that completed a new level.
    mutating func addReading(decibels: Float) -> Bool {
        pending.append(Self.level(forDecibels: decibels))
        guard pending.count >= Self.readingsPerLevel else { return false }
        levels.removeFirst()
        levels.append(pending.reduce(0, +) / Double(pending.count))
        pending.removeAll(keepingCapacity: true)
        return true
    }

    mutating func reset() {
        self = VoiceLevelHistory()
    }
}
