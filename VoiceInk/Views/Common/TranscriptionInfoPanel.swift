import AppKit
import SwiftUI

/// Reusable component that displays transcription Details and AI Request sections.
/// Used in both the inline history side panel and the separate history window's metadata view.
struct TranscriptionInfoPanel: View {
    let transcription: Transcription

    var body: some View {
        Form {
            detailsSection
            screenshotContextSection
            aiRequestSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        Section {
            metadataRow(
                icon: "calendar",
                label: "Date",
                value: transcription.timestamp.formatted(date: .abbreviated, time: .shortened)
            )

            metadataRow(
                icon: "hourglass",
                label: "Duration",
                value: transcription.duration.formatTiming()
            )

            if let modelName = transcription.transcriptionModelName {
                metadataRow(
                    icon: "cpu.fill",
                    label: "Transcription Model",
                    value: modelName
                )

                if let duration = transcription.transcriptionDuration {
                    metadataRow(
                        icon: "clock.fill",
                        label: "Transcription Time",
                        value: duration.formatTiming()
                    )
                }
            }

            if let aiModel = transcription.aiEnhancementModelName {
                metadataRow(
                    icon: "sparkles",
                    label: "Enhancement Model",
                    value: aiModel
                )

                if let duration = transcription.enhancementDuration {
                    metadataRow(
                        icon: "clock.fill",
                        label: "Enhancement Time",
                        value: duration.formatTiming()
                    )
                }
            }

            if let promptName = transcription.promptName {
                metadataRow(
                    icon: "text.bubble.fill",
                    label: "Prompt",
                    value: promptName
                )
            }

            if let modeName = transcription.modeName {
                metadataRow(
                    icon: "bolt.fill",
                    label: "Mode",
                    value: modeName
                )
            }
        } header: {
            Text("Details")
        }
    }

    // MARK: - Screenshot Context Section

    @ViewBuilder
    private var screenshotContextSection: some View {
        if transcription.hasRetainedScreenshotContext {
            Section {
                Button {
                    openRetainedScreenshot()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Screenshot")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("Opens with the default image viewer")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open retained screenshot with the default image viewer")

                if let metadata = transcription.retainedScreenshotContextMetadata {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Screenshot Metadata")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(metadata)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .foregroundColor(.primary)
                    }
                }
            } header: {
                Text("Screenshot Context")
            }
        }
    }

    // MARK: - AI Request Section

    @ViewBuilder
    private var aiRequestSection: some View {
        if transcription.aiRequestSystemMessage != nil || transcription.aiRequestUserMessage != nil {
            Section {
                if let systemMsg = transcription.aiRequestSystemMessage, !systemMsg.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("System Prompt")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(systemMsg)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .foregroundColor(.primary)
                    }
                }

                if let userMsg = transcription.aiRequestUserMessage, !userMsg.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("User Message")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(userMsg)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .foregroundColor(.primary)
                    }
                }
            } header: {
                Text("AI Request")
            }
            .hoverCopyButton(
                textToCopy: fullRequestText,
                alignment: .topTrailing,
                padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            )
        }
    }

    // MARK: - Helpers

    private var fullRequestText: String {
        var parts: [String] = []
        if let sys = transcription.aiRequestSystemMessage, !sys.isEmpty {
            parts.append("System Prompt:\n\(sys)")
        }
        if let user = transcription.aiRequestUserMessage, !user.isEmpty {
            parts.append("User Message:\n\(user)")
        }
        return parts.joined(separator: "\n\n")
    }

    @MainActor
    private func openRetainedScreenshot() {
        guard let data = transcription.screenshotContextData, !data.isEmpty else {
            NotificationManager.shared.showNotification(
                title: String(localized: "Screenshot context is unavailable."),
                type: .error
            )
            return
        }

        do {
            let url = try writeScreenshotToTemporaryFile(data: data)
            guard NSWorkspace.shared.open(url) else {
                NotificationManager.shared.showNotification(
                    title: String(localized: "Could not open screenshot context."),
                    type: .error
                )
                return
            }
        } catch {
            NotificationManager.shared.showNotification(
                title: String(localized: "Could not prepare screenshot context."),
                type: .error
            )
        }
    }

    private func writeScreenshotToTemporaryFile(data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkScreenshotContext", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let url = directory.appendingPathComponent(
            "transcription-\(transcription.id.uuidString).\(screenshotFileExtension)"
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    private var screenshotFileExtension: String {
        switch transcription.screenshotContextMediaType?.lowercased() {
        case "image/png":
            return "png"
        case "image/heic":
            return "heic"
        case "image/tiff":
            return "tiff"
        default:
            return "jpg"
        }
    }

    private func metadataRow(icon: String, label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }

}
