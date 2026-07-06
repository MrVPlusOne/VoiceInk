import SwiftUI

struct AIEditHistoryDetailView: View {
    let record: AIEditHistoryRecord
    var onInfoTap: (() -> Void)?

    @State private var isScreenContextInspectorPresented = false

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    metadataSummary

                    AIEditHistoryTextBlock(
                        label: "Instruction",
                        text: record.instruction,
                        systemImage: "text.bubble"
                    )

                    if let sourceText = record.sourceText, !sourceText.isEmpty {
                        AIEditHistoryTextBlock(
                            label: "Source",
                            text: sourceText,
                            systemImage: "text.quote"
                        )
                    }

                    AIEditHistoryTextBlock(
                        label: "Result",
                        text: record.generatedText,
                        systemImage: "sparkles"
                    )

                    if !record.fullRequestText.isEmpty {
                        requestSection
                    }
                }
                .padding(16)
            }
        }
        .padding(.vertical, 12)
        .sheet(isPresented: $isScreenContextInspectorPresented) {
            if let screenContext = record.sentScreenContextForInspection {
                AIEditScreenContextInspectorView(
                    contextText: screenContext,
                    subtitle: "Sent with this AI Edit request"
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .fill(AppTheme.Surface.materialCard)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Edit")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(record.mode.displayName) - \(record.outcome.displayName) - \(record.timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if record.sentScreenContextForInspection != nil {
                screenContextButton
            }

            if let onInfoTap {
                Button(action: onInfoTap) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("View details")
            }
        }
    }

    private var metadataSummary: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 8, alignment: .leading)
            ],
            alignment: .leading,
            spacing: 8
        ) {
            summaryChip(
                icon: "calendar",
                label: "Date",
                value: record.timestamp.formatted(date: .abbreviated, time: .shortened)
            )
            summaryChip(icon: "sparkles", label: "Provider", value: record.providerName)
            summaryChip(icon: "cpu.fill", label: "Model", value: record.modelName)
            summaryChip(icon: "macwindow", label: "Target", value: record.targetDisplayName)
        }
    }

    private func summaryChip(icon: String, label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.Text.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AppTheme.Text.muted)
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.Text.primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .fill(AppTheme.Surface.subtle)
        )
    }

    private var requestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Model Prompt / Payload", systemImage: "curlybraces")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)

                Spacer()

                if record.sentScreenContextForInspection != nil {
                    screenContextButton
                }
            }

            if let systemMessage = record.aiRequestSystemMessage, !systemMessage.isEmpty {
                AIEditHistoryTextBlock(
                    label: "System Prompt",
                    text: systemMessage,
                    systemImage: "terminal",
                    isMonospaced: true
                )
            }

            if let userMessage = record.aiRequestUserMessage, !userMessage.isEmpty {
                AIEditHistoryTextBlock(
                    label: "User Payload",
                    text: userMessage,
                    systemImage: "text.badge.checkmark",
                    isMonospaced: true
                )
            }
        }
    }

    private var screenContextButton: some View {
        Button {
            isScreenContextInspectorPresented = true
        } label: {
            Label("Screen context", systemImage: "rectangle.on.rectangle")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.Text.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(AppTheme.Selection.fill)
                )
        }
        .buttonStyle(.plain)
        .help("View sent screen context")
    }
}

struct AIEditHistoryInfoPanel: View {
    let record: AIEditHistoryRecord

    var body: some View {
        Form {
            detailsSection
            targetSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailsSection: some View {
        Section {
            metadataRow(
                icon: "calendar",
                label: "Date",
                value: record.timestamp.formatted(date: .abbreviated, time: .shortened)
            )
            metadataRow(
                icon: "wand.and.sparkles",
                label: "Mode",
                value: record.mode.displayName
            )
            metadataRow(
                icon: record.outcome.systemImage,
                label: "Outcome",
                value: record.outcome.displayName
            )
            if let outcomeNote = record.outcomeNote {
                metadataRow(
                    icon: "info.circle",
                    label: "Outcome Note",
                    value: outcomeNote
                )
            }
            metadataRow(
                icon: "sparkles",
                label: "Provider",
                value: record.providerName
            )
            metadataRow(
                icon: "cpu.fill",
                label: "Model",
                value: record.modelName
            )
            metadataRow(
                icon: "clock.fill",
                label: "Generation Time",
                value: record.generationDuration.formatTiming()
            )
        } header: {
            Text("AI Edit")
        }
    }

    @ViewBuilder
    private var targetSection: some View {
        Section {
            metadataRow(
                icon: "macwindow",
                label: "Target App",
                value: record.targetDisplayName
            )
            if let bundleIdentifier = record.targetBundleIdentifier {
                metadataRow(
                    icon: "shippingbox",
                    label: "Bundle",
                    value: bundleIdentifier
                )
            }
            if let title = record.targetWindowTitle {
                metadataRow(
                    icon: "rectangle.on.rectangle",
                    label: "Window",
                    value: title
                )
            }
            if let frame = record.targetWindowFrameDescription {
                metadataRow(
                    icon: "viewfinder",
                    label: "Window Frame",
                    value: frame
                )
            }
        } header: {
            Text("Target")
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

private struct AIEditHistoryTextBlock: View {
    let label: LocalizedStringKey
    let text: String
    let systemImage: String
    var isMonospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            ScrollView {
                Text(text)
                    .font(isMonospaced ? .system(size: 11, weight: .regular, design: .monospaced) : .system(size: 14))
                    .lineSpacing(isMonospaced ? 2 : 3)
                    .foregroundColor(AppTheme.Text.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .frame(maxHeight: isMonospaced ? 360 : 260)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(AppTheme.Surface.materialCard)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .strokeBorder(AppTheme.Border.subtle, lineWidth: 1)
                    }
            )
            .hoverCopyButton(textToCopy: text)
        }
    }
}
