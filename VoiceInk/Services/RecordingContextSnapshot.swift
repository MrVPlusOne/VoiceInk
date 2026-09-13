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
    let readiness = RecordingContextReadiness()

    func snapshotWhenReady() async -> RecordingContextSnapshot {
        await readiness.wait()
        return snapshot
    }

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
        sourceSettings: TranscriptionContextSourceSettings,
        includeScreenshotContext: Bool = false
    ) -> [Task<Void, Never>] {
        // Freeze the target before asynchronous selection capture can change focus.
        let screenCaptureService = ScreenCaptureService()
        let target = sourceSettings.includeScreenText
            ? screenCaptureService.makeFocusedWindowHint(excluding: ProcessInfo.processInfo.processIdentifier)
            : nil
        var tasks: [Task<Void, Never>] = []

        if sourceSettings.includeClipboard {
            store.updateClipboardText(NSPasteboard.general.string(forType: .string))
        }
        if sourceSettings.includeSelectedText {
            store.readiness.started()
            tasks.append(Task { @MainActor in
                defer { store.readiness.finished() }
                guard !Task.isCancelled else { return }
                let selectedText = await SelectedTextService.fetchSelectedText()
                guard !Task.isCancelled else { return }
                store.updateSelectedText(selectedText)
            })
        }
        if sourceSettings.includeScreenText, let target {
            store.readiness.started()
            tasks.append(Task { @MainActor in
                defer { store.readiness.finished() }
                guard CGPreflightScreenCaptureAccess(), !Task.isCancelled else { return }
                let context = await screenCaptureService.captureWindowContext(
                    includeScreenshot: includeScreenshotContext,
                    targetWindowHint: target
                )
                guard !Task.isCancelled else { return }
                store.updateScreenContext(context)
            })
        }
        return tasks
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
