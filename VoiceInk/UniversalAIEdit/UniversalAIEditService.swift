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
        let systemPrompt = UniversalAIEditPromptBuilder.systemPrompt(mode: mode)
        let userPayload = UniversalAIEditPromptBuilder.userPayload(
            instruction: trimmedInstruction,
            mode: mode,
            context: context,
            customVocabulary: customVocabulary,
            userPreferences: UserDefaults.standard.string(forKey: UniversalAIEditUserPreferences.userDefaultsKey)
        )

        let start = Date()
        let response = try await aiService.completeChat(
            provider: provider,
            modelName: configuration.modelName,
            messages: [.user(userPayload)],
            systemPrompt: systemPrompt,
            timeout: requestTimeout
        )
        let filtered = AIEnhancementOutputFilter.filter(response)
        guard !filtered.isEmpty else {
            throw UniversalAIEditError.emptyModelOutput
        }

        return UniversalAIEditResult(
            text: filtered,
            provider: provider,
            modelName: modelName,
            duration: Date().timeIntervalSince(start),
            aiRequestSystemMessage: systemPrompt,
            aiRequestUserMessage: userPayload
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
}
