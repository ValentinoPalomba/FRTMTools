
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

extension SecurityScanResult: Exportable {
    func export() throws -> String {
        let header = "File,Line,Description\n"
        let rows = findings.map { finding in
            let file = escapeCSVField(finding.filePath)
            let line = "\(finding.lineNumber)"
            let description = escapeCSVField(finding.content)
            return "\(file),\(line),\(description)"
        }
        return header + rows.joined(separator: "\n")
    }
    
    private func escapeCSVField(_ field: String) -> String {
        var escaped = field
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            escaped = escaped.replacingOccurrences(of: "\"", with: "")
            escaped = "\"\(escaped)\""
        }
        return escaped
    }
}
