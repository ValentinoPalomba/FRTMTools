
import Foundation

struct SecurityScanResult: Identifiable, Codable, Hashable {
    let id: UUID
    var projectName: String
    var projectPath: String
    var scanDate: Date
    var findings: [SecurityFinding]
    
    init(projectPath: String, findings: [SecurityFinding]) {
        self.id = UUID()
        self.projectName = URL(fileURLWithPath: projectPath).lastPathComponent
        self.projectPath = projectPath
        self.scanDate = Date()
        self.findings = findings
    }
}
