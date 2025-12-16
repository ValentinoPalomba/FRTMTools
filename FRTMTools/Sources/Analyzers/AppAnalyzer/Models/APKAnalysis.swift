import Foundation
import AppKit

enum PlayAssetDeliveryType: String, Codable, Sendable {
    case installTime = "install-time"
    case fastFollow = "fast-follow"
    case onDemand = "on-demand"
    case unknown

    var displayName: String {
        switch self {
        case .installTime: return "Install-time"
        case .fastFollow: return "Fast-follow"
        case .onDemand: return "On-demand"
        case .unknown: return "Unknown"
        }
    }
}

struct PlayAssetPackInfo: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let moduleName: String
    let deliveryType: PlayAssetDeliveryType
    let compressedSizeBytes: Int64

    init(id: UUID = UUID(), name: String, moduleName: String, deliveryType: PlayAssetDeliveryType, compressedSizeBytes: Int64) {
        self.id = id
        self.name = name
        self.moduleName = moduleName
        self.deliveryType = deliveryType
        self.compressedSizeBytes = compressedSizeBytes
    }
}

struct DynamicFeatureFileInfo: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let path: String
    let sizeBytes: Int64

    init(id: UUID = UUID(), name: String, path: String, sizeBytes: Int64) {
        self.id = id
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
    }
}

struct DynamicFeatureInfo: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let moduleName: String
    let deliveryType: PlayAssetDeliveryType
    let estimatedSizeBytes: Int64
    let files: [DynamicFeatureFileInfo]

    init(
        id: UUID = UUID(),
        name: String,
        moduleName: String,
        deliveryType: PlayAssetDeliveryType,
        estimatedSizeBytes: Int64,
        files: [DynamicFeatureFileInfo]
    ) {
        self.id = id
        self.name = name
        self.moduleName = moduleName
        self.deliveryType = deliveryType
        self.estimatedSizeBytes = estimatedSizeBytes
        self.files = files
    }
    
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case moduleName
        case deliveryType
        case estimatedSizeBytes
        case files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        moduleName = try container.decode(String.self, forKey: .moduleName)
        deliveryType = try container.decode(PlayAssetDeliveryType.self, forKey: .deliveryType)
        estimatedSizeBytes = try container.decode(Int64.self, forKey: .estimatedSizeBytes)
        files = try container.decodeIfPresent([DynamicFeatureFileInfo].self, forKey: .files) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(moduleName, forKey: .moduleName)
        try container.encode(deliveryType, forKey: .deliveryType)
        try container.encode(estimatedSizeBytes, forKey: .estimatedSizeBytes)
        try container.encode(files, forKey: .files)
    }
}

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
    let bundletoolInstallSizeBytes: Int64?
    let bundletoolDownloadSizeBytes: Int64?

    let packageName: String?
    let minSDK: String?
    let targetSDK: String?
    let permissions: [String]
    let supportedABIs: [String]
    let signatureInfo: APKSignatureInfo?
    let launchableActivity: String?
    let launchableActivityLabel: String?
    let supportedLocales: [String]
    let supportsScreens: [String]
    let densities: [String]
    let supportsAnyDensity: Bool?
    let requiredFeatures: [String]
    let optionalFeatures: [String]
    let components: [AndroidComponentInfo]
    let deepLinks: [AndroidDeepLinkInfo]
    let thirdPartyLibraries: [ThirdPartyLibraryInsight]
    let playAssetPacks: [PlayAssetPackInfo]
    let dynamicFeatures: [DynamicFeatureInfo]
    let packageAttributions: [PackageAttribution]

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
        bundletoolInstallSizeBytes: Int64? = nil,
        bundletoolDownloadSizeBytes: Int64? = nil,
        dependencyGraph: DependencyGraph? = nil,
        signatureInfo: APKSignatureInfo? = nil,
        launchableActivity: String? = nil,
        launchableActivityLabel: String? = nil,
        supportedLocales: [String] = [],
        supportsScreens: [String] = [],
        densities: [String] = [],
        supportsAnyDensity: Bool? = nil,
        requiredFeatures: [String] = [],
        optionalFeatures: [String] = [],
        components: [AndroidComponentInfo] = [],
        deepLinks: [AndroidDeepLinkInfo] = [],
        thirdPartyLibraries: [ThirdPartyLibraryInsight] = [],
        playAssetPacks: [PlayAssetPackInfo] = [],
        dynamicFeatures: [DynamicFeatureInfo] = [],
        packageAttributions: [PackageAttribution] = []
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
        self.bundletoolInstallSizeBytes = bundletoolInstallSizeBytes
        self.bundletoolDownloadSizeBytes = bundletoolDownloadSizeBytes
        self.url = url
        self.dependencyGraph = dependencyGraph
        self.packageName = packageName
        self.minSDK = minSDK
        self.targetSDK = targetSDK
        self.permissions = permissions
        self.supportedABIs = supportedABIs
        self.signatureInfo = signatureInfo
        self.launchableActivity = launchableActivity
        self.launchableActivityLabel = launchableActivityLabel
        self.supportedLocales = supportedLocales
        self.supportsScreens = supportsScreens
        self.densities = densities
        self.supportsAnyDensity = supportsAnyDensity
        self.requiredFeatures = requiredFeatures
        self.optionalFeatures = optionalFeatures
        self.components = components
        self.deepLinks = deepLinks
        self.thirdPartyLibraries = thirdPartyLibraries
        self.playAssetPacks = playAssetPacks
        self.dynamicFeatures = dynamicFeatures
        self.packageAttributions = packageAttributions
    }
    
    enum CodingKeys: String, CodingKey {
        case id, fileName, executableName, appLabel, url, rootFile, version, buildNumber, installedSize, imageData, isStripped, allowsArbitraryLoads, dependencyGraph, packageName, minSDK, targetSDK, permissions, supportedABIs, signatureInfo, launchableActivity, launchableActivityLabel, supportedLocales, supportsScreens, densities, supportsAnyDensity, requiredFeatures, optionalFeatures, components, deepLinks, thirdPartyLibraries, bundletoolInstallSizeBytes, bundletoolDownloadSizeBytes, playAssetPacks, dynamicFeatures, packageAttributions
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
        bundletoolInstallSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .bundletoolInstallSizeBytes)
        bundletoolDownloadSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .bundletoolDownloadSizeBytes)
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
        launchableActivity = try container.decodeIfPresent(String.self, forKey: .launchableActivity)
        launchableActivityLabel = try container.decodeIfPresent(String.self, forKey: .launchableActivityLabel)
        supportedLocales = try container.decodeIfPresent([String].self, forKey: .supportedLocales) ?? []
        supportsScreens = try container.decodeIfPresent([String].self, forKey: .supportsScreens) ?? []
        densities = try container.decodeIfPresent([String].self, forKey: .densities) ?? []
        supportsAnyDensity = try container.decodeIfPresent(Bool.self, forKey: .supportsAnyDensity)
        requiredFeatures = try container.decodeIfPresent([String].self, forKey: .requiredFeatures) ?? []
        optionalFeatures = try container.decodeIfPresent([String].self, forKey: .optionalFeatures) ?? []
        components = try container.decodeIfPresent([AndroidComponentInfo].self, forKey: .components) ?? []
        deepLinks = try container.decodeIfPresent([AndroidDeepLinkInfo].self, forKey: .deepLinks) ?? []
        thirdPartyLibraries = try container.decodeIfPresent([ThirdPartyLibraryInsight].self, forKey: .thirdPartyLibraries) ?? []
        playAssetPacks = try container.decodeIfPresent([PlayAssetPackInfo].self, forKey: .playAssetPacks) ?? []
        dynamicFeatures = try container.decodeIfPresent([DynamicFeatureInfo].self, forKey: .dynamicFeatures) ?? []
        packageAttributions = try container.decodeIfPresent([PackageAttribution].self, forKey: .packageAttributions) ?? []
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
        try container.encodeIfPresent(bundletoolInstallSizeBytes, forKey: .bundletoolInstallSizeBytes)
        try container.encodeIfPresent(bundletoolDownloadSizeBytes, forKey: .bundletoolDownloadSizeBytes)
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
        try container.encodeIfPresent(launchableActivity, forKey: .launchableActivity)
        try container.encodeIfPresent(launchableActivityLabel, forKey: .launchableActivityLabel)
        try container.encode(supportedLocales, forKey: .supportedLocales)
        try container.encode(supportsScreens, forKey: .supportsScreens)
        try container.encode(densities, forKey: .densities)
        try container.encodeIfPresent(supportsAnyDensity, forKey: .supportsAnyDensity)
        try container.encode(requiredFeatures, forKey: .requiredFeatures)
        try container.encode(optionalFeatures, forKey: .optionalFeatures)
        try container.encode(components, forKey: .components)
        try container.encode(deepLinks, forKey: .deepLinks)
        try container.encode(thirdPartyLibraries, forKey: .thirdPartyLibraries)
        try container.encode(playAssetPacks, forKey: .playAssetPacks)
        try container.encode(dynamicFeatures, forKey: .dynamicFeatures)
        try container.encode(packageAttributions, forKey: .packageAttributions)
    }
}

extension APKAnalysis: Exportable {}
