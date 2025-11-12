import Foundation
import AppKit

// MARK: - Models

struct IPAAnalysis: AppAnalysis {
    let id: UUID
    let fileName: String
    let executableName: String?
    let url: URL
    let rootFile: FileInfo
    let version: String?
    let buildNumber: String?
    var installedSize: InstalledSizeMetrics?
    private let imageData: Data?
    let isStripped: Bool
    let allowsArbitraryLoads: Bool
    var dependencyGraph: DependencyGraph?

    var totalSize: Int64 {
        rootFile.size
    }

    var image: NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
    }

    init(
        id: UUID = UUID(),
        url: URL,
        fileName: String,
        executableName: String?,
        rootFile: FileInfo,
        image: NSImage?,
        version: String?,
        buildNumber: String?,
        isStripped: Bool,
        allowsArbitraryLoads: Bool,
        installedSize: InstalledSizeMetrics? = nil,
        dependencyGraph: DependencyGraph? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.executableName = executableName
        self.rootFile = rootFile
        self.version = version
        self.buildNumber = buildNumber
        self.imageData = image?.tiffRepresentation
        self.isStripped = isStripped
        self.allowsArbitraryLoads = allowsArbitraryLoads
        self.installedSize = installedSize
        self.url = url
        self.dependencyGraph = dependencyGraph
    }
    
    enum CodingKeys: String, CodingKey {
        case id, fileName, executableName, url, rootFile, version, buildNumber, imageData, isStripped, allowsArbitraryLoads, installedSize, dependencyGraph
    }
}

extension IPAAnalysis: Exportable {}
