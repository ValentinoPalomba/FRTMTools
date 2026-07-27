import Foundation

struct SerializableDeadCodeResult: Identifiable, Codable, Sendable {
    enum Remediation: String, Codable, Sendable {
        case deleteDeclaration
        case removeAssignments
        case removeConformance
        case reduceAccessibility

        var title: String {
            switch self {
            case .deleteDeclaration: "Delete declaration"
            case .removeAssignments: "Review assignments"
            case .removeConformance: "Remove conformance"
            case .reduceAccessibility: "Reduce accessibility"
            }
        }

        var systemImage: String {
            switch self {
            case .deleteDeclaration: "trash"
            case .removeAssignments: "arrow.turn.down.right"
            case .removeConformance: "link.badge.minus"
            case .reduceAccessibility: "lock"
            }
        }
    }

    enum FileRemovalSafety: String, Codable, Sendable {
        case safeWholeFile
        case reviewRequired
    }

    let id: UUID
    let kind: String
    let accessibility: String
    let name: String?
    let location: String
    let filePath: String
    let icon: String
    let annotationDescription: String
    let graphID: String
    let usrs: [String]
    let parentGraphID: String?
    let linkedGraphIDs: [String]
    let externalReferenceLocations: [String]
    let remediation: Remediation
    let fileRemovalSafety: FileRemovalSafety

    var requiresOwningDeclarationRemoval: Bool {
        kind == "initializer" ||
            (kind == "function" && name?.hasPrefix("deinit") == true)
    }

    func isStructurallyRemovable(
        within graphIDs: Set<String>
    ) -> Bool {
        guard requiresOwningDeclarationRemoval else { return true }
        guard let parentGraphID else { return false }
        return graphIDs.contains(parentGraphID)
    }

    init(
        id: UUID,
        kind: String,
        accessibility: String,
        name: String?,
        location: String,
        filePath: String,
        icon: String,
        annotationDescription: String,
        graphID: String? = nil,
        usrs: [String] = [],
        parentGraphID: String? = nil,
        linkedGraphIDs: [String] = [],
        externalReferenceLocations: [String] = [],
        remediation: Remediation = .deleteDeclaration,
        fileRemovalSafety: FileRemovalSafety = .reviewRequired
    ) {
        self.id = id
        self.kind = kind
        self.accessibility = accessibility
        self.name = name
        self.location = location
        self.filePath = filePath
        self.icon = icon
        self.annotationDescription = annotationDescription
        self.graphID = graphID ?? id.uuidString
        self.usrs = usrs
        self.parentGraphID = parentGraphID
        self.linkedGraphIDs = linkedGraphIDs
        self.externalReferenceLocations = externalReferenceLocations
        self.remediation = remediation
        self.fileRemovalSafety = fileRemovalSafety
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case accessibility
        case name
        case location
        case filePath
        case icon
        case annotationDescription
        case graphID
        case usrs
        case parentGraphID
        case linkedGraphIDs
        case externalReferenceLocations
        case remediation
        case fileRemovalSafety
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        accessibility = try container.decode(String.self, forKey: .accessibility)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        location = try container.decode(String.self, forKey: .location)
        filePath = try container.decode(String.self, forKey: .filePath)
        icon = try container.decode(String.self, forKey: .icon)
        annotationDescription = try container.decode(String.self, forKey: .annotationDescription)
        graphID = try container.decodeIfPresent(String.self, forKey: .graphID) ?? id.uuidString
        usrs = try container.decodeIfPresent([String].self, forKey: .usrs) ?? []
        parentGraphID = try container.decodeIfPresent(String.self, forKey: .parentGraphID)
        linkedGraphIDs = try container.decodeIfPresent([String].self, forKey: .linkedGraphIDs) ?? []
        externalReferenceLocations = try container.decodeIfPresent(
            [String].self,
            forKey: .externalReferenceLocations
        ) ?? []
        remediation = try container.decodeIfPresent(Remediation.self, forKey: .remediation) ?? .deleteDeclaration
        fileRemovalSafety = try container.decodeIfPresent(FileRemovalSafety.self, forKey: .fileRemovalSafety) ?? .reviewRequired
    }
}
