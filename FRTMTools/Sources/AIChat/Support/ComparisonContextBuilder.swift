import Foundation

struct ComparisonContextBuilder {
    private let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    func buildContext(
        first: any AppAnalysis,
        second: any AppAnalysis,
        result: ComparisonResult,
        firstAnalysisContext: AnalysisContext? = nil,
        secondAnalysisContext: AnalysisContext? = nil,
        firstCategories: [CategoryResult]? = nil,
        secondCategories: [CategoryResult]? = nil
    ) -> AnalysisContext {
        var sections: [String] = []
        sections.append(metadataSection(first: first, second: second))
        sections.append(categorySection(categories: result.categories))
        sections.append(fileDiffSection(result: result))
        if let frameworks = frameworkChangesSection(
            result: result,
            firstCategories: firstCategories,
            secondCategories: secondCategories
        ) {
            sections.append(frameworks)
        }
        if let firstContext = firstAnalysisContext {
            sections.append("Baseline details:\n\(firstContext.summary)")
        }
        if let secondContext = secondAnalysisContext {
            sections.append("Comparison details:\n\(secondContext.summary)")
        }

        let summary = sections.joined(separator: "\n\n")
        let title = "\(first.fileName) vs \(second.fileName)"
        let identifier = first.executableName ?? second.executableName
        return AnalysisContext(title: title, identifier: identifier, summary: summary)
    }

    private func metadataSection(first: any AppAnalysis, second: any AppAnalysis) -> String {
        var lines: [String] = []
        let total1 = formatter.string(fromByteCount: first.totalSize)
        let total2 = formatter.string(fromByteCount: second.totalSize)
        let delta = second.totalSize - first.totalSize
        let deltaSymbol = delta == 0 ? "±" : (delta > 0 ? "➕" : "➖")
        let deltaString = formatter.string(fromByteCount: abs(delta))

        lines.append("Baseline: \(displayName(for: first)) (\(total1))")
        lines.append("Comparison: \(displayName(for: second)) (\(total2))")
        lines.append("Size delta: \(deltaSymbol) \(deltaString)")
        if let version1 = versionString(for: first) {
            lines.append("Version A: \(version1)")
        }
        if let version2 = versionString(for: second) {
            lines.append("Version B: \(version2)")
        }
        return "Comparison overview:\n" + lines.joined(separator: "\n")
    }

    private func categorySection(categories: [ComparisonCategory]) -> String {
        guard !categories.isEmpty else { return "No category data available." }
        let sorted = categories.sorted {
            abs(($0.size2 - $0.size1)) > abs(($1.size2 - $1.size1))
        }
        let top = sorted.prefix(5).map { category -> String in
            let delta = category.size2 - category.size1
            let symbol = delta == 0 ? "±" : (delta > 0 ? "↑" : "↓")
            let signed = formatter.string(fromByteCount: abs(delta))
            return "\(category.name): \(symbol) \(signed) (from \(formatter.string(fromByteCount: category.size1)) to \(formatter.string(fromByteCount: category.size2)))"
        }
        return "Top category deltas:\n" + top.joined(separator: "\n")
    }

    private func fileDiffSection(result: ComparisonResult) -> String {
        var lines: [String] = []
        lines.append("Modified files: \(result.modifiedFiles.count)")
        lines.append("Added files: \(result.addedFiles.count)")
        lines.append("Removed files: \(result.removedFiles.count)")

        let highlights = [
            ("Modified", result.modifiedFiles),
            ("Added", result.addedFiles),
            ("Removed", result.removedFiles)
        ].compactMap { title, diffs -> String? in
            guard let top = diffs.max(by: { abs($0.size2 - $0.size1) < abs($1.size2 - $1.size1) }) else {
                return nil
            }
            return "\(title) highlight: \(describe(diff: top))"
        }

        if !highlights.isEmpty {
            lines.append(contentsOf: highlights)
        }

        return "File changes summary:\n" + lines.joined(separator: "\n")
    }

    private func frameworkChangesSection(
        result: ComparisonResult,
        firstCategories: [CategoryResult]?,
        secondCategories: [CategoryResult]?
    ) -> String? {
        var addedSummaries = summarizeFrameworks(from: result.addedFiles, sizeKeyPath: \.size2)
        var removedSummaries = summarizeFrameworks(from: result.removedFiles, sizeKeyPath: \.size1)

        if let firstCategories, let secondCategories {
            let firstMap = frameworkCategoryMap(from: firstCategories)
            let secondMap = frameworkCategoryMap(from: secondCategories)
            for (name, size) in secondMap where firstMap[name] == nil {
                let current = addedSummaries[name] ?? 0
                addedSummaries[name] = max(current, size)
            }
            for (name, size) in firstMap where secondMap[name] == nil {
                let current = removedSummaries[name] ?? 0
                removedSummaries[name] = max(current, size)
            }
        }

        guard !addedSummaries.isEmpty || !removedSummaries.isEmpty else { return nil }
        var rows: [String] = []
        if !addedSummaries.isEmpty {
            let lines = addedSummaries.sorted(by: { $0.value > $1.value }).map {
                "\($0.key) (\(formatter.string(fromByteCount: $0.value)))"
            }
            rows.append("Added frameworks:\n" + lines.joined(separator: "\n"))
        }
        if !removedSummaries.isEmpty {
            let lines = removedSummaries.sorted(by: { $0.value > $1.value }).map {
                "\($0.key) (\(formatter.string(fromByteCount: $0.value)))"
            }
            rows.append("Removed frameworks:\n" + lines.joined(separator: "\n"))
        }
        return rows.joined(separator: "\n\n")
    }

    private func summarizeFrameworks(
        from diffs: [FileDiff],
        sizeKeyPath: KeyPath<FileDiff, Int64>
    ) -> [String: Int64] {
        var accumulator: [String: Int64] = [:]
        for diff in diffs {
            guard let name = frameworkName(from: diff.name), !name.isEmpty else { continue }
            let size = diff[keyPath: sizeKeyPath]
            let current = accumulator[name] ?? 0
            accumulator[name] = max(current, size)
        }
        return accumulator
    }

    private func frameworkName(from path: String) -> String? {
        let lower = path.lowercased()
        guard let range = lower.range(of: ".framework") else { return nil }
        let end = range.upperBound
        let distance = lower.distance(from: lower.startIndex, to: end)
        let endIndex = path.index(path.startIndex, offsetBy: distance)
        if path.hasSuffix(".framework") {
            return String(path[path.startIndex..<endIndex])
        }
        if let slashIndex = path[path.startIndex..<endIndex].lastIndex(of: "/") {
            return String(path[path.index(after: slashIndex)..<endIndex])
        }
        return String(path[path.startIndex..<endIndex])
    }

    private func frameworkCategoryMap(from categories: [CategoryResult]) -> [String: Int64] {
        guard let frameworks = categories.first(where: { $0.type == .frameworks }) else { return [:] }
        var map: [String: Int64] = [:]
        for item in frameworks.items {
            map[item.name] = item.size
        }
        return map
    }

    private func describe(diff: FileDiff) -> String {
        let change = diff.size2 - diff.size1
        let symbol = change == 0 ? "±" : (change > 0 ? "↑" : "↓")
        let detail: String
        if diff.size1 == 0 {
            detail = "added \(formatter.string(fromByteCount: diff.size2))"
        } else if diff.size2 == 0 {
            detail = "removed \(formatter.string(fromByteCount: diff.size1))"
        } else {
            let before = formatter.string(fromByteCount: diff.size1)
            let after = formatter.string(fromByteCount: diff.size2)
            detail = "from \(before) to \(after)"
        }
        return "\(diff.name): \(symbol) \(detail)"
    }

    private func displayName(for analysis: any AppAnalysis) -> String {
        analysis.executableName ?? analysis.fileName
    }

    private func versionString(for analysis: any AppAnalysis) -> String? {
        guard let version = analysis.version else { return nil }
        if let build = analysis.buildNumber {
            return "\(version) (\(build))"
        }
        return version
    }
}
