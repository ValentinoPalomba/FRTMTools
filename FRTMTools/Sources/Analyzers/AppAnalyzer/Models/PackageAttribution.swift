import Foundation

struct PackageAttribution: Identifiable, Codable, Sendable {
    let id: UUID
    let packageName: String
    let classCount: Int
    let estimatedSizeBytes: Int64
    let sampleClasses: [String]
    let files: [PackageAttributedFile]

    init(
        id: UUID = UUID(),
        packageName: String,
        classCount: Int,
        estimatedSizeBytes: Int64,
        sampleClasses: [String] = [],
        files: [PackageAttributedFile] = []
    ) {
        self.id = id
        self.packageName = packageName
        self.classCount = classCount
        self.estimatedSizeBytes = estimatedSizeBytes
        self.sampleClasses = sampleClasses
        self.files = files
    }
    
    private enum CodingKeys: String, CodingKey {
        case id
        case packageName
        case classCount
        case estimatedSizeBytes
        case sampleClasses
        case files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        packageName = try container.decode(String.self, forKey: .packageName)
        classCount = try container.decode(Int.self, forKey: .classCount)
        estimatedSizeBytes = try container.decode(Int64.self, forKey: .estimatedSizeBytes)
        sampleClasses = try container.decodeIfPresent([String].self, forKey: .sampleClasses) ?? []
        files = try container.decodeIfPresent([PackageAttributedFile].self, forKey: .files) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(packageName, forKey: .packageName)
        try container.encode(classCount, forKey: .classCount)
        try container.encode(estimatedSizeBytes, forKey: .estimatedSizeBytes)
        try container.encode(sampleClasses, forKey: .sampleClasses)
        try container.encode(files, forKey: .files)
    }
}

struct PackageAttributedFile: Identifiable, Codable, Sendable {
    enum FileType: String, Codable, Sendable {
        case classDefinition
        case resource
        case asset
        case native
    }

    let id: UUID
    let name: String
    let originPath: String
    let type: FileType
    let estimatedSizeBytes: Int64

    init(
        id: UUID = UUID(),
        name: String,
        originPath: String,
        type: FileType,
        estimatedSizeBytes: Int64
    ) {
        self.id = id
        self.name = name
        self.originPath = originPath
        self.type = type
        self.estimatedSizeBytes = estimatedSizeBytes
    }
}

extension PackageAttributedFile.FileType {
    var displayName: String {
        switch self {
        case .classDefinition:
            return "Class"
        case .resource:
            return "Resource"
        case .asset:
            return "Asset"
        case .native:
            return "Native"
        }
    }
}
