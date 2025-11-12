import Foundation
import AppKit

struct APKAnalysis: AppAnalysis {
    let id: UUID
    let fileName: String
    let executableName: String?
    let appLabel: String?
    let url: URL
    let rootFile: FileInfo
    let version: String?
    let buildNumber: String?
    var installedSize: InstalledSizeMetrics?
    private let imageData: Data?
    let isStripped: Bool
    let allowsArbitraryLoads: Bool
    var dependencyGraph: DependencyGraph?

    let packageName: String?
    let minSDK: String?
    let targetSDK: String?
    let permissions: [String]
    let supportedABIs: [String]
    let signatureInfo: APKSignatureInfo?

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
        appLabel: String?,
        rootFile: FileInfo,
        image: NSImage?,
        version: String?,
        buildNumber: String?,
        packageName: String?,
        minSDK: String?,
        targetSDK: String?,
        permissions: [String],
        supportedABIs: [String],
        isStripped: Bool,
        allowsArbitraryLoads: Bool,
        installedSize: InstalledSizeMetrics? = nil,
        dependencyGraph: DependencyGraph? = nil,
        signatureInfo: APKSignatureInfo? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.executableName = executableName
        self.appLabel = appLabel
        self.rootFile = rootFile
        self.version = version
        self.buildNumber = buildNumber
        self.imageData = image?.tiffRepresentation
        self.isStripped = isStripped
        self.allowsArbitraryLoads = allowsArbitraryLoads
        self.installedSize = installedSize
        self.url = url
        self.dependencyGraph = dependencyGraph
        self.packageName = packageName
        self.minSDK = minSDK
        self.targetSDK = targetSDK
        self.permissions = permissions
        self.supportedABIs = supportedABIs
        self.signatureInfo = signatureInfo
    }
    
    enum CodingKeys: String, CodingKey {
        case id, fileName, executableName, appLabel, url, rootFile, version, buildNumber, installedSize, imageData, isStripped, allowsArbitraryLoads, dependencyGraph, packageName, minSDK, targetSDK, permissions, supportedABIs, signatureInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        executableName = try container.decodeIfPresent(String.self, forKey: .executableName)
        appLabel = try container.decodeIfPresent(String.self, forKey: .appLabel)
        url = try container.decode(URL.self, forKey: .url)
        rootFile = try container.decode(FileInfo.self, forKey: .rootFile)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        buildNumber = try container.decodeIfPresent(String.self, forKey: .buildNumber)
        installedSize = try container.decodeIfPresent(InstalledSizeMetrics.self, forKey: .installedSize)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        isStripped = try container.decode(Bool.self, forKey: .isStripped)
        allowsArbitraryLoads = try container.decode(Bool.self, forKey: .allowsArbitraryLoads)
        dependencyGraph = try container.decodeIfPresent(DependencyGraph.self, forKey: .dependencyGraph)
        packageName = try container.decodeIfPresent(String.self, forKey: .packageName)
        minSDK = try container.decodeIfPresent(String.self, forKey: .minSDK)
        targetSDK = try container.decodeIfPresent(String.self, forKey: .targetSDK)
        permissions = try container.decodeIfPresent([String].self, forKey: .permissions) ?? []
        supportedABIs = try container.decodeIfPresent([String].self, forKey: .supportedABIs) ?? []
        signatureInfo = try container.decodeIfPresent(APKSignatureInfo.self, forKey: .signatureInfo)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileName, forKey: .fileName)
        try container.encodeIfPresent(executableName, forKey: .executableName)
        try container.encodeIfPresent(appLabel, forKey: .appLabel)
        try container.encode(url, forKey: .url)
        try container.encode(rootFile, forKey: .rootFile)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(buildNumber, forKey: .buildNumber)
        try container.encodeIfPresent(installedSize, forKey: .installedSize)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(isStripped, forKey: .isStripped)
        try container.encode(allowsArbitraryLoads, forKey: .allowsArbitraryLoads)
        try container.encodeIfPresent(dependencyGraph, forKey: .dependencyGraph)
        try container.encodeIfPresent(packageName, forKey: .packageName)
        try container.encodeIfPresent(minSDK, forKey: .minSDK)
        try container.encodeIfPresent(targetSDK, forKey: .targetSDK)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(supportedABIs, forKey: .supportedABIs)
        try container.encodeIfPresent(signatureInfo, forKey: .signatureInfo)
    }
}

extension APKAnalysis: Exportable {}
