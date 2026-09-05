import Foundation
import Testing
@testable import VoiceInk

@MainActor
struct OpenAITranscriptionSetupTests {
    @Test func openAIIsAvailableInOnboardingAndModelCatalog() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let coordinator = OnboardingCoordinator(defaults: defaults)
        #expect(coordinator.onboardingTranscriptionProviderOptions.contains { $0.providerKey == "OpenAI" })
        let provider = try #require(CloudProviderRegistry.provider(for: .openAI))
        #expect(provider.models.map(\.name) == ["gpt-4o-transcribe", "gpt-transcribe", "gpt-4o-mini-transcribe", "whisper-1"])
        for model in provider.models {
            #expect(TranscriptionModelRegistry.models.contains { $0.name == model.name && $0.provider == .openAI })
            #expect(!model.supportsStreaming)
        }
    }

    @Test func selectedOpenAIModelSurvivesOnboardingReload() throws {
        #expect(OnboardingStorageKeys.onboardingKeys.contains(OnboardingStorageKeys.transcriptionModel))
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let coordinator = OnboardingCoordinator(defaults: defaults)
        coordinator.storedTranscriptionSetupKind = OnboardingTranscriptionSetupKind.cloud.rawValue
        coordinator.storedOnboardingTranscriptionProvider = "OpenAI"
        #expect(coordinator.selectedOnboardingTranscriptionModelName == "gpt-4o-transcribe")
        coordinator.selectedOnboardingTranscriptionModelBinding().wrappedValue = "gpt-transcribe"
        let restored = OnboardingCoordinator(defaults: defaults)
        #expect(restored.selectedOnboardingTranscriptionModelName == "gpt-transcribe")
        #expect(!restored.selectedOnboardingTranscriptionUsesRealtime)

        // A different provider must never inherit an OpenAI-only model ID.
        restored.storedOnboardingTranscriptionProvider = "Groq"
        #expect(restored.selectedOnboardingTranscriptionModel?.provider == .groq)
        restored.selectedOnboardingTranscriptionModelBinding().wrappedValue = "whisper-1"
        #expect(restored.selectedOnboardingTranscriptionModel?.provider == .groq)
    }
}
