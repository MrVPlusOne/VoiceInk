import Foundation

enum UniversalAIEditOpenAIMultimodalClient {
    static func chatCompletion(
        baseURL: URL,
        apiKey: String,
        model: String,
        userPayload: String,
        screenshot: UniversalAIEditScreenshotContext,
        systemPrompt: String,
        temperature: Double,
        reasoningEffort: String?,
        timeout: TimeInterval
    ) async throws -> String {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": userPayload
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": screenshot.dataURL,
                                "detail": screenshot.detail
                            ]
                        ]
                    ]
                ]
            ],
            "temperature": temperature,
            "stream": false
        ]

        if let reasoningEffort {
            body["reasoning_effort"] = reasoningEffort
        }

        guard JSONSerialization.isValidJSONObject(body),
              let requestBody = try? JSONSerialization.data(withJSONObject: body) else {
            throw UniversalAIEditMultimodalRequestError.encodingFailed
        }

        request.httpBody = requestBody

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UniversalAIEditMultimodalRequestError.network
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UniversalAIEditMultimodalRequestError.http(statusCode: http.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            return decoded.choices.first?.message.content ?? ""
        } catch {
            throw UniversalAIEditMultimodalRequestError.decoding
        }
    }
}

enum UniversalAIEditMultimodalRequestError: LocalizedError {
    case encodingFailed
    case network
    case http(statusCode: Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return String(localized: "Failed to encode the screenshot request.")
        case .network:
            return String(localized: "Screenshot request failed because no HTTP response was received.")
        case .http(let statusCode):
            return String(format: String(localized: "Screenshot request failed with HTTP %d."), statusCode)
        case .decoding:
            return String(localized: "Screenshot request succeeded, but VoiceInk could not read the response.")
        }
    }

    var fallbackMetadataDescription: String {
        switch self {
        case .encodingFailed:
            return "encoding_failed"
        case .network:
            return "network_or_no_http_response"
        case .http(let statusCode):
            return "http_status_\(statusCode)"
        case .decoding:
            return "response_decoding_failed"
        }
    }
}

private struct OpenAIChatResponse: Decodable {
    let choices: [OpenAIChatChoice]
}

private struct OpenAIChatChoice: Decodable {
    let message: OpenAIChatMessage
}

private struct OpenAIChatMessage: Decodable {
    let content: String
}
