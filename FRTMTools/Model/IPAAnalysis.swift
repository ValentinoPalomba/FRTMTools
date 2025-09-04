import Foundation
import AppKit

// MARK: - Models

struct IPAAnalysis: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let rootFile: FileInfo
    let version: String?
    let buildNumber: String?
    private let imageData: Data?
    let isStripped: Bool
    let allowsArbitraryLoads: Bool

    var totalSize: Int64 {
        rootFile.size
    }

    var image: NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
    }

    init(id: UUID = UUID(), fileName: String, rootFile: FileInfo, image: NSImage?, version: String?, buildNumber: String?, isStripped: Bool, allowsArbitraryLoads: Bool) {
        self.id = id
        self.fileName = fileName
        self.rootFile = rootFile
        self.version = version
        self.buildNumber = buildNumber
        self.imageData = image?.tiffRepresentation
        self.isStripped = isStripped
        self.allowsArbitraryLoads = allowsArbitraryLoads
    }
    
    enum CodingKeys: String, CodingKey {
        case id, fileName, rootFile, version, buildNumber, imageData, isStripped, allowsArbitraryLoads
    }
}

struct FileInfo: Identifiable, Codable {
    let id: UUID
    let name: String
    let type: FileType
    let size: Int64
    let subItems: [FileInfo]?

    init(id: UUID = UUID(), name: String, type: FileType, size: Int64, subItems: [FileInfo]? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.size = size
        self.subItems = subItems
    }
}

enum FileType: String, Codable {
    case file
    case directory
    case app
    case framework
    case bundle
    case assets
    case binary
    case plist
    case lproj
}

struct FileDiff: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let size1: Int64
    let size2: Int64
}