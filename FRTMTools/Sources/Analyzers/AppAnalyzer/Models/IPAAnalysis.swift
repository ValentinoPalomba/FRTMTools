import Foundation
import AppKit

// MARK: - Models

struct IPAAnalysis: Identifiable, Codable, Sendable {
    let id: UUID
    let fileName: String
    let executableName: String?
    let url: URL
    let rootFile: FileInfo
    let version: String?
    let buildNumber: String?
    struct InstalledSize: Codable, Sendable {
        let total: Int
        let binaries: Int
        let frameworks: Int
        let resources: Int
    }
    var installedSize: InstalledSize?
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

    init(id: UUID = UUID(), url: URL, fileName: String, executableName: String?, rootFile: FileInfo, image: NSImage?, version: String?, buildNumber: String?, isStripped: Bool, allowsArbitraryLoads: Bool, installedSize: InstalledSize? = nil, dependencyGraph: DependencyGraph? = nil) {
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

extension IPAAnalysis: Exportable {
    func export() throws -> String {
        let header = "Path,Type,Size (Bytes)\n"
        let rows = flatten(file: rootFile).map {
            "\($0.name),\($0.type),\($0.size)"
        }
        return header + rows.joined(separator: "\n")
    }

    private func flatten(file: FileInfo, prefix: String = "") -> [FileInfo] {
        let currentPath = "\(prefix)/\(file.name)"
        var result = [FileInfo(
            name: file.name,
            type: file.type,
            size: file.size
        )]
        
        for child in file.subItems ?? [] {
            result.append(contentsOf: flatten(file: child, prefix: currentPath))
        }
        return result
    }
}
