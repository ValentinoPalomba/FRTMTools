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

