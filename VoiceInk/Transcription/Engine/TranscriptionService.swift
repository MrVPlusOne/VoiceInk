import Foundation

struct TranscriptionRequestContext {
    let language: String?
    let prompt: String?
    let recognitionContext: String?
    var diagnostics: TranscriptionDiagnosticsRecorder?

    init(language: String?, prompt: String?, recognitionContext: String? = nil) {
        self.language = language
        self.prompt = prompt
        self.recognitionContext = recognitionContext
    }

    static var currentDefaults: TranscriptionRequestContext {
        TranscriptionRequestContext(
            language: UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto",
            prompt: UserDefaults.standard.string(forKey: "TranscriptionPrompt"),
            recognitionContext: nil
        )
    }

    var promptWithRecognitionContext: String? {
        TranscriptionRecognitionContextBuilder.combinedPrompt(
            basePrompt: prompt,
            recognitionContext: recognitionContext
        )
    }

    func recordRequest(
        model: any TranscriptionModel,
        transport: String = "File",
        prompt: String? = nil,
        recognitionContext: String? = nil,
        notes: String
    ) {
        diagnostics?.record(TranscriptionRequestDiagnostics(
            model: (model as? CustomCloudModel)?.modelName ?? model.name,
            provider: model.provider.rawValue,
            transport: transport,
            language: language,
            prompt: prompt,
            recognitionContext: recognitionContext,
            notes: notes
        ))
    }
}

struct TranscriptionContextSourceSettings: Equatable {
    let includeSelectedText: Bool
    let includeClipboard: Bool
    let includeScreenText: Bool

    static let none = TranscriptionContextSourceSettings(
        includeSelectedText: false,
        includeClipboard: false,
        includeScreenText: false
    )

    static func mode(_ mode: ModeConfig?) -> TranscriptionContextSourceSettings {
        TranscriptionContextSourceSettings(
            includeSelectedText: mode?.useSelectedTextContext ?? defaultBool(forKey: "useSelectedTextContext", defaultValue: true),
            includeClipboard: mode?.useClipboardContext ?? UserDefaults.standard.bool(forKey: "useClipboardContext"),
            includeScreenText: mode?.useScreenCapture ?? UserDefaults.standard.bool(forKey: "useScreenCaptureContext")
        )
    }

    static func enhancement(_ configuration: EnhancementRuntimeConfiguration?) -> TranscriptionContextSourceSettings {
        TranscriptionContextSourceSettings(
            includeSelectedText: configuration?.useSelectedTextContext ?? false,
            includeClipboard: configuration?.useClipboardContext ?? false,
            includeScreenText: configuration?.useScreenCaptureContext ?? false
        )
    }

    private static func defaultBool(forKey key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }
}

enum TranscriptionContextModelSettings {
    private static let enabledKeyPrefix = "TranscriptionContextEnabled"

    static func storageID(for model: any TranscriptionModel) -> String {
        if let customModel = model as? CustomCloudModel {
            return "\(model.provider.rawValue):\(customModel.id.uuidString)"
        }

        return "\(model.provider.rawValue):\(model.name)"
    }

    static func userDefaultsKey(for model: any TranscriptionModel) -> String {
        "\(enabledKeyPrefix).\(storageID(for: model))"
    }

    static func supportsTranscriptionContext(_ model: any TranscriptionModel) -> Bool {
        if let customModel = model as? CustomCloudModel {
            return customModel.supportsTranscriptionContext
        }

        return model.provider == .openAI && isKnownOpenAITranscriptionContextModel(model.name)
    }

    static func isSendContextEnabled(for model: any TranscriptionModel, defaults: UserDefaults = .standard) -> Bool {
        TranscriptionContextPolicy.isEnabled(
            supported: supportsTranscriptionContext(model),
            isBuiltInOpenAI: model.provider == .openAI,
            explicitPreference: defaults.object(forKey: userDefaultsKey(for: model)) as? Bool
        )
    }

    static func setSendContextEnabled(_ isEnabled: Bool, for model: any TranscriptionModel, defaults: UserDefaults = .standard) {
        let key = userDefaultsKey(for: model)
        if supportsTranscriptionContext(model) {
            // Preserve an explicit opt-out even for models that default to using mode-allowed context.
            defaults.set(isEnabled, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    static func isKnownOpenAITranscriptionContextModel(_ modelName: String) -> Bool {
        TranscriptionContextPolicy.isKnownOpenAIModel(modelName)
    }
}

enum TranscriptionRecognitionContextBuilder {
    private static let maxTotalCharacters = 10_000
    private static let maxSelectedTextCharacters = 2_000
    private static let maxClipboardCharacters = 2_000
    private static let maxScreenTextCharacters = 4_000

    static func build(
        snapshot: RecordingContextSnapshot?,
        sourceSettings: TranscriptionContextSourceSettings
    ) -> String? {
        guard let snapshot else { return nil }

        return build(
            selectedText: sourceSettings.includeSelectedText ? snapshot.selectedText : nil,
            clipboardText: sourceSettings.includeClipboard ? snapshot.clipboardText : nil,
            screenText: sourceSettings.includeScreenText ? snapshot.screenText : nil
        )
    }

    static func build(
        selectedText: String?,
        clipboardText: String?,
        screenText: String?
    ) -> String? {
        var blocks: [String] = []

        // Speech models read the prompt as text that came before the audio, so this is plain prose, not markup.
        appendBlock(
            label: "Text the speaker has selected:",
            text: selectedText,
            maxCharacters: maxSelectedTextCharacters,
            to: &blocks
        )
        appendBlock(
            label: "Text on the speaker's clipboard:",
            text: clipboardText,
            maxCharacters: maxClipboardCharacters,
            to: &blocks
        )
        appendBlock(
            label: "Text on the speaker's screen, which may include names and terms they say:",
            text: screenText,
            maxCharacters: maxScreenTextCharacters,
            to: &blocks
        )

        guard !blocks.isEmpty else { return nil }

        return normalized(truncated(blocks.joined(separator: "\n\n"), maxCharacters: maxTotalCharacters))
    }

    static func combinedPrompt(basePrompt: String?, recognitionContext: String?) -> String? {
        let parts = [normalized(basePrompt), normalized(recognitionContext)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    private static func appendBlock(label: String, text: String?, maxCharacters: Int, to blocks: inout [String]) {
        guard let text = normalized(text) else { return }
        let trimmed = truncated(text, maxCharacters: maxCharacters)
        blocks.append("\(label)\n\(trimmed)")
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func truncated(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: max(0, maxCharacters - 1))
        return String(text[..<endIndex]) + "..."
    }
}

/// A protocol defining the interface for a transcription service.
/// This allows for a unified way to handle both local and cloud-based transcription models.
protocol TranscriptionService {
    /// Transcribes the audio from a given file URL.
    ///
    /// - Parameters:
    ///   - audioURL: The URL of the audio file to transcribe.
    ///   - model: The `TranscriptionModel` to use for transcription. This provides context about the provider (local, OpenAI, etc.).
    /// - Returns: The transcribed text as a `String`.
    /// - Throws: An error if the transcription fails.
    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws -> String
}

extension TranscriptionService {
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        try await transcribe(audioURL: audioURL, model: model, context: .currentDefaults)
    }
}
