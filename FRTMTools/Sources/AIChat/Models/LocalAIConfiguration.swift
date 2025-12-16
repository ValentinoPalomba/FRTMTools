import Foundation

struct LocalAIConfiguration: Codable, Equatable {
    enum ResponseLanguage: String, Codable, CaseIterable, Sendable {
        case english = "English"
        case italian = "Italian"
    }

    var endpoint: URL
    var model: String
    var temperature: Double
    var maxTokens: Int
    var systemPrompt: String
    var historyLimit: Int
    var preferredLanguage: ResponseLanguage

    static var `default`: LocalAIConfiguration {
        LocalAIConfiguration(
            endpoint: URL(string: "http://127.0.0.1:11434")!,
            model: "llama3",
            temperature: 0.2,
            maxTokens: 768,
            systemPrompt: "You are an expert mobile build analyst that explains the findings of the provided report. Answer with concise bullet points unless the user specifically asks for prose.",
            historyLimit: 10,
            preferredLanguage: .italian
        )
    }

    enum CodingKeys: String, CodingKey {
        case endpoint
        case model
        case temperature
        case maxTokens
        case systemPrompt
        case historyLimit
        case preferredLanguage
    }

    init(
        endpoint: URL,
        model: String,
        temperature: Double,
        maxTokens: Int,
        systemPrompt: String,
        historyLimit: Int,
        preferredLanguage: ResponseLanguage
    ) {
        self.endpoint = endpoint
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
        self.historyLimit = historyLimit
        self.preferredLanguage = preferredLanguage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decode(URL.self, forKey: .endpoint)
        model = try container.decode(String.self, forKey: .model)
        temperature = try container.decode(Double.self, forKey: .temperature)
        maxTokens = try container.decode(Int.self, forKey: .maxTokens)
        systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
        historyLimit = try container.decode(Int.self, forKey: .historyLimit)
        preferredLanguage = try container.decodeIfPresent(ResponseLanguage.self, forKey: .preferredLanguage) ?? .italian
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(model, forKey: .model)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encode(systemPrompt, forKey: .systemPrompt)
        try container.encode(historyLimit, forKey: .historyLimit)
        try container.encode(preferredLanguage, forKey: .preferredLanguage)
    }
}

@MainActor
final class LocalAIConfigurationStore: ObservableObject {
    static let shared = LocalAIConfigurationStore()

    @Published var configuration: LocalAIConfiguration {
        didSet { persistConfiguration() }
    }

    private let defaults = UserDefaults.standard
    private let storageKey = "local_ai_configuration"

    private init() {
        if
            let stored = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(LocalAIConfiguration.self, from: stored)
        {
            configuration = decoded
        } else {
            configuration = .default
        }
    }

    func reset() {
        configuration = .default
    }

    private func persistConfiguration() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
