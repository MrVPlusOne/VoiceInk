import AppKit
import SwiftUI

struct AIEditScreenContextInspectorView: View {
    var contextText: String?
    var screenshotData: Data?
    var screenshotMetadata: String?
    var subtitle: String?

    @Environment(\.dismiss) private var dismiss

    private var screenshotImage: NSImage? {
        guard let screenshotData else { return nil }
        return NSImage(data: screenshotData)
    }

    var body: some View {
        VStack(spacing: 0) {
            AppPanelHeader(title: "Screen Context", onClose: { dismiss() })

            VStack(alignment: .leading, spacing: 12) {
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.Text.secondary)
                        .lineLimit(2)
                }

                if let screenshotImage {
                    screenshotBlock(screenshotImage)
                }

                if let screenshotMetadata, !screenshotMetadata.isEmpty {
                    textBlock(
                        title: "Screenshot Metadata",
                        text: screenshotMetadata,
                        maxHeight: 180
                    )
                }

                if let contextText, !contextText.isEmpty {
                    textBlock(
                        title: screenshotImage == nil ? "Screen Context" : "OCR Fallback Context",
                        text: contextText,
                        maxHeight: screenshotImage == nil ? 320 : 220
                    )
                }
            }
            .padding(16)
        }
        .frame(minWidth: 560, idealWidth: 720, minHeight: 440, idealHeight: 560)
        .background(SidePanelBackground())
    }

    private func screenshotBlock(_ image: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Screenshot", systemImage: "photo")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(12)
            }
            .frame(minHeight: 280, maxHeight: 420)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(AppTheme.Surface.materialCard)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .strokeBorder(AppTheme.Border.subtle, lineWidth: 1)
                    }
            )
        }
    }

    private func textBlock(title: LocalizedStringKey, text: String, maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "text.alignleft")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            ScrollView {
                Text(text)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundColor(AppTheme.Text.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: maxHeight)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .fill(AppTheme.Surface.materialCard)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .strokeBorder(AppTheme.Border.subtle, lineWidth: 1)
                    }
            )
            .hoverCopyButton(textToCopy: text, accessibilityLabel: "Copy screen context")
        }
    }
}
