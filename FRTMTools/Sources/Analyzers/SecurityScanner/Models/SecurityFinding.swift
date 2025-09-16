
import Foundation

struct SecurityFinding: Identifiable, Hashable, Codable {
    let id = UUID()
    var filePath: String
    var lineNumber: Int
    var content: String
    var ruleName: String
}
