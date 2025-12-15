import Foundation

final class ComparisonDashboardHTMLBuilder {
    enum PlatformPair {
        case ipa(IPAAnalysis, IPAAnalysis)
        case apk(APKAnalysis, APKAnalysis)

        var label: String {
            switch self {
            case .ipa: return "IPA Comparison"
            case .apk: return "APK Comparison"
            }
        }

        var analyses: (any AppAnalysis, any AppAnalysis) {
            switch self {
            case .ipa(let first, let second):
                return (first, second)
            case .apk(let first, let second):
                return (first, second)
            }
        }
    }

    private let platform: PlatformPair
    private let first: any AppAnalysis
    private let second: any AppAnalysis
    private let comparison: ComparisonResult
    private let byteFormatter: ByteCountFormatter

    init(platform: PlatformPair) {
        self.platform = platform
        let tuple = platform.analyses
        self.first = tuple.0
        self.second = tuple.1
        self.comparison = ComparisonAnalyzer.compare(first: first, second: second)

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        self.byteFormatter = formatter
    }

    func build() -> String {
        let header = renderHeroSection()
        let buildCards = renderBuildCardsSection()
        let categories = renderCategorySection()
        let diffs = renderDiffSection()
        let narrative = renderNarrativeSection()
        let meta = renderMetadataSection()
        let footer = renderFooter()

        let sections = [buildCards, categories, diffs, narrative, meta]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let sectionStack = sections.isEmpty ? "" : """
        <div class="section-stack">
            \(sections)
        </div>
        """

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>FRTMTools • \(first.fileName.htmlEscaped) vs \(second.fileName.htmlEscaped)</title>
            <style>
            \(DashboardHTMLStyle.baseCSS)
            </style>
        </head>
        <body class="dashboard">
            <div class="dashboard-shell">
                \(header)
                <main class="dashboard-main" role="main">
                    \(sectionStack)
                </main>
                \(footer)
            </div>
        </body>
        </html>
        """
    }

    private func renderHeroSection() -> String {
        let beforeSize = formattedBytes(first.totalSize)
        let afterSize = formattedBytes(second.totalSize)
        let change = second.totalSize - first.totalSize
        let delta = formattedDelta(change)
        let changeSummary = "\(comparison.modifiedFiles.count) modified · \(comparison.addedFiles.count) added · \(comparison.removedFiles.count) removed"
        let percent = percentChange(delta: change, base: first.totalSize) ?? ""
        let driftBadge: String
        if change == 0 {
            driftBadge = "badge badge-neutral"
        } else if change > 0 {
            driftBadge = "badge badge-warning"
        } else {
            driftBadge = "badge badge-success"
        }
        let heroBadges = """
        <div class="hero-badges">
            <span class="\(driftBadge)">\(delta.htmlEscaped) (\(percent))</span>
            <span class="badge badge-soft">\(changeSummary.htmlEscaped)</span>
        </div>
        """
        let beforePath = first.url.path
        let afterPath = second.url.path
        let generated = iso8601String()

        return """
        <header class="dashboard-header">
            <div class="header-main">
                <div class="hero-text">
                    <p class="hero-eyebrow">\(platform.label.htmlEscaped)</p>
                    <h1 class="hero-title">\(first.fileName.htmlEscaped) vs \(second.fileName.htmlEscaped)</h1>
                    <p class="hero-subtitle">Tracking footprint drift between two builds.</p>
                    \(heroBadges)
                </div>
            </div>
            <div class="header-meta">
                <dl class="meta-list">
                    <div>
                        <dt>Before</dt>
                        <dd>\(beforeSize.htmlEscaped)</dd>
                    </div>
                    <div>
                        <dt>After</dt>
                        <dd>\(afterSize.htmlEscaped)</dd>
                    </div>
                    <div>
                        <dt>Net Change</dt>
                        <dd class="\(deltaCssClass(change))">\(delta.htmlEscaped) (\(percent))</dd>
                    </div>
                    <div>
                        <dt>File Changes</dt>
                        <dd>\(changeSummary.htmlEscaped)</dd>
                    </div>
                    <div>
                        <dt>Generated</dt>
                        <dd>\(generated)</dd>
                    </div>
                </dl>
                <div class="header-actions">
                    <p class="header-note">Diff created locally with FRTMTools CLI.</p>
                    <p class="hero-source">Before · \(beforePath.htmlEscaped)</p>
                    <p class="hero-source">After · \(afterPath.htmlEscaped)</p>
                </div>
            </div>
        </header>
        """
    }

    private func renderBuildCardsSection() -> String {
        return """
        <section>
            <div class="section-header">
                <div>
                    <p class="section-eyebrow">Build Snapshots</p>
                    <h2>Reference Metadata</h2>
                </div>
                <span>Context for each bundle analyzed in this comparison.</span>
            </div>
            <div class="comparison-grid">
                \(buildCard(for: first, title: "Before Build"))
                \(buildCard(for: second, title: "After Build"))
            </div>
        </section>
        """
    }

    private func buildCard(for analysis: any AppAnalysis, title: String) -> String {
        let version = analysis.version ?? "n/a"
        let build = analysis.buildNumber ?? "n/a"
        let size = formattedBytes(analysis.totalSize)
        return """
        <div class="build-card">
            <h3>\(title.htmlEscaped)</h3>
            <dl>
                <dt>Version</dt><dd>\(version.htmlEscaped)</dd>
                <dt>Build</dt><dd>\(build.htmlEscaped)</dd>
                <dt>Size</dt><dd>\(size.htmlEscaped)</dd>
                <dt>Path</dt><dd>\(analysis.url.path.htmlEscaped)</dd>
            </dl>
        </div>
        """
    }

    private func renderCategorySection() -> String {
        guard !comparison.categories.isEmpty else { return "" }
        let rows = comparison.categories
            .sorted { abs(($0.size2 - $0.size1)) > abs(($1.size2 - $1.size1)) }
            .map { category -> String in
                let delta = category.size2 - category.size1
                return """
                <tr>
                    <td>\(category.name.htmlEscaped)</td>
                    <td class="td-numeric">\(formattedBytes(category.size1))</td>
                    <td class="td-numeric">\(formattedBytes(category.size2))</td>
                    <td class="td-numeric \(deltaCssClass(delta))">\(formattedDelta(delta))</td>
                </tr>
                """
            }
            .joined(separator: "\n")
        return """
        <section class="section">
            <div class="section-header">
                <h2>Category Breakdown</h2>
                <p>How each bundle section changed in size.</p>
            </div>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Category</th>
                            <th class="th-numeric">Before</th>
                            <th class="th-numeric">After</th>
                            <th class="th-numeric">Delta</th>
                        </tr>
                    </thead>
                    <tbody>
                        \(rows)
                    </tbody>
                </table>
            </div>
        </section>
        """
    }

    private func renderDiffSection() -> String {
        let modified = diffColumn(title: "Modified Files", files: comparison.modifiedFiles, emptyState: "No files were modified.")
        let added = diffColumn(title: "Added Files", files: comparison.addedFiles, emptyState: "No files were added.")
        let removed = diffColumn(title: "Removed Files", files: comparison.removedFiles, emptyState: "No files were removed.")
        
        guard !modified.isEmpty || !added.isEmpty || !removed.isEmpty else { return "" }

        return """
        <section class="section">
            <div class="section-header">
                <h2>File-level Differences</h2>
                <p>Largest changes ranked by size impact.</p>
            </div>
            <div class="comparison-grid">
                \(modified)
                \(added)
                \(removed)
            </div>
        </section>
        """
    }

    private func diffColumn(title: String, files: [FileDiff], emptyState: String) -> String {
        let content: String
        if files.isEmpty {
            content = "<div class='empty-state'>\(emptyState.htmlEscaped)</div>"
        } else {
            let rows = files
                .sorted { abs(($0.size2 - $0.size1)) > abs(($1.size2 - $1.size1)) }
                .prefix(15)
                .map { diff -> String in
                    let delta = diff.size2 - diff.size1
                    return """
                    <tr>
                        <td class="td-path">\(diff.name.htmlEscaped)</td>
                        <td class="td-numeric">\(formattedBytes(diff.size1))</td>
                        <td class="td-numeric">\(formattedBytes(diff.size2))</td>
                        <td class="td-numeric \(deltaCssClass(delta))">\(formattedDelta(delta))</td>
                    </tr>
                    """
                }
                .joined(separator: "\n")
            
            content = """
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>File</th>
                            <th class="th-numeric">Before</th>
                            <th class="th-numeric">After</th>
                            <th class="th-numeric">Δ</th>
                        </tr>
                    </thead>
                    <tbody>
                        \(rows)
                    </tbody>
                </table>
            </div>
            """
        }
        
        return """
        <div class="build-card">
             <h3>\(title.htmlEscaped)</h3>
            \(content)
        </div>
        """
    }

    private func renderNarrativeSection() -> String {
        switch platform {
        case .ipa(let firstIPA, let secondIPA):
            let viewModel = ComparisonReportViewModel(first: firstIPA, second: secondIPA, result: comparison)
            let bullets = viewModel.reportItems(for: .english)
            guard !bullets.isEmpty else { return "" }
            let items = bullets.map { "<li>\($0.htmlEscaped)</li>" }.joined(separator: "\n")
            return """
            <section class="section">
                <div class="section-header">
                    <h2>Natural-Language Summary</h2>
                    <p>A narrative summary of the most significant changes.</p>
                </div>
                <ul class="narrative">
                    \(items)
                </ul>
            </section>
            """
        default:
            return ""
        }
    }
    
    private func renderMetadataSection() -> String {
        return "" // This is now part of the build cards
    }
    
    private func renderFooter() -> String {
        return """
        <footer class="dashboard-footer">
            <p>Generated with FRTMTools CLI on \(iso8601String())</p>
        </footer>
        """
    }

    private func formattedBytes(_ value: Int64) -> String {
        return byteFormatter.string(fromByteCount: value)
    }

    private func formattedDelta(_ delta: Int64) -> String {
        if delta == 0 { return "0 B" }
        let prefix = delta > 0 ? "+" : "−"
        let formatted = byteFormatter.string(fromByteCount: abs(delta))
        return "\(prefix)\(formatted)"
    }
    
    private func deltaCssClass(_ delta: Int64) -> String {
        if delta == 0 { return "td-delta neutral" }
        return delta > 0 ? "td-delta positive" : "td-delta negative"
    }

    private func percentChange(delta: Int64, base: Int64) -> String? {
        guard base > 0 else { return nil }
        let pct = (Double(delta) / Double(base)) * 100
        guard pct.isFinite, abs(pct) > 0.01 else { return "0.0%" }
        return String(format: "%+.1f%%", pct)
    }

    private func iso8601String() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}
