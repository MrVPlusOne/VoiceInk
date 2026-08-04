import Foundation
import AppKit

struct RecordingContextSnapshot {
    var capturedAt = Date()
    var selectedText: String?
    var clipboardText: String?
    var screenText: String?
    var screenshotContext: UniversalAIEditScreenshotContext?
}

@MainActor
final class RecordingContextSnapshotStore {
    private(set) var snapshot = RecordingContextSnapshot()

    func updateSelectedText(_ text: String?) {
        snapshot.selectedText = Self.normalized(text)
    }

    func updateClipboardText(_ text: String?) {
        snapshot.clipboardText = Self.normalized(text)
    }

    func updateScreenText(_ text: String?) {
        snapshot.screenText = Self.normalized(text)
        snapshot.screenshotContext = nil
    }

    func updateScreenContext(_ context: ActiveWindowCaptureResult?) {
        snapshot.screenText = Self.normalized(context?.contextText)
        snapshot.screenshotContext = context?.screenshotContext
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
enum RecordingContextCaptureService {
    static func startCapture(
        into store: RecordingContextSnapshotStore,
        includeScreenshotContext: Bool = false
    ) -> [Task<Void, Never>] {
        [
            Task { @MainActor in
                store.updateClipboardText(NSPasteboard.general.string(forType: .string))
            },
            Task { @MainActor in
                guard !Task.isCancelled else { return }
                let selectedText = await SelectedTextService.fetchSelectedText()
                guard !Task.isCancelled else { return }
                store.updateSelectedText(selectedText)
            },
            Task { @MainActor in
                guard CGPreflightScreenCaptureAccess(), !Task.isCancelled else { return }
                let screenCaptureService = ScreenCaptureService()
                let context = await screenCaptureService.captureWindowContext(
                    includeScreenshot: includeScreenshotContext
                )
                guard !Task.isCancelled else { return }
                store.updateScreenContext(context)
            }
        ]
    }

    nonisolated static func shouldIncludeScreenshotContext(
        enhancementConfiguration: EnhancementRuntimeConfiguration?,
        isEnhancementConfigured: Bool
    ) -> Bool {
        guard isEnhancementConfigured,
              let enhancementConfiguration,
              enhancementConfiguration.isEnabled,
              enhancementConfiguration.useScreenCaptureContext,
              let provider = enhancementConfiguration.provider else {
            return false
        }

        let modelName = enhancementConfiguration.modelName ?? provider.defaultModel
        return ScreenshotContextCapability.supportsScreenshotContext(
            provider: provider,
            modelName: modelName
        )
    }
}
