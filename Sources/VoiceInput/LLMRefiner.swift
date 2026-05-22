import Foundation

struct LLMConfig: Codable {
    var apiBaseURL: String
    var apiKey: String
    var model: String
}

final class LLMRefiner {
    private let settings: AppSettings
    private let session: URLSession

    init(settings: AppSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func refine(_ text: String) async throws -> String {
        guard settings.hasCompleteLLMConfiguration else {
            return text
        }

        let request = try makeRequest(for: text, maxTokens: 256)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try parseCompletionText(from: data) ?? text
    }

    func testConfiguration() async throws -> String {
        guard settings.hasCompleteLLMConfiguration else {
            throw RefinerError.missingConfiguration
        }

        let request = try makeRequest(for: "OK", maxTokens: 8, isTest: true)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try parseCompletionText(from: data) ?? "OK"
    }
}

extension LLMRefiner {
    enum RefinerError: LocalizedError {
        case missingConfiguration
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "LLM configuration is incomplete"
            case .invalidResponse:
                return "Invalid LLM response"
            }
        }
    }
}

private extension LLMRefiner {
    func makeRequest(for text: String, maxTokens: Int, isTest: Bool = false) throws -> URLRequest {
        let endpoint = try endpointURL()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")

        let systemPrompt = """
        You are a cautious speech transcription corrector.
        Fix only obvious speech recognition mistakes.
        Keep correct text unchanged.
        Do not rewrite, polish, expand, translate, or summarize.
        Pay special attention to Chinese homophones and technical English terms misheard as Chinese.
        If the input already looks correct, return it exactly as-is.
        Return only the corrected text.
        """

        let userContent = isTest ? "Reply with exactly OK." : text

        let body: [String: Any] = [
            "model": settings.model,
            "temperature": 0,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func endpointURL() throws -> URL {
        let raw = settings.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw RefinerError.missingConfiguration }

        let normalized: String
        if raw.hasSuffix("/chat/completions") {
            normalized = raw
        } else if raw.hasSuffix("/") {
            normalized = raw + "chat/completions"
        } else if raw.hasSuffix("/v1") {
            normalized = raw + "/chat/completions"
        } else {
            normalized = raw + "/chat/completions"
        }

        guard let url = URL(string: normalized) else {
            throw RefinerError.missingConfiguration
        }
        return url
    }

    func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw RefinerError.invalidResponse
        }
        guard !data.isEmpty else {
            throw RefinerError.invalidResponse
        }
    }

    func parseCompletionText(from data: Data) throws -> String? {
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String
        }
        let message: Message
    }

    let choices: [Choice]
}
