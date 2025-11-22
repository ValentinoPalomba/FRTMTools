import Foundation
import AppKit

/// Common contract for app package analysis results (IPA, APK, AAB, ...).
protocol AppAnalysis: Identifiable, Codable, Sendable {
    var id: UUID { get }
    var fileName: String { get }
    var executableName: String? { get }
    var url: URL { get }
    var rootFile: FileInfo { get }
    var version: String? { get }
    var buildNumber: String? { get }
    var installedSize: InstalledSizeMetrics? { get set }
    var image: NSImage? { get }
    var totalSize: Int64 { get }
    var isStripped: Bool { get }
    var allowsArbitraryLoads: Bool { get }
    var dependencyGraph: DependencyGraph? { get set }
}

struct InstalledSizeMetrics: Codable {
    let total: Int
    let binaries: Int
    let frameworks: Int
    let resources: Int
}

extension Exportable where Self: AppAnalysis {
    func export() throws -> String {
        let header = "Path,Type,Size (Bytes)\n"
        let rows = rootFile.flattened(includeDirectories: true).map {
            "\($0.name),\($0.type),\($0.size)"
        }
        return header + rows.joined(separator: "\n")
    }
}
