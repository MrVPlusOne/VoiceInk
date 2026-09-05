import Foundation

/// The newer model accepts `languages[]`, unlike the older models' `language` field.
enum GPTTranscribeRequest {
    static let modelName = "gpt-transcribe"

    static func make(
        audioData: Data,
        apiKey: String,
        language: String?,
        prompt: String?,
        keywords: [String],
        boundary: String = "Boundary-\(UUID().uuidString)"
    ) -> URLRequest {
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        append("\r\n")
        field("model", modelName)
        field("response_format", "json")
        if let language, !language.isEmpty, language != "auto" {
            field("languages[]", language)
        }
        if let prompt, !prompt.isEmpty {
            field("prompt", prompt)
        }
        for keyword in keywords where !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            field("keywords[]", keyword)
        }
        append("--\(boundary)--\r\n")

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
}
