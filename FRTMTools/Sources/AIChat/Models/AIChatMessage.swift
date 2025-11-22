import Foundation

enum AIChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

struct AIChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: AIChatRole
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: AIChatRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
