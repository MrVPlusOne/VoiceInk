import SwiftUI

struct UniversalAIEditPanelView: View {
    @ObservedObject var manager: UniversalAIEditManager
    @FocusState private var instructionFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 14) {
                contextSummary
                instructionEditor
                statusArea
                previewArea
                actionBar
            }
            .padding(18)
        }
        .frame(width: 660, height: 600)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.Surface.window)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.Border.card, lineWidth: 1)
        )
        .onAppear {
            instructionFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.Accent.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(AppTheme.Accent.fill))

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Edit")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)
                Text(manager.mode.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Text.secondary)
            }

            Spacer()

            Button {
                manager.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    private var contextSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(manager.context?.target.displayName ?? "Target app", systemImage: "macwindow")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.Text.primary)
                    .lineLimit(1)

                Spacer()

                Picker("", selection: $manager.mode) {
                    Text("Edit selection").tag(UniversalAIEditMode.replaceSelection)
                    Text("Generate").tag(UniversalAIEditMode.insertNew)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .disabled(manager.phase.isBusy)
            }

            HStack(spacing: 6) {
                contextChip(
                    title: manager.context?.selectedText == nil ? "No selection" : "Selection",
                    systemImage: "text.cursor",
                    isActive: manager.context?.selectedText != nil
                )
                contextChip(
                    title: manager.context?.screenText == nil ? "No screen context" : "Screen context",
                    systemImage: "rectangle.on.rectangle",
                    isActive: manager.context?.screenText != nil
                )
                contextChip(
                    title: manager.context?.clipboardText == nil ? "Clipboard off" : "Clipboard",
                    systemImage: "doc.on.clipboard",
                    isActive: manager.context?.clipboardText != nil
                )
            }

            if let selectedText = manager.context?.selectedText, !selectedText.isEmpty {
                Text(selectedText)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Text.secondary)
                    .lineLimit(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.Surface.subtle)
                    )
            }
        }
    }

    private func contextChip(title: String, systemImage: String, isActive: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isActive ? AppTheme.Text.primary : AppTheme.Text.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isActive ? AppTheme.Selection.fill : AppTheme.Surface.subtle)
            )
    }

    private var instructionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Instruction")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)
                Spacer()
                Button {
                    manager.toggleVoiceInstruction()
                } label: {
                    Label(
                        manager.isVoiceRecording ? "Stop" : "Voice",
                        systemImage: manager.isVoiceRecording ? "stop.fill" : "mic.fill"
                    )
                    .font(.system(size: 12, weight: .medium))
                }
                .disabled(manager.phase == .generating || manager.phase == .applying)
            }

            TextEditor(text: $manager.instruction)
                .font(.system(size: 14))
                .focused($instructionFocused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 96)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.Surface.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(instructionFocused ? AppTheme.Accent.border : AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        if let status = manager.statusText {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(status)
                    .font(.system(size: 12))
                    .foregroundColor(statusColor)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(statusColor.opacity(0.10))
            )
        }
    }

    private var statusColor: Color {
        switch manager.phase {
        case .failed:
            return AppTheme.Status.error
        case .listening, .transcribingInstruction, .generating, .applying:
            return AppTheme.Accent.primary
        default:
            return AppTheme.Text.secondary
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        if !manager.generatedText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Preview")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.Text.primary)
                    Spacer()
                    if let result = manager.lastResult {
                        Text(result.modelName)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.Text.muted)
                            .lineLimit(1)
                    }
                }

                ScrollView {
                    Text(manager.generatedText)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.Text.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(maxHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.Surface.subtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.Border.subtle, lineWidth: 1)
                )
            }
        } else {
            Spacer(minLength: 8)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Discard") {
                manager.discardPreview()
            }
            .disabled(manager.generatedText.isEmpty || manager.phase.isBusy)

            Spacer()

            Button("Copy") {
                manager.copyResult()
            }
            .disabled(manager.generatedText.isEmpty || manager.phase.isBusy)

            Button("Generate") {
                manager.generate()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!manager.canGenerate)

            Button("Apply") {
                manager.applyResult()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!manager.canApply)
        }
    }
}
