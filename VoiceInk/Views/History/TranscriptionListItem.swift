import SwiftUI

struct TranscriptionListItem: View {
    let entry: HistoryEntry
    let isSelected: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggleCheck: (() -> Void)?

    private var transcription: Transcription? {
        entry.transcription
    }

    private var duration: TimeInterval? {
        guard let transcription, transcription.duration > 0 else { return nil }
        return transcription.duration
    }

    var body: some View {
        HStack(spacing: 8) {
            if let onToggleCheck {
                Toggle("", isOn: Binding(
                    get: { isChecked },
                    set: { _ in onToggleCheck() }
                ))
                .toggleStyle(CircularCheckboxStyle())
                .labelsHidden()
            } else {
                Image(systemName: entry.kindSystemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    if entry.aiEditRecord != nil {
                        Text(entry.kindLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(AppTheme.Surface.card)
                            )
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                    if let duration {
                        Text(duration.formatTiming())
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(AppTheme.Surface.card)
                            )
                            .foregroundColor(.secondary)
                    }
                }

                Text(entry.previewText)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(2)
                    .foregroundColor(.primary)
            }
        }
        .padding(10)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(AppTheme.Selection.fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .strokeBorder(AppTheme.Selection.border, lineWidth: 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(AppTheme.Surface.subtle)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .strokeBorder(AppTheme.Border.tint, lineWidth: 1)
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

struct CircularCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(configuration.isOn ? AppTheme.Selection.foreground : .secondary)
                .font(.system(size: 18))
        }
        .buttonStyle(.plain)
    }
}
