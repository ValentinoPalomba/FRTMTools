import Foundation

struct DeadCodeAnalysis: Identifiable, Codable {
    let id: UUID
    let projectName: String
    let projectPath: String
    let scanTimeDuration: TimeInterval
    var results: [SerializableDeadCodeResult]
}

extension DeadCodeAnalysis: Exportable {
    func export() throws -> String {
        let header = "Category,Name,Description,File Path\n"
        
        let groupedResults = Dictionary(grouping: results, by: { $0.kind })
        let deadCodeGroups = groupedResults.map { DeadCodeGroup(kind: $0.key, results: $0.value) }

        let rows = deadCodeGroups.flatMap { group in
            group.results.map { result -> String in
                let category = escapeCSVField(group.kind)
                let name = escapeCSVField(result.name ?? "Unknown")
                let description = escapeCSVField(result.annotationDescription)
                let fileUrl = URL(string: result.filePath)
                let filePath = escapeCSVField(fileUrl?.lastPathComponent ?? "")
                return "\(category),\(name),\(description),\(filePath)"
            }
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
