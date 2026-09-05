import AppKit
import SwiftUI

struct ErrorDetailsView: View {
    let error: APIErrorPresentation
    let onClose: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(error.title, systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(error.guidance)
                        .textSelection(.enabled)
                    Text("Error details")
                        .font(.headline)
                    Text(error.details)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button(copied ? "Copied" : "Copy details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error.copyableText, forType: .string)
                    copied = true
                }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 300)
    }
}
