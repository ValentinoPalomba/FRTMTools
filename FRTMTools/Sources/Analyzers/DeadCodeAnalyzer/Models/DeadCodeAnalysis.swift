import Foundation

struct DeadCodeAnalysis: Identifiable, Codable {
    let id: UUID
    let projectName: String
    let projectPath: String
    let scanTimeDuration: TimeInterval
    var results: [SerializableDeadCodeResult]
}
