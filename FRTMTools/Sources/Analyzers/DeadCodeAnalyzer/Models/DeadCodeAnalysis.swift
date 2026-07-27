import Foundation

struct DeadCodeAnalysis: Identifiable, Codable, Sendable {
    static let currentGraphSnapshotVersion = 5

    let id: UUID
    let projectName: String
    let projectPath: String
    let scheme: String?
    let scanTimeDuration: TimeInterval
    let graphSnapshotVersion: Int
    var results: [SerializableDeadCodeResult]

    init(
        id: UUID,
        projectName: String,
        projectPath: String,
        scheme: String?,
        scanTimeDuration: TimeInterval,
        graphSnapshotVersion: Int = Self.currentGraphSnapshotVersion,
        results: [SerializableDeadCodeResult]
    ) {
        self.id = id
        self.projectName = projectName
        self.projectPath = projectPath
        self.scheme = scheme
        self.scanTimeDuration = scanTimeDuration
        self.graphSnapshotVersion = graphSnapshotVersion
        self.results = results
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case projectName
        case projectPath
        case scheme
        case scanTimeDuration
        case graphSnapshotVersion
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectName = try container.decode(String.self, forKey: .projectName)
        projectPath = try container.decode(String.self, forKey: .projectPath)
        scheme = try container.decodeIfPresent(String.self, forKey: .scheme)
        scanTimeDuration = try container.decode(TimeInterval.self, forKey: .scanTimeDuration)
        graphSnapshotVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .graphSnapshotVersion
        ) ?? 1
        results = try container.decode([SerializableDeadCodeResult].self, forKey: .results)
    }
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
