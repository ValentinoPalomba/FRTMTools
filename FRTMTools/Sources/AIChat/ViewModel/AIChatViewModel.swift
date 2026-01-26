import Foundation
import Observation

@MainActor
@Observable
final class AIChatViewModel {
    private(set) var messages: [AIChatMessage] = []
    var isSending = false
    var errorMessage: String?

    let context: AnalysisContext
    let configurationStore: LocalAIConfigurationStore

    @ObservationIgnored private let client: LocalAIModeling

    init(
        context: AnalysisContext,
        configurationStore: LocalAIConfigurationStore = .shared,
        client: LocalAIModeling = OllamaClient()
    ) {
        self.context = context
        self.configurationStore = configurationStore
        self.client = client
        seedWelcomeMessage()
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isSending else { return }

        let userMessage = AIChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        isSending = true
        errorMessage = nil

        do {
            let payload = buildPayloadMessages()
            let reply = try await client.send(messages: payload, configuration: configurationStore.configuration)
            messages.append(AIChatMessage(role: .assistant, content: reply))
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    func resetConversation() {
        messages.removeAll()
        seedWelcomeMessage()
    }

    private func seedWelcomeMessage() {
        let greeting = """
        Hi! I'm your on-device AI assistant. Ask me about \(context.title) and I'll explain what the analysis discovered.
        """
        messages.append(AIChatMessage(role: .assistant, content: greeting))
    }

    private func buildPayloadMessages() -> [AIChatMessage] {
        let system = AIChatMessage(
            role: .system,
            content: """
            \(configurationStore.configuration.systemPrompt)

            Context you must rely on:

            \(context.summary)

            Always answer in \(configurationStore.configuration.preferredLanguage.rawValue).
            """
        )

        let usableHistory = messages
            .filter { $0.role != .system }
            .suffix(configurationStore.configuration.historyLimit * 2)

        return [system] + usableHistory
    }
}
