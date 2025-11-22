import Foundation

struct AnalysisContext {
    let title: String
    let identifier: String?
    let summary: String
}

struct AnalysisContextBuilder {
    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    func buildContext(
        for analysis: any AppAnalysis,
        categories: [CategoryResult],
        tips: [Tip],
        archs: ArchsResult
    ) -> AnalysisContext {
        var sections: [String] = []
        sections.append(metadataSection(for: analysis, archs: archs))
        if let sizeSection = installedSizeSection(for: analysis) {
            sections.append(sizeSection)
        }
        if !categories.isEmpty {
            sections.append(categorySection(categories: categories, totalSize: analysis.totalSize))
            if let frameworksSection = heaviestFrameworkSection(from: categories) {
                sections.append(frameworksSection)
            }
        }
        if !tips.isEmpty {
            sections.append(tipsSection(from: tips))
        }
        if let platformExtras = platformSpecificSection(for: analysis) {
            sections.append(platformExtras)
        }

        let context = sections.joined(separator: "\n\n")
        let identifier: String?
        if let ipa = analysis as? IPAAnalysis {
            identifier = ipa.executableName
        } else if let apk = analysis as? APKAnalysis {
            identifier = apk.packageName ?? apk.appLabel
        } else {
            identifier = nil
        }

        return AnalysisContext(
            title: analysis.fileName,
            identifier: identifier,
            summary: context
        )
    }

    private func metadataSection(for analysis: any AppAnalysis, archs: ArchsResult) -> String {
        var rows: [String] = []
        let uncompressedSize = byteFormatter.string(fromByteCount: analysis.totalSize)
        rows.append("• File: \(analysis.fileName)")
        if let executable = analysis.executableName {
            rows.append("• Executable: \(executable)")
        }
        if let version = analysis.version {
            let build = analysis.buildNumber.map { " (\($0))" } ?? ""
            rows.append("• Version: \(version)\(build)")
        }
        rows.append("• Uncompressed size: \(uncompressedSize)")
        if archs.number > 0 {
            rows.append("• Architectures: \(archs.types.joined(separator: ", "))")
        }
        rows.append("• Allows ATS exceptions: \(analysis.allowsArbitraryLoads ? "Yes" : "No")")
        rows.append("• Binary stripped: \(analysis.isStripped ? "Yes" : "No")")
        return "App overview:\n" + rows.joined(separator: "\n")
    }

    private func installedSizeSection(for analysis: any AppAnalysis) -> String? {
        guard let metrics = analysis.installedSize else { return nil }
        let parts = [
            "total: \(metrics.total) MB",
            "binaries: \(metrics.binaries) MB",
            "frameworks: \(metrics.frameworks) MB",
            "resources: \(metrics.resources) MB"
        ]
        return "Installed size estimation (" + parts.joined(separator: ", ") + ")"
    }

    private func categorySection(categories: [CategoryResult], totalSize: Int64) -> String {
        let totalDouble = max(Double(totalSize), 1)
        let topCategories = categories.prefix(5)
        let rows = topCategories.enumerated().map { index, category in
            let humanSize = byteFormatter.string(fromByteCount: category.totalSize)
            let ratio = Double(category.totalSize) / totalDouble
            let percentage = String(format: "%.1f%%", ratio * 100)
            return "\(index + 1). \(category.name): \(humanSize) (\(percentage))"
        }
        return "Category distribution:\n" + rows.joined(separator: "\n")
    }

    private func tipsSection(from tips: [Tip]) -> String {
        var lines: [String] = []
        let flattened = flatten(tips: tips).prefix(8)
        for entry in flattened {
            lines.append("– \(entry)")
        }
        return "Notable findings:\n" + lines.joined(separator: "\n")
    }

    private func heaviestFrameworkSection(from categories: [CategoryResult]) -> String? {
        guard let frameworksCategory = categories.first(where: { $0.type == .frameworks }) else {
            return nil
        }
        guard let largest = frameworksCategory.items.max(by: { $0.size < $1.size }) else { return nil }
        let size = byteFormatter.string(fromByteCount: largest.size)
        return "Largest framework: \(largest.name) (\(size))"
    }

    private func flatten(tips: [Tip], depth: Int = 0) -> [String] {
        var output: [String] = []
        for tip in tips {
            let prefix = String(repeating: "  ", count: depth)
            output.append(prefix + tip.text)
            if !tip.subTips.isEmpty {
                output.append(contentsOf: flatten(tips: tip.subTips, depth: depth + 1))
            }
        }
        return output
    }

    private func platformSpecificSection(for analysis: any AppAnalysis) -> String? {
        if let ipa = analysis as? IPAAnalysis {
            let urlLastPath = ipa.url.lastPathComponent
            return "Bundle location hint: \(urlLastPath)"
        }

        if let apk = analysis as? APKAnalysis {
            var rows: [String] = []
            if let package = apk.packageName {
                rows.append("• Package: \(package)")
            }
            if let minSDK = apk.minSDK, let targetSDK = apk.targetSDK {
                rows.append("• SDKs: min \(minSDK), target \(targetSDK)")
            }
            if !apk.permissions.isEmpty {
                let permissions = apk.permissions.prefix(8).joined(separator: ", ")
                rows.append("• Declared permissions: \(permissions)")
            }
            if !rows.isEmpty {
                return "Android specifics:\n" + rows.joined(separator: "\n")
            }
        }

        return nil
    }
}
