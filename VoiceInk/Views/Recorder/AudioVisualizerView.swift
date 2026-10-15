import SwiftUI

/// Live input level bars, newest on the right: the same meter as Wet Ink's recording pill. Each bar is one
/// 50 ms level from `VoiceLevelHistory`, so the bars scroll and their height follows how loud you are.
struct VoiceLevelBars: View {
    let levels: [Double]
    var color: Color = .white
    var barCount = 15
    var barWidth: CGFloat = 3
    var barSpacing: CGFloat = 2
    var minHeight: CGFloat = 4
    var maxHeight: CGFloat = 28

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(Array(visibleLevels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(color.opacity(0.9))
                    .frame(width: barWidth, height: minHeight + CGFloat(level) * (maxHeight - minHeight))
            }
        }
        .frame(height: maxHeight)
        .animation(.linear(duration: 0.05), value: levels)
    }

    private var visibleLevels: [Double] {
        let recent = levels.suffix(barCount)
        return Array(repeating: 0, count: barCount - recent.count) + recent
    }
}

// Flat bars shown when the recorder is idle (no audio input)
struct StaticVisualizer: View {
    private let barCount = 15
    private let barWidth: CGFloat = 3
    private let barHeight: CGFloat = 4
    private let barSpacing: CGFloat = 2
    let color: Color

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(color.opacity(0.5))
                    .frame(width: barWidth, height: barHeight)
            }
        }
    }
}

// MARK: - Processing Status Display

struct ProcessingStatusDisplay: View {
    enum Mode {
        case transcribing
        case enhancing
    }

    let mode: Mode
    let color: Color

    private var label: LocalizedStringKey {
        switch mode {
        case .transcribing: return "Transcribing"
        case .enhancing:    return "Enhancing"
        }
    }

    private var animationSpeed: Double {
        switch mode {
        case .transcribing: return 0.18
        case .enhancing:    return 0.22
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .foregroundColor(color)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            ProgressAnimation(color: color, animationSpeed: animationSpeed)
        }
        .frame(height: 28) // matches VoiceLevelBars maxHeight to prevent layout shift
    }
}
