import Foundation
import AppKit

// MARK: - Models

struct IPAAnalysis: AppAnalysis {
    struct BinaryStrippingInfo: Codable, Sendable {
        let name: String
        let path: String?
        let fullPath: String?
        let size: Int64
        let potentialSaving: Int64
    }

    let id: UUID
    let fileName: String
    let executableName: String?
    let url: URL
    let rootFile: FileInfo
    let version: String?
    let buildNumber: String?
    var installedSize: InstalledSizeMetrics?

    struct StartupTime: Codable, Sendable {
        let averageTime: Double
        let minTime: Double?
        let maxTime: Double?
        let measurements: Int
        let warnings: [String]

        var formattedAverage: String {
            if averageTime < 1.0 {
                return String(format: "%.0f ms", averageTime * 1000)
            }
            return String(format: "%.2f s", averageTime)
        }
    }
    var startupTime: StartupTime?


    private let imageData: Data?
    let isStripped: Bool
    let nonStrippedBinaries: [BinaryStrippingInfo]
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
        nonStrippedBinaries: [BinaryStrippingInfo] = [],
        allowsArbitraryLoads: Bool,
        installedSize: InstalledSizeMetrics? = nil,
        startupTime: StartupTime? = nil,
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
        self.nonStrippedBinaries = nonStrippedBinaries
        self.allowsArbitraryLoads = allowsArbitraryLoads
        self.installedSize = installedSize
        self.startupTime = startupTime
        self.url = url
        self.dependencyGraph = dependencyGraph
    }

    enum CodingKeys: String, CodingKey {
        case id, fileName, executableName, url, rootFile, version, buildNumber, imageData, isStripped, nonStrippedBinaries, allowsArbitraryLoads, installedSize, startupTime, dependencyGraph
    }
}

extension IPAAnalysis: Exportable {}
