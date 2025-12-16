import Foundation

protocol LocalAIModeling: Sendable {
    func send(
        messages: [AIChatMessage],
        configuration: LocalAIConfiguration
    ) async throws -> String
}

enum LocalAIClientError: LocalizedError {
    case invalidEndpoint
    case invalidStatus(Int)
    case missingMessage

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The configured local model endpoint is not valid."
        case .invalidStatus(let status):
            return "Local model returned status code \(status)."
        case .missingMessage:
            return "Local model did not return a message."
        }
    }
}

struct OllamaClient: LocalAIModeling {
    func send(
        messages: [AIChatMessage],
        configuration: LocalAIConfiguration
    ) async throws -> String {
        let normalizedEndpoint = normalize(endpoint: configuration.endpoint)
        let chatEndpoint = normalizedEndpoint.appendingPathComponent("chat")
        var request = URLRequest(url: chatEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = try JSONEncoder().encode(
            RequestPayload(
                model: configuration.model,
                messages: messages.map { RequestPayload.Message(role: $0.role.rawValue, content: $0.content) },
                options: .init(
                    temperature: configuration.temperature,
                    numPredict: configuration.maxTokens
                )
            )
        )
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalAIClientError.invalidEndpoint
        }
        guard httpResponse.statusCode == 200 else {
            throw LocalAIClientError.invalidStatus(httpResponse.statusCode)
        }

        let chatResponse = try JSONDecoder().decode(ResponsePayload.self, from: data)
        guard let content = chatResponse.message?.content else {
            throw LocalAIClientError.missingMessage
        }
        return content
    }

    private func normalize(endpoint: URL) -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        var path = components?.path ?? ""
        if path.isEmpty || path == "/" {
            path = "/api"
        }
        if !path.hasSuffix("/api") {
            if path.hasSuffix("/") {
                path += "api"
            } else {
                path += "/api"
            }
        }
        components?.path = path
        return components?.url ?? endpoint.appendingPathComponent("api")
    }
}

private struct RequestPayload: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Options: Encodable {
        let temperature: Double
        let numPredict: Int

        enum CodingKeys: String, CodingKey {
            case temperature
            case numPredict = "num_predict"
        }
    }

    let model: String
    let messages: [Message]
    let stream: Bool = false
    let options: Options
}

private struct ResponsePayload: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String
    }

    let message: Message?
    let done: Bool?
}
