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
            throw UniversalAIEditMultimodalRequestError.network("No HTTP response received.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "No error details"
            throw UniversalAIEditMultimodalRequestError.http(statusCode: http.statusCode, message: message)
        }

        do {
            let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            return decoded.choices.first?.message.content ?? ""
        } catch {
            throw UniversalAIEditMultimodalRequestError.decoding(error.localizedDescription)
        }
    }
}

enum UniversalAIEditMultimodalRequestError: LocalizedError {
    case encodingFailed
    case network(String)
    case http(statusCode: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return String(localized: "Failed to encode the screenshot request.")
        case .network(let message):
            return String(format: String(localized: "Screenshot request network error: %@"), message)
        case .http(let statusCode, let message):
            return String(format: String(localized: "Screenshot request failed with HTTP %d: %@"), statusCode, message)
        case .decoding(let message):
            return String(format: String(localized: "Failed to read screenshot response: %@"), message)
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
