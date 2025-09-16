
import Foundation

struct SecurityFinding: Identifiable, Hashable, Codable {
    var id = UUID()
    var filePath: String
    var lineNumber: Int
    var content: String
    var ruleName: String
}
