import Foundation
import LLMkit
import SwiftData

@MainActor
final class UniversalAIEditService {
    private var requestTimeout: TimeInterval {
        let stored = UserDefaults.standard.integer(forKey: "EnhancementTimeoutSeconds")
        return stored > 0 ? TimeInterval(stored) : 7
    }

    func generate(
        instruction: String,
        mode: UniversalAIEditMode,
        context: UniversalAIEditContext,
        enhancementService: AIEnhancementService,
        modelContext: ModelContext
    ) async throws -> UniversalAIEditResult {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else {
            throw UniversalAIEditError.emptyInstruction
        }

        guard let aiService = enhancementService.getAIService() else {
            throw UniversalAIEditError.missingEnhancementService
        }

        let configuration = ModeRuntimeResolver.currentEnhancementConfiguration(
            enhancementService: enhancementService,
            aiService: aiService
        )

        guard let provider = configuration.provider else {
            throw UniversalAIEditError.modelNotConfigured
        }

        let modelName = configuration.modelName ?? provider.defaultModel
        guard isConfigured(provider: provider, modelName: modelName) else {
            throw UniversalAIEditError.modelNotConfigured
        }

        let customVocabulary = CustomVocabularyService.shared.getCustomVocabulary(from: modelContext)
        let shouldUseScreenshot = shouldUseScreenshotContext(
            context: context,
            provider: provider,
            modelName: modelName
        )
        let screenContextMode: UniversalAIEditScreenContextPromptMode = shouldUseScreenshot ? .screenshot : .ocrText
        let systemPrompt = UniversalAIEditPromptBuilder.systemPrompt(
            mode: mode,
            screenContextMode: screenContextMode
        )
        let userPayload = UniversalAIEditPromptBuilder.userPayload(
            instruction: trimmedInstruction,
            mode: mode,
            context: context,
            customVocabulary: customVocabulary,
            userPreferences: UserDefaults.standard.string(forKey: UniversalAIEditUserPreferences.userDefaultsKey),
            screenContextMode: screenContextMode
        )

        let start = Date()
        let response: String
        let requestSystemPrompt: String
        let requestUserPayload: String
        let screenshotContextForHistory: UniversalAIEditScreenshotContext?
        if shouldUseScreenshot, let screenshotContext = context.screenshotContext {
            screenshotContextForHistory = screenshotContext
            do {
                response = try await generateWithScreenshotContext(
                    provider: provider,
                    modelName: modelName,
                    userPayload: userPayload,
                    screenshotContext: screenshotContext,
                    systemPrompt: systemPrompt
                )
                requestSystemPrompt = systemPrompt
                requestUserPayload = userPayload
            } catch {
                let fallbackSystemPrompt = UniversalAIEditPromptBuilder.systemPrompt(
                    mode: mode,
                    screenContextMode: .ocrText
                )
                let fallbackUserPayload = UniversalAIEditPromptBuilder.userPayload(
                    instruction: trimmedInstruction,
                    mode: mode,
                    context: context,
                    customVocabulary: customVocabulary,
                    userPreferences: UserDefaults.standard.string(forKey: UniversalAIEditUserPreferences.userDefaultsKey),
                    screenContextMode: .ocrText
                )
                requestSystemPrompt = fallbackSystemPrompt
                requestUserPayload = Self.appendingScreenshotFallbackMetadata(
                    to: fallbackUserPayload,
                    screenshotContext: screenshotContext,
                    error: error
                )
                response = try await aiService.completeChat(
                    provider: provider,
                    modelName: configuration.modelName,
                    messages: [.user(fallbackUserPayload)],
                    systemPrompt: requestSystemPrompt,
                    timeout: requestTimeout
                )
            }
        } else {
            response = try await aiService.completeChat(
                provider: provider,
                modelName: configuration.modelName,
                messages: [.user(userPayload)],
                systemPrompt: systemPrompt,
                timeout: requestTimeout
            )
            requestSystemPrompt = systemPrompt
            requestUserPayload = userPayload
            screenshotContextForHistory = nil
        }
        let filtered = AIEnhancementOutputFilter.filter(response)
        guard !filtered.isEmpty else {
            throw UniversalAIEditError.emptyModelOutput
        }

        return UniversalAIEditResult(
            text: filtered,
            provider: provider,
            modelName: modelName,
            duration: Date().timeIntervalSince(start),
            aiRequestSystemMessage: requestSystemPrompt,
            aiRequestUserMessage: requestUserPayload,
            screenshotContextForHistory: screenshotContextForHistory
        )
    }

    private func isConfigured(provider: AIProvider, modelName: String) -> Bool {
        switch provider {
        case .localCLI, .ollama:
            return true
        case .custom:
            return CustomAIProviderManager.shared.requestConfiguration(forModel: modelName) != nil
        default:
            return APIKeyManager.shared.hasAPIKey(forProvider: provider.rawValue)
        }
    }

    private func shouldUseScreenshotContext(
        context: UniversalAIEditContext,
        provider: AIProvider,
        modelName: String
    ) -> Bool {
        guard UniversalAIEditScreenshotContextSettings.isEnabled,
              context.screenshotContext != nil else {
            return false
        }

        return UniversalAIEditScreenshotCapability.supportsScreenshotContext(
            provider: provider,
            modelName: modelName
        )
    }

    private func generateWithScreenshotContext(
        provider: AIProvider,
        modelName: String,
        userPayload: String,
        screenshotContext: UniversalAIEditScreenshotContext,
        systemPrompt: String
    ) async throws -> String {
        guard provider == .openAI,
              let baseURL = URL(string: provider.baseURL) else {
            throw UniversalAIEditError.modelNotConfigured
        }

        let temperature = modelName.lowercased().hasPrefix("gpt-5") ? 1.0 : 0.3
        let reasoningEffort = ReasoningConfig.getReasoningParameter(
            for: provider,
            modelName: modelName
        )

        return try await UniversalAIEditOpenAIMultimodalClient.chatCompletion(
            baseURL: baseURL,
            apiKey: try apiKey(for: provider, modelName: modelName),
            model: modelName,
            userPayload: userPayload,
            screenshot: screenshotContext,
            systemPrompt: systemPrompt,
            temperature: temperature,
            reasoningEffort: reasoningEffort,
            timeout: requestTimeout
        )
    }

    private func apiKey(for provider: AIProvider, modelName: String) throws -> String {
        if provider == .custom {
            guard let customConfiguration = CustomAIProviderManager.shared.requestConfiguration(forModel: modelName) else {
                throw UniversalAIEditError.modelNotConfigured
            }
            return customConfiguration.apiKey
        }

        guard let key = APIKeyManager.shared.getAPIKey(forProvider: provider.rawValue), !key.isEmpty else {
            throw UniversalAIEditError.modelNotConfigured
        }
        return key
    }

    private static func appendingScreenshotFallbackMetadata(
        to userPayload: String,
        screenshotContext: UniversalAIEditScreenshotContext,
        error: Error
    ) -> String {
        let fallbackReason: String
        if let multimodalError = error as? UniversalAIEditMultimodalRequestError {
            fallbackReason = multimodalError.fallbackMetadataDescription
        } else {
            fallbackReason = "screenshot_request_failed"
        }

        return """
        \(userPayload)

        <SCREENSHOT_CONTEXT_FALLBACK>
        Screenshot context was requested, but the image request failed. VoiceInk fell back to OCR text screen context.
        Failure: \(fallbackReason)
        \(screenshotContext.redactedMetadata)
        </SCREENSHOT_CONTEXT_FALLBACK>
        """
    }
}
