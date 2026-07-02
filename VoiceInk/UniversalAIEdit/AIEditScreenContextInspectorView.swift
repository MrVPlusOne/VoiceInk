import SwiftUI

struct AIEditScreenContextInspectorView: View {
    let contextText: String
    var subtitle: String?

    @Environment(\.dismiss) private var dismiss

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

                ScrollView {
                    Text(contextText)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .lineSpacing(3)
                        .foregroundColor(AppTheme.Text.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minHeight: 320)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .fill(AppTheme.Surface.materialCard)
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                .strokeBorder(AppTheme.Border.subtle, lineWidth: 1)
                        }
                )
                .hoverCopyButton(textToCopy: contextText, accessibilityLabel: "Copy screen context")
            }
            .padding(16)
        }
        .frame(minWidth: 560, idealWidth: 720, minHeight: 440, idealHeight: 560)
        .background(SidePanelBackground())
    }
}
