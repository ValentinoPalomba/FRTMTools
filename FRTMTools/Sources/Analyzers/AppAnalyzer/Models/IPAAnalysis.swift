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
                let ms = Int((averageTime * 1000).rounded())
                return "\(ms) ms"
            }
            return averageTime.formatted(.number.precision(.fractionLength(2))) + " s"
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.fileName = try container.decode(String.self, forKey: .fileName)
        self.executableName = try container.decodeIfPresent(String.self, forKey: .executableName)
        self.url = try container.decode(URL.self, forKey: .url)
        self.rootFile = try container.decode(FileInfo.self, forKey: .rootFile)
        self.version = try container.decodeIfPresent(String.self, forKey: .version)
        self.buildNumber = try container.decodeIfPresent(String.self, forKey: .buildNumber)
        self.imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        self.isStripped = try container.decode(Bool.self, forKey: .isStripped)
        self.nonStrippedBinaries = try container.decodeIfPresent([BinaryStrippingInfo].self, forKey: .nonStrippedBinaries) ?? []
        self.allowsArbitraryLoads = try container.decode(Bool.self, forKey: .allowsArbitraryLoads)
        self.installedSize = try container.decodeIfPresent(InstalledSizeMetrics.self, forKey: .installedSize)
        self.startupTime = try container.decodeIfPresent(StartupTime.self, forKey: .startupTime)
        self.dependencyGraph = try container.decodeIfPresent(DependencyGraph.self, forKey: .dependencyGraph)
    }
}

extension IPAAnalysis: Exportable {}
