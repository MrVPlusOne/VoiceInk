import Foundation
import SwiftData
import LLMkit

struct OpenAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .openAI
    let providerKey = "OpenAI"
    let languageCodes: [String]? = nil
    let includesAutoDetect = true

    private let baseURL = URL(string: "https://api.openai.com")!

    var models: [CloudModel] { [
        model(name: "gpt-4o-transcribe", displayName: "GPT-4o Transcribe",
              description: "OpenAI's GPT-4o speech-to-text model", speed: 0.8, accuracy: 0.95),
        model(name: GPTTranscribeRequest.modelName, displayName: "GPT Transcribe",
              description: "OpenAI's latest speech-to-text model with multilingual and keyword hints", speed: 0.8, accuracy: 0.95),
        model(name: "gpt-4o-mini-transcribe", displayName: "GPT-4o Mini Transcribe",
              description: "OpenAI's smaller, faster speech-to-text model", speed: 0.9, accuracy: 0.9),
        model(name: "whisper-1", displayName: "Whisper (OpenAI)",
              description: "OpenAI's hosted Whisper speech-to-text model", speed: 0.7, accuracy: 0.9)
    ] }

    private func model(name: String, displayName: String, description: String, speed: Double, accuracy: Double) -> CloudModel {
        CloudModel(
            name: name, displayName: displayName, description: description,
            provider: .openAI, speed: speed, accuracy: accuracy, isMultilingual: true,
            supportedLanguages: LanguageDictionary.forProvider(isMultilingual: true, provider: .openAI)
        )
    }

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        if model == GPTTranscribeRequest.modelName {
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CloudTranscriptionError.missingAPIKey
            }
            let request = GPTTranscribeRequest.make(
                audioData: audioData, apiKey: apiKey, language: language,
                prompt: prompt, keywords: customVocabulary
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
            }
            guard (200..<300).contains(http.statusCode) else {
                throw CloudTranscriptionError.apiRequestFailed(
                    statusCode: http.statusCode,
                    message: String(data: data, encoding: .utf8) ?? "No error details"
                )
            }
            guard let result = try? JSONDecoder().decode(GPTTranscribeResponse.self, from: data),
                  !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return result.text
        }

        return try await OpenAITranscriptionClient.transcribe(
            baseURL: baseURL, audioData: audioData, fileName: fileName,
            apiKey: apiKey, model: model, language: language, prompt: prompt
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? { nil }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        await OpenAITranscriptionClient.verifyAPIKey(baseURL: baseURL, apiKey: key)
    }

    private struct GPTTranscribeResponse: Decodable {
        let text: String
    }
}
