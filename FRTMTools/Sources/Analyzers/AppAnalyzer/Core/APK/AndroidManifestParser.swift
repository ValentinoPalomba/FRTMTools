import Foundation

enum AndroidComponentType: String, Codable, Sendable {
    case activity
    case activityAlias
    case service
    case receiver
    case provider
    
    init?(elementName: String) {
        switch elementName {
        case "activity": self = .activity
        case "activity-alias": self = .activityAlias
        case "service": self = .service
        case "receiver": self = .receiver
        case "provider": self = .provider
        default: return nil
        }
    }
}

struct AndroidIntentData: Codable, Sendable {
    var scheme: String?
    var host: String?
    var port: String?
    var path: String?
    var pathPrefix: String?
    var pathPattern: String?
    var mimeType: String?
}

struct AndroidIntentFilterInfo: Codable, Sendable {
    var actions: [String]
    var categories: [String]
    var data: [AndroidIntentData]
}

struct AndroidComponentInfo: Codable, Sendable {
    let type: AndroidComponentType
    let name: String
    let label: String?
    let exported: Bool?
    let intentFilters: [AndroidIntentFilterInfo]
}

struct AndroidDeepLinkInfo: Codable, Sendable, Identifiable {
    let id = UUID()
    let componentName: String
    let scheme: String?
    let host: String?
    let path: String?
    let mimeType: String?
}

struct AndroidManifestInfo {
    var packageName: String?
    var versionName: String?
    var versionCode: String?
    var appLabel: String?
    var minSDK: String?
    var targetSDK: String?
    var permissions: [String] = []
    var iconResource: String?
    var iconPath: String?
    var nativeCodes: [String] = []
    var launchableActivity: String?
    var launchableActivityLabel: String?
    var supportedLocales: [String] = []
    var supportsScreens: [String] = []
    var densities: [String] = []
    var supportsAnyDensity: Bool?
    var requiredFeatures: [String] = []
    var optionalFeatures: [String] = []
    var components: [AndroidComponentInfo] = []
    var deepLinks: [AndroidDeepLinkInfo] = []
}

private func normalizedComponentName(_ raw: String, packageName: String?) -> String {
    guard !raw.isEmpty else { return raw }
    guard let packageName, !packageName.isEmpty else {
        return raw.hasPrefix(".") ? String(raw.dropFirst()) : raw
    }
    if raw.hasPrefix(".") {
        return packageName + raw
    }
    if !raw.contains(".") {
        return "\(packageName).\(raw)"
    }
    return raw
}

private func parseBooleanAttribute(_ value: String) -> Bool? {
    switch value.lowercased() {
    case "true", "1": return true
    case "false", "0": return false
    default: return nil
    }
}

private func deepLinks(from component: AndroidComponentInfo) -> [AndroidDeepLinkInfo] {
    guard component.type == .activity || component.type == .activityAlias else { return [] }

    func qualifies(_ filter: AndroidIntentFilterInfo) -> Bool {
        guard filter.actions.contains("android.intent.action.VIEW"),
              filter.categories.contains(where: { $0 == "android.intent.category.BROWSABLE" }) else {
            return false
        }
        return true
    }
    
    func resolvedPath(from data: AndroidIntentData) -> String? {
        if let path = data.path { return path }
        if let prefix = data.pathPrefix { return "prefix:\(prefix)" }
        if let pattern = data.pathPattern { return "pattern:\(pattern)" }
        return nil
    }
    
    var links: [AndroidDeepLinkInfo] = []
    for filter in component.intentFilters where qualifies(filter) {
        if filter.data.isEmpty {
            links.append(AndroidDeepLinkInfo(
                componentName: component.name,
                scheme: nil,
                host: nil,
                path: nil,
                mimeType: nil
            ))
        } else {
            for data in filter.data {
                if data.scheme == nil && data.host == nil && data.path == nil && data.pathPrefix == nil && data.pathPattern == nil {
                    continue
                }
                links.append(AndroidDeepLinkInfo(
                    componentName: component.name,
                    scheme: data.scheme,
                    host: data.host,
                    path: resolvedPath(from: data),
                    mimeType: data.mimeType
                ))
            }
        }
    }
    return links
}

enum AndroidManifestParser {
    static func parse(from url: URL) -> AndroidManifestInfo? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        // AXML can sometimes be in a text format, handle that first.
        if let text = String(data: data, encoding: .utf8), text.trimmingCharacters(in: .whitespacesAndNewlines).starts(with: "<") {
            return parseTextManifest(text)
        }

        // Otherwise, parse it as a binary XML file.
        var binaryParser = AndroidBinaryXMLParser(data: data)
        if let info = binaryParser.parse() {
            return info
        }

        var fallbackParser = AndroidStringPoolHeuristicParser(data: data)
        return fallbackParser.parse()
    }

    private static func parseTextManifest(_ text: String) -> AndroidManifestInfo? {
        guard let xmlData = text.data(using: .utf8) else { return nil }
        do {
            let document = try XMLDocument(data: xmlData)
            guard let manifest = document.rootElement() else { return nil }
            var info = AndroidManifestInfo()
            info.packageName = manifest.attribute(forName: "package")?.stringValue
            info.versionCode = manifest.attribute(forName: "android:versionCode")?.stringValue
            info.versionName = manifest.attribute(forName: "android:versionName")?.stringValue
            info.appLabel = manifest.attribute(forName: "android:label")?.stringValue

            if let usesSDK = manifest.elements(forName: "uses-sdk").first {
                info.minSDK = usesSDK.attribute(forName: "android:minSdkVersion")?.stringValue
                info.targetSDK = usesSDK.attribute(forName: "android:targetSdkVersion")?.stringValue
            }

            let permissionElements = manifest.elements(forName: "uses-permission")
            info.permissions = permissionElements.compactMap { $0.attribute(forName: "android:name")?.stringValue }
            
            if let application = manifest.elements(forName: "application").first {
                info.iconResource = application.attribute(forName: "android:icon")?.stringValue
                if let label = application.attribute(forName: "android:label")?.stringValue {
                    info.appLabel = label
                }
                let componentInfos = extractComponents(from: application, packageName: info.packageName)
                info.components.append(contentsOf: componentInfos)
                info.deepLinks.append(contentsOf: componentInfos.flatMap { deepLinks(from: $0) })
            }
            
            return info
        } catch {
            return nil
        }
    }
    
    private static func extractComponents(from application: XMLElement, packageName: String?) -> [AndroidComponentInfo] {
        guard let children = application.children else { return [] }
        var components: [AndroidComponentInfo] = []
        
        for child in children {
            guard let element = child as? XMLElement,
                  let name = element.name,
                  let type = AndroidComponentType(elementName: name) else { continue }
            
            if let component = buildComponent(from: element, type: type, packageName: packageName) {
                components.append(component)
            }
        }
        
        return components
    }
    
    private static func buildComponent(from element: XMLElement, type: AndroidComponentType, packageName: String?) -> AndroidComponentInfo? {
        let rawName = element.attribute(forName: "android:name")?.stringValue ?? element.attribute(forName: "name")?.stringValue ?? ""
        guard !rawName.isEmpty else { return nil }
        let resolvedName = normalizedComponentName(rawName, packageName: packageName)
        let label = element.attribute(forName: "android:label")?.stringValue
        let exportedString = element.attribute(forName: "android:exported")?.stringValue
        let exported = exportedString.flatMap(parseBooleanAttribute)
        let filters = buildIntentFilters(from: element)
        return AndroidComponentInfo(type: type, name: resolvedName, label: label, exported: exported, intentFilters: filters)
    }
    
    private static func buildIntentFilters(from component: XMLElement) -> [AndroidIntentFilterInfo] {
        let filters = component.elements(forName: "intent-filter")
        return filters.compactMap { filterElement in
            var actions: [String] = []
            var categories: [String] = []
            var dataEntries: [AndroidIntentData] = []
            
            for child in filterElement.children ?? [] {
                guard let element = child as? XMLElement, let name = element.name else { continue }
                switch name {
                case "action":
                    if let action = element.attribute(forName: "android:name")?.stringValue ?? element.attribute(forName: "name")?.stringValue {
                        actions.append(action)
                    }
                case "category":
                    if let category = element.attribute(forName: "android:name")?.stringValue ?? element.attribute(forName: "name")?.stringValue {
                        categories.append(category)
                    }
                case "data":
                    var data = AndroidIntentData()
                    data.scheme = element.attribute(forName: "android:scheme")?.stringValue
                    data.host = element.attribute(forName: "android:host")?.stringValue
                    data.port = element.attribute(forName: "android:port")?.stringValue
                    data.path = element.attribute(forName: "android:path")?.stringValue
                    data.pathPrefix = element.attribute(forName: "android:pathPrefix")?.stringValue
                    data.pathPattern = element.attribute(forName: "android:pathPattern")?.stringValue
                    data.mimeType = element.attribute(forName: "android:mimeType")?.stringValue
                    dataEntries.append(data)
                default:
                    continue
                }
            }
            
            return AndroidIntentFilterInfo(actions: actions, categories: categories, data: dataEntries)
        }
    }
}

private struct ComponentBuilder {
    let type: AndroidComponentType
    var rawName: String?
    var label: String?
    var exported: Bool?
    var intentFilters: [AndroidIntentFilterInfo] = []
    
    mutating func apply(attributes: [String: String]) {
        if let name = attributes["android:name"] ?? attributes["name"] {
            rawName = name
        }
        if let labelValue = attributes["android:label"] {
            label = labelValue
        }
        if let exportedValue = attributes["android:exported"], let parsed = parseBooleanAttribute(exportedValue) {
            exported = parsed
        }
    }
    
    mutating func add(filter: AndroidIntentFilterInfo) {
        intentFilters.append(filter)
    }
    
    func build(packageName: String?) -> AndroidComponentInfo? {
        guard let rawName, !rawName.isEmpty else { return nil }
        let resolved = normalizedComponentName(rawName, packageName: packageName)
        return AndroidComponentInfo(type: type, name: resolved, label: label, exported: exported, intentFilters: intentFilters)
    }
}

private struct IntentFilterBuilder {
    var actions: [String] = []
    var categories: [String] = []
    var dataEntries: [AndroidIntentData] = []
    
    mutating func addAction(_ value: String) {
        actions.append(value)
    }
    
    mutating func addCategory(_ value: String) {
        categories.append(value)
    }
    
    mutating func addData(_ data: AndroidIntentData) {
        dataEntries.append(data)
    }
    
    func build() -> AndroidIntentFilterInfo {
        AndroidIntentFilterInfo(actions: actions, categories: categories, data: dataEntries)
    }
}

private struct AndroidBinaryXMLParser {
    // MARK: - Constants
    enum ChunkType: UInt16 {
        case RES_NULL_TYPE = 0x0000
        case RES_STRING_POOL_TYPE = 0x0001
        case RES_TABLE_TYPE = 0x0002
        case RES_XML_TYPE = 0x0003
        case RES_XML_START_NAMESPACE_TYPE = 0x0100
        case RES_XML_END_NAMESPACE_TYPE = 0x0101
        case RES_XML_START_ELEMENT_TYPE = 0x0102
        case RES_XML_END_ELEMENT_TYPE = 0x0103
        case RES_XML_CDATA_TYPE = 0x0104
        case RES_XML_RESOURCE_MAP_TYPE = 0x0180
    }
    
    private enum DataType: UInt8 {
        case TYPE_NULL = 0x00
        case TYPE_REFERENCE = 0x01
        case TYPE_ATTRIBUTE = 0x02
        case TYPE_STRING = 0x03
        case TYPE_FLOAT = 0x04
        case TYPE_DIMENSION = 0x05
        case TYPE_FRACTION = 0x06
        case TYPE_INT_DEC = 0x10
        case TYPE_INT_HEX = 0x11
        case TYPE_INT_BOOLEAN = 0x12
        case TYPE_INT_COLOR_ARGB8 = 0x1c
        case TYPE_INT_COLOR_RGB8 = 0x1d
        case TYPE_INT_COLOR_ARGB4 = 0x1e
        case TYPE_INT_COLOR_RGB4 = 0x1f
    }

    // MARK: - Properties
    private let data: Data
    private var offset: Int = 0
    private var stringPool: [String] = []
    private var resourceMap: [UInt32: String] = [:]
    private var namespaceStack: [(prefix: String, uri: String)] = []
    private var info = AndroidManifestInfo()
    private var componentStack: [ComponentBuilder] = []
    private var intentFilterStack: [IntentFilterBuilder] = []

    init(data: Data) {
        self.data = data
    }

    // MARK: - Main Parsing Logic
    mutating func parse() -> AndroidManifestInfo? {
        // First chunk must be RES_XML_TYPE
        guard let fileHeader = readChunkHeader(), fileHeader.type == .RES_XML_TYPE else { return nil }
        offset += fileHeader.headerSize

        while offset < data.count {
            guard let header = readChunkHeader() else { break }
            let chunkStart = offset
            
            switch header.type {
            case .RES_STRING_POOL_TYPE:
                parseStringPool(header: header)
            case .RES_XML_RESOURCE_MAP_TYPE:
                parseResourceMap(header: header)
            case .RES_XML_START_NAMESPACE_TYPE:
                parseStartNamespace(header: header)
            case .RES_XML_END_NAMESPACE_TYPE:
                parseEndNamespace(header: header)
            case .RES_XML_START_ELEMENT_TYPE:
                parseStartElement(header: header)
            case .RES_XML_END_ELEMENT_TYPE:
                parseEndElement(header: header)
            default:
                break // Ignore other chunk types
            }
            
            offset = chunkStart + header.chunkSize
        }

        // If we couldn't parse the package name, the parsing likely failed.
        guard info.packageName != nil else { return nil }
        return info
    }

    // MARK: - Chunk Parsers
    private mutating func parseStringPool(header: ChunkHeader) {
        let chunkStart = offset
        guard let stringCount = readUInt32(at: chunkStart + 8),
              let styleCount = readUInt32(at: chunkStart + 12),
              let flags = readUInt32(at: chunkStart + 16),
              let stringsStart = readUInt32(at: chunkStart + 20),
              let stylesStart = readUInt32(at: chunkStart + 24)
        else { return }

        let isUTF8 = (flags & 0x00000100) != 0
        let offsetsStart = chunkStart + header.headerSize
        
        var pool: [String] = []
        for i in 0..<Int(stringCount) {
            guard let strOffset = readUInt32(at: offsetsStart + (i * 4)) else { continue }
            let absolute = chunkStart + Int(stringsStart) + Int(strOffset)
            if let string = readString(at: absolute, isUTF8: isUTF8) {
                pool.append(string)
            } else {
                pool.append("")
            }
        }
        stringPool = pool
    }
    
    private mutating func parseResourceMap(header: ChunkHeader) {
        let chunkStart = offset
        let count = (header.chunkSize - header.headerSize) / 4
        for i in 0..<count {
            guard let resId = readUInt32(at: chunkStart + header.headerSize + (i * 4)) else { continue }
            // The resource ID name is its index in the string pool
            resourceMap[resId] = string(at: i)
        }
    }
    
    private mutating func parseStartNamespace(header: ChunkHeader) {
        let chunkStart = offset
        guard let prefixIdx = readInt32(at: chunkStart + 16),
              let uriIdx = readInt32(at: chunkStart + 20)
        else { return }
        
        let prefix = string(at: Int(prefixIdx)) ?? ""
        let uri = string(at: Int(uriIdx)) ?? ""
        namespaceStack.append((prefix, uri))
    }
    
    private mutating func parseEndNamespace(header: ChunkHeader) {
        namespaceStack.popLast()
    }

    private mutating func parseStartElement(header: ChunkHeader) {
        let chunkStart = offset
        guard let nsIdx = readInt32(at: chunkStart + 16),
              let nameIdx = readInt32(at: chunkStart + 20),
              let attributeStart = readUInt16(at: chunkStart + 24),
              let attributeSize = readUInt16(at: chunkStart + 26),
              let attributeCount = readUInt16(at: chunkStart + 28)
        else { return }

        let elementName = string(at: Int(nameIdx))
        let attributesOffset = chunkStart + Int(attributeStart)

        var attributes: [String: String] = [:]
        for i in 0..<Int(attributeCount) {
            let attrOffset = attributesOffset + (i * Int(attributeSize))
            guard let attrNsIdx = readInt32(at: attrOffset),
                  let attrNameIdx = readInt32(at: attrOffset + 4),
                  let rawValueIdx = readInt32(at: attrOffset + 8),
                  let typedValueSize = readUInt16(at: attrOffset + 12),
                  let typedValueDataType = readUInt8(at: attrOffset + 15),
                  let typedValueData = readUInt32(at: attrOffset + 16)
            else { continue }

            let attributeName = string(at: Int(attrNameIdx))
            let value: String? = {
                if typedValueDataType == DataType.TYPE_STRING.rawValue, let rawString = string(at: Int(typedValueData)) {
                    return rawString
                } else {
                    return typedValueToString(type: typedValueDataType, data: typedValueData)
                }
            }()

            let namespace = string(at: Int(attrNsIdx))
            if let qualifiedName = qualify(name: attributeName, namespace: namespace), let value {
                attributes[qualifiedName] = value
                apply(attribute: qualifiedName, value: value, elementName: elementName)
            }
        }
        
        if let elementName {
            handleElementStart(name: elementName, attributes: attributes)
        }
    }

    private mutating func parseEndElement(header: ChunkHeader) {
        let chunkStart = offset
        guard let nameIdx = readInt32(at: chunkStart + 16),
              let elementName = string(at: Int(nameIdx)) else { return }
        handleElementEnd(name: elementName)
    }

    // MARK: - Data Application
    private mutating func apply(attribute name: String?, value: String?, elementName: String?) {
        guard let value, let elementName else { return }

        switch elementName {
        case "manifest":
            if name == "package" { info.packageName = value }
            if name == "android:versionName" { info.versionName = value }
            if name == "android:versionCode" { info.versionCode = value }
            if name == "android:label" { info.appLabel = value }
        case "uses-sdk":
            if name == "android:minSdkVersion" { info.minSDK = value }
            if name == "android:targetSdkVersion" { info.targetSDK = value }
        case "uses-permission":
            if name == "android:name" {
                info.permissions.append(value)
            }
        case "application":
            if name == "android:icon" {
                info.iconResource = value
            }
            if name == "android:label" {
                info.appLabel = value
            }
        default:
            break
        }
    }
    
    private mutating func handleElementStart(name: String, attributes: [String: String]) {
        if let type = AndroidComponentType(elementName: name) {
            var builder = ComponentBuilder(type: type)
            builder.apply(attributes: attributes)
            componentStack.append(builder)
            return
        }
        
        switch name {
        case "intent-filter":
            guard !componentStack.isEmpty else { return }
            intentFilterStack.append(IntentFilterBuilder())
        case "action":
            guard var current = intentFilterStack.popLast(),
                  let action = attributes["android:name"] ?? attributes["name"] else { return }
            current.addAction(action)
            intentFilterStack.append(current)
        case "category":
            guard var current = intentFilterStack.popLast(),
                  let category = attributes["android:name"] ?? attributes["name"] else { return }
            current.addCategory(category)
            intentFilterStack.append(current)
        case "data":
            guard var current = intentFilterStack.popLast() else { return }
            var data = AndroidIntentData()
            data.scheme = attributes["android:scheme"]
            data.host = attributes["android:host"]
            data.port = attributes["android:port"]
            data.path = attributes["android:path"]
            data.pathPrefix = attributes["android:pathPrefix"]
            data.pathPattern = attributes["android:pathPattern"]
            data.mimeType = attributes["android:mimeType"]
            current.addData(data)
            intentFilterStack.append(current)
        default:
            break
        }
    }
    
    private mutating func handleElementEnd(name: String) {
        if name == "intent-filter" {
            guard let filter = intentFilterStack.popLast(),
                  !componentStack.isEmpty else { return }
            let built = filter.build()
            componentStack[componentStack.count - 1].add(filter: built)
            return
        }
        
        if let type = AndroidComponentType(elementName: name) {
            guard let builder = componentStack.popLast(), builder.type == type else { return }
            if let built = builder.build(packageName: info.packageName) {
                info.components.append(built)
                info.deepLinks.append(contentsOf: deepLinks(from: built))
            }
        }
    }

    // MARK: - Helpers
    private func qualify(name: String?, namespace: String?) -> String? {
        guard let name else { return nil }
        guard let namespace, !namespace.isEmpty else { return name }
        
        if let prefix = namespaceStack.first(where: { $0.uri == namespace })?.prefix, !prefix.isEmpty {
            return "\(prefix):\(name)"
        }
        // A common case for AndroidManifest
        if namespace == "http://schemas.android.com/apk/res/android" {
            return "android:\(name)"
        }
        return name
    }
    
    private func string(at index: Int?) -> String? {
        guard let index, index >= 0, index < stringPool.count else { return nil }
        return stringPool[index]
    }

    private func typedValueToString(type: UInt8, data: UInt32) -> String? {
        guard let dataType = DataType(rawValue: type) else {
            return "type_0x\(String(type, radix: 16))_val_0x\(String(data, radix: 16))"
        }
        switch dataType {
        case .TYPE_NULL: return nil
        case .TYPE_INT_DEC: return String(Int32(bitPattern: data))
        case .TYPE_INT_HEX: return "0x\(String(data, radix: 16))"
        case .TYPE_INT_BOOLEAN: return data != 0 ? "true" : "false"
        case .TYPE_STRING: return string(at: Int(data))
        case .TYPE_REFERENCE: return "@\(String(data, radix: 16))"
        case .TYPE_INT_COLOR_ARGB8, .TYPE_INT_COLOR_RGB8, .TYPE_INT_COLOR_ARGB4, .TYPE_INT_COLOR_RGB4:
            return "#\(String(data, radix: 16))"
        case .TYPE_FLOAT: return String(Float(bitPattern: data))
        // TODO: Implement dimension and fraction decoding if needed
        default: return "type_\(dataType)_val_0x\(String(data, radix: 16))"
        }
    }

    // MARK: - Binary Readers
    private func readChunkHeader() -> ChunkHeader? {
        guard let typeRaw = readUInt16(at: offset),
              let type = ChunkType(rawValue: typeRaw),
              let headerSize = readUInt16(at: offset + 2),
              let chunkSize = readUInt32(at: offset + 4)
        else { return nil }
        return ChunkHeader(type: type, headerSize: Int(headerSize), chunkSize: Int(chunkSize))
    }
    
    private func readUInt8(at offset: Int) -> UInt8? {
        guard offset < data.count else { return nil }
        return data[offset]
    }

    private func readUInt16(at offset: Int) -> UInt16? {
        guard offset + 1 < data.count else { return nil }
        return data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self).littleEndian }
    }
    
    private func readInt32(at offset: Int) -> Int32? {
        guard offset + 3 < data.count else { return nil }
        return data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int32.self).littleEndian }
    }

    private func readUInt32(at offset: Int) -> UInt32? {
        guard offset + 3 < data.count else { return nil }
        return data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian }
    }

    private func readString(at position: Int, isUTF8: Bool) -> String? {
        guard position < data.count else { return nil }
        if isUTF8 {
            // UTF-8 strings are encoded with two lengths:
            // 1. The length in UTF-16 characters.
            // 2. The length in bytes.
            let (charLen, charBytes) = readVarint(at: position)
            let (byteLen, byteBytes) = readVarint(at: position + charBytes)
            let start = position + charBytes + byteBytes
            let end = min(start + byteLen, data.count)
            guard start <= end, data[end] == 0x00 else { return nil } // Null-terminated
            let slice = data.subdata(in: start..<end)
            return String(data: slice, encoding: .utf8)
        } else { // UTF-16
            let (len, lenBytes) = readVarint16(at: position)
            let start = position + lenBytes
            let byteLength = len * 2
            let end = min(start + byteLength, data.count)
            guard start <= end, readUInt16(at: end) == 0x0000 else { return nil } // Null-terminated
            let slice = data.subdata(in: start..<end)
            return String(data: slice, encoding: .utf16LittleEndian)
        }
    }
    
    private func readVarint(at position: Int) -> (Int, Int) {
        guard let first = readUInt8(at: position) else { return (0,0) }
        if (first & 0x80) != 0 {
            guard let second = readUInt8(at: position + 1) else { return (0,0) }
            return ((((Int(first) & 0x7F) << 8) | Int(second)), 2)
        } else {
            return (Int(first), 1)
        }
    }
    
    private func readVarint16(at position: Int) -> (Int, Int) {
        guard let first = readUInt16(at: position) else { return (0,0) }
        if (first & 0x8000) != 0 {
            guard let second = readUInt16(at: position + 2) else { return (0,0) }
            return ((((Int(first) & 0x7FFF) << 16) | Int(second)), 4)
        } else {
            return (Int(first), 2)
        }
    }
}

private struct ChunkHeader {
    let type: AndroidBinaryXMLParser.ChunkType
    let headerSize: Int
    let chunkSize: Int
}

// MARK: - Resilient Fallback Parser

private struct AndroidStringPoolHeuristicParser {
    private let data: Data
    private let allowedPackageCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._")
    private let labelExclusions: Set<String> = [
        "name","label","application","activity","service","receiver","provider","release","debug","main",
        "version","sdk","min","max","target","true","false","null","value","config","default","string",
        "layout","drawable","color","dimen","style","array","integer","bool","id","attr","anim","menu",
        "raw","xml","font","navigation","transition"
    ]

    init(data: Data) {
        self.data = data
    }

    mutating func parse() -> AndroidManifestInfo? {
        guard let strings = extractStringPoolStrings(), !strings.isEmpty else {
            return nil
        }

        var info = AndroidManifestInfo()
        var permissionSet: Set<String> = []
        var versionCodeCandidate: String?
        var versionNameCandidate: String?
        var packageCandidates: [String] = []

        for string in strings {
            if looksLikePermission(string) {
                permissionSet.insert(string)
            }

            if looksLikeVersionCode(string) {
                if let existing = versionCodeCandidate,
                   let existingInt = Int(existing),
                   let candidateInt = Int(string),
                   candidateInt > existingInt {
                    versionCodeCandidate = string
                } else if versionCodeCandidate == nil {
                    versionCodeCandidate = string
                }
            }

            if versionNameCandidate == nil, looksLikeVersionName(string) {
                versionNameCandidate = string
            }

            if looksLikePackageCandidate(string) {
                packageCandidates.append(string)
            }
        }

        info.permissions = Array(permissionSet).sorted()
        info.versionCode = versionCodeCandidate
        info.versionName = versionNameCandidate
        info.packageName = bestPackageName(from: packageCandidates, in: strings) ?? packageCandidates.first
        info.minSDK = value(nearKeyword: "minSdkVersion", in: strings)
        info.targetSDK = value(nearKeyword: "targetSdkVersion", in: strings)
        info.appLabel = inferAppLabel(from: strings)

        let hasUsefulData = info.packageName != nil
            || info.versionName != nil
            || info.versionCode != nil
            || info.appLabel != nil
            || !info.permissions.isEmpty
            || info.minSDK != nil
            || info.targetSDK != nil

        return hasUsefulData ? info : nil
    }

    // MARK: - String pool parsing
    private func extractStringPoolStrings() -> [String]? {
        guard data.count >= 8 else { return nil }

        var cursor = 0
        guard let fileType = readUInt16(at: cursor),
              fileType == 0x0003,
              let headerSize = readUInt16(at: cursor + 2),
              readUInt32(at: cursor + 4) != nil
        else { return nil }

        let declaredSize = data.count
        cursor += Int(headerSize)

        while cursor + 8 <= declaredSize {
            guard let chunkType = readUInt16(at: cursor),
                  let chunkHeaderSize = readUInt16(at: cursor + 2),
                  let chunkSize = readUInt32(at: cursor + 4),
                  chunkSize > 0
            else { break }

            if chunkType == 0x0001 {
                return parseStringPool(at: cursor, headerSize: Int(chunkHeaderSize), chunkSize: Int(chunkSize))
            }

            let next = cursor + Int(chunkSize)
            if next <= cursor { break }
            cursor = min(next, declaredSize)
        }

        return nil
    }

    private func parseStringPool(at offset: Int, headerSize: Int, chunkSize: Int) -> [String] {
        guard let stringCount = readUInt32(at: offset + 8),
              let flags = readUInt32(at: offset + 16),
              let stringsStart = readUInt32(at: offset + 20)
        else { return [] }

        let isUTF8 = (flags & 0x00000100) != 0
        let offsetsStart = offset + headerSize
        let chunkLimit = min(offset + Int(chunkSize), data.count)

        var results: [String] = []
        results.reserveCapacity(Int(stringCount))

        for index in 0..<Int(stringCount) {
            let offsetLocation = offsetsStart + (index * 4)
            guard offsetLocation + 3 < chunkLimit,
                  let strOffset = readUInt32(at: offsetLocation)
            else {
                continue
            }
            let absolute = offset + Int(stringsStart) + Int(strOffset)
            if let string = readString(at: absolute, isUTF8: isUTF8, limit: chunkLimit), !string.isEmpty {
                results.append(string)
            }
        }

        return results
    }

    private func readString(at position: Int, isUTF8: Bool, limit: Int) -> String? {
        guard position < limit else { return nil }
        if isUTF8 {
            let (utf16Length, utf16Bytes) = readVarint(at: position)
            guard utf16Bytes > 0, utf16Length >= 0 else { return nil }
            let (byteLength, byteBytes) = readVarint(at: position + utf16Bytes)
            guard byteBytes > 0, byteLength >= 0 else { return nil }
            let start = position + utf16Bytes + byteBytes
            let end = start + byteLength
            guard start < end, end <= limit, end <= data.count else { return nil }
            let slice = data.subdata(in: start..<end)
            return String(data: slice, encoding: .utf8)
        } else {
            let (len, lenBytes) = readVarint16(at: position)
            guard lenBytes > 0, len >= 0 else { return nil }
            let start = position + lenBytes
            let end = start + (len * 2)
            guard start < end, end <= limit, end <= data.count else { return nil }
            let slice = data.subdata(in: start..<end)
            return String(data: slice, encoding: .utf16LittleEndian)
        }
    }

    // MARK: - Heuristics
    private func looksLikePackageCandidate(_ value: String) -> Bool {
        guard value.count >= 3, value.count <= 200 else { return false }
        guard value.contains(".") else { return false }
        let components = value.split(separator: ".")
        guard components.count >= 2 else { return false }
        guard !value.hasPrefix("android.permission.") else { return false }
        guard let first = value.first, first.isLetter || first == "_" else { return false }
        return value.unicodeScalars.allSatisfy { allowedPackageCharacters.contains($0) }
    }

    private func bestPackageName(from candidates: [String], in strings: [String]) -> String? {
        guard !candidates.isEmpty else { return nil }
        let permissionOwners = strings.compactMap(permissionOwner(from:))
        var best: (name: String, score: Int)?

        for candidate in candidates {
            var score = 0
            let prefix = candidate + "."

            for other in strings where other != candidate {
                if other.hasPrefix(prefix) {
                    score += 3
                } else if other.contains(prefix) {
                    score += 1
                }
            }

            for owner in permissionOwners {
                if owner == candidate {
                    score += 6
                } else if owner.hasPrefix(prefix) {
                    score += 2
                }
            }

            if candidate.hasPrefix("android.") {
                score -= 4
            }

            score += candidate.split(separator: ".").count

            if let currentBest = best {
                if score > currentBest.score || (score == currentBest.score && candidate.count > currentBest.name.count) {
                    best = (candidate, score)
                }
            } else {
                best = (candidate, score)
            }
        }

        return best?.name ?? candidates.first
    }

    private func permissionOwner(from permission: String) -> String? {
        guard let range = permission.range(of: ".permission.", options: .caseInsensitive) else {
            return nil
        }
        let owner = String(permission[..<range.lowerBound])
        return looksLikePackageCandidate(owner) ? owner : nil
    }

    private func looksLikeVersionName(_ value: String) -> Bool {
        guard value.count <= 60, (value.contains(".") || value.contains("-")) else { return false }
        guard let first = value.first, first.isNumber else { return false }
        let filtered = value
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
            .replacingOccurrences(of: "rc", with: "")
            .replacingOccurrences(of: "beta", with: "")
            .replacingOccurrences(of: "alpha", with: "")
        return filtered.first?.isNumber == true
    }

    private func looksLikeVersionCode(_ value: String) -> Bool {
        guard value.count >= 3, value.count <= 12 else { return false }
        return value.allSatisfy(\.isNumber)
    }

    private func looksLikePermission(_ value: String) -> Bool {
        if value.hasPrefix("android.permission.") {
            return true
        }
        if let range = value.range(of: ".permission.", options: .caseInsensitive) {
            let suffix = value[range.upperBound...].lowercased()
            return !suffix.hasSuffix("activity") && !suffix.hasSuffix("service") && !suffix.hasSuffix("receiver") && !suffix.hasSuffix("provider")
        }
        return false
    }

    private func inferAppLabel(from strings: [String]) -> String? {
        if let applicationIndex = strings.firstIndex(of: "application") {
            if let local = labelCandidate(around: applicationIndex, in: strings) {
                return local
            }
        }

        if let spaced = strings.first(where: { isLabelCandidate($0, preferSpaces: true) }) {
            return spaced
        }

        return strings.first(where: { isLabelCandidate($0, preferSpaces: false) })
    }

    private func labelCandidate(around index: Int, in strings: [String]) -> String? {
        let lowerBound = max(0, index - 5)
        let upperBound = min(strings.count, index + 25)
        for idx in lowerBound..<upperBound where idx != index {
            let candidate = strings[idx]
            if isLabelCandidate(candidate, preferSpaces: true) {
                return candidate
            }
        }
        return nil
    }

    private func isLabelCandidate(_ value: String, preferSpaces: Bool) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 60 else { return false }
        let lower = trimmed.lowercased()
        if labelExclusions.contains(lower) { return false }
        if trimmed.contains("/") || trimmed.contains("@") { return false }
        if trimmed.hasPrefix("android") || trimmed.hasPrefix("com.") { return false }
        if trimmed.lowercased().hasSuffix(".xml") { return false }
        if trimmed.rangeOfCharacter(from: .decimalDigits) != nil { return false }
        if trimmed.contains(".") && !trimmed.contains(" ") { return false }
        if preferSpaces {
            return trimmed.contains(" ") && trimmed.first?.isUppercase == true
        }
        return trimmed.first?.isUppercase == true
    }

    private func value(nearKeyword keyword: String, in strings: [String]) -> String? {
        guard let index = strings.firstIndex(where: { $0.caseInsensitiveCompare(keyword) == .orderedSame }) else {
            return nil
        }

        let searchRange = (index + 1)..<min(strings.count, index + 6)
        for idx in searchRange {
            let candidate = strings[idx]
            if candidate.allSatisfy(\.isNumber) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Primitive readers
    private func readUInt8(at offset: Int) -> UInt8? {
        guard offset < data.count else { return nil }
        return data[offset]
    }

    private func readUInt16(at offset: Int) -> UInt16? {
        guard offset + 1 < data.count else { return nil }
        return data.withUnsafeBytes { pointer in
            pointer.load(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    private func readUInt32(at offset: Int) -> UInt32? {
        guard offset + 3 < data.count else { return nil }
        return data.withUnsafeBytes { pointer in
            pointer.load(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    private func readVarint(at position: Int) -> (Int, Int) {
        guard let first = readUInt8(at: position) else { return (0, 0) }
        if (first & 0x80) != 0 {
            guard let second = readUInt8(at: position + 1) else { return (0, 0) }
            let value = (Int(first & 0x7F) << 8) | Int(second)
            return (value, 2)
        } else {
            return (Int(first), 1)
        }
    }

    private func readVarint16(at position: Int) -> (Int, Int) {
        guard let first = readUInt16(at: position) else { return (0, 0) }
        if (first & 0x8000) != 0 {
            guard let second = readUInt16(at: position + 2) else { return (0, 0) }
            let value = (Int(first & 0x7FFF) << 16) | Int(second)
            return (value, 4)
        } else {
            return (Int(first), 2)
        }
    }
}
