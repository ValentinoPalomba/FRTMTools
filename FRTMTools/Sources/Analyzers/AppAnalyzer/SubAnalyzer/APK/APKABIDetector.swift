import Foundation

final class APKABIDetector: @unchecked Sendable {
    private let fm = FileManager.default

    func supportedABIs(in layout: AndroidPackageLayout, manifestInfo: AndroidManifestInfo?) -> [String] {
        if let manifestABIs = manifestInfo?.nativeCodes, !manifestABIs.isEmpty {
            return Array(Set(manifestABIs)).sorted()
        }

        var abiSet: Set<String> = []
        guard let enumerator = fm.enumerator(at: layout.rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        for case let directoryURL as URL in enumerator {
            guard directoryURL.lastPathComponent == "lib" else { continue }
            guard let children = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else {
                continue
            }

            for child in children {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else { continue }
                abiSet.insert(child.lastPathComponent)
            }
        }

        return abiSet.sorted()
    }
}
