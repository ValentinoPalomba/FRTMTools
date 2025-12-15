//
//  AppDashboardHTMLBuilder.swift
//  FRTMToolsCLI
//
//  Created by PALOMBA VALENTINO on 02/12/25.
//

import Foundation
import AppKit

class AppDashboardHTMLBuilder {
    enum Platform {
        case ipa(IPAAnalysis)
        case apk(APKAnalysis)

        var label: String {
            switch self {
            case .ipa: return "IPA Report"
            case .apk: return "APK Report"
            }
        }

        var subtitleLines: [String] {
            switch self {
            case .ipa:
                return []
            case .apk(let apk):
                var lines: [String] = []
                if let appLabel = apk.appLabel, !appLabel.isEmpty {
                    lines.append(appLabel)
                }
                if let package = apk.packageName {
                    lines.append("Package: \(package)")
                }
                return lines
            }
        }

        var apkAnalysis: APKAnalysis? {
            if case .apk(let apk) = self {
                return apk
            }
            return nil
        }
    }

    private let analysis: any AppAnalysis
    private let platform: Platform
    private let categories: [CategoryResult]
    private let byteFormatter: ByteCountFormatter
    private let treemapRoot: TreemapNode
    private let categoryDataset: [CategoryDatum]
    private let tips: [Tip]
    private lazy var duplicateInsightSections: [DuplicateInsightSection] = buildDuplicateInsightSections()
    private lazy var flattenedFiles: [FileInfo] = analysis.rootFile.flattened(includeDirectories: false)
    private lazy var flattenedFilesIncludingDirectories: [FileInfo] = analysis.rootFile.flattened(includeDirectories: true)
    private lazy var fileEntries: [FileEntry] = flattenedFiles.enumerated().map { index, file in
        let path = file.path ?? file.fullPath ?? file.name
        let libraryMatches = librariesForFile(path: path, internalName: file.internalName)
        return FileEntry(
            index: index + 1,
            name: file.name,
            path: path,
            type: file.type.rawValue,
            size: file.size,
            internalName: file.internalName,
            libraries: libraryMatches.isEmpty ? nil : libraryMatches
        )
    }
    private lazy var uniqueFileTypes: [String] = {
        Array(Set(fileEntries.map(\.type))).sorted()
    }()
    private lazy var libraryMatchers: [LibraryMatcher] = {
        guard let libs = platform.apkAnalysis?.thirdPartyLibraries else { return [] }
        return libs.compactMap { library in
            let tokens = normalizedTokens(for: library)
            guard !tokens.isEmpty else { return nil }
            return LibraryMatcher(name: library.name, tokens: tokens)
        }
    }()
    private lazy var libraryNames: [String] = {
        guard let libs = platform.apkAnalysis?.thirdPartyLibraries else { return [] }
        var seen = Set<String>()
        return libs
            .map(\.name)
            .filter { name in
                if seen.contains(name) { return false }
                seen.insert(name)
                return true
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()

    init(platform: Platform) {
        self.platform = platform

        let resolvedAnalysis: any AppAnalysis
        switch platform {
        case .ipa(let ipa):
            resolvedAnalysis = ipa
        case .apk(let apk):
            resolvedAnalysis = apk
        }
        self.analysis = resolvedAnalysis

        let generatedCategories = CategoryGenerator.generateCategories(from: resolvedAnalysis.rootFile)
        self.categories = generatedCategories
        self.categoryDataset = generatedCategories.map { category in
            CategoryDatum(
                id: category.id,
                name: category.name,
                size: category.totalSize,
                percent: resolvedAnalysis.totalSize > 0 ? Double(category.totalSize) / Double(resolvedAnalysis.totalSize) : 0
            )
        }

        self.treemapRoot = TreemapNode(file: resolvedAnalysis.rootFile, depth: 0)

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        self.byteFormatter = formatter
        self.tips = TipGenerator.generateTips(for: resolvedAnalysis)
    }

    func build() -> String {
        let icon = renderIcon()
        let header = renderHeroSection(iconHTML: icon)
        let footer = renderFooter()
        let dataScript = renderDashboardDataScriptTag()
        let clientScripts = renderClientScripts()

        let breakdownSection = renderBreakdownStack()
        let mainContent: String
        if platform.apkAnalysis != nil {
            let insights = renderInsightsSection()
            let dynamicFeatures = renderDynamicFeaturesPanel()
            mainContent = renderAndroidTabContainer(
                breakdownContent: breakdownSection,
                insightsContent: insights,
                dynamicContent: dynamicFeatures
            )
        } else if !tips.isEmpty {
            let insights = renderInsightsSection()
            mainContent = renderTabScaffold(tabs: [
                TabItem(id: "tab-breakdown", label: "Breakdown", content: breakdownSection, emptyMessage: "No breakdown data available."),
                TabItem(id: "tab-insights", label: "Insights", content: insights, emptyMessage: "No insights available for this build.")
            ])
        } else {
            mainContent = breakdownSection
        }

        let contentMarkup = [
            mainContent
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>FRTMTools • \(analysis.fileName.htmlEscaped)</title>
            <style>
            \(DashboardHTMLStyle.baseCSS)
            </style>
        </head>
        <body class="dashboard">
            <div class="dashboard-shell">
                \(header)
                <main class="dashboard-main" role="main">
                    \(contentMarkup)
                </main>
                \(footer)
            </div>
            \(dataScript)
            \(clientScripts)
        </body>
        </html>
        """

    }

    private func renderIcon() -> String {
        if let data = analysis.image?.toData(), data.isEmpty == false {
            let base64 = data.base64EncodedString()
            return """
                <div class="app-icon">
                    <img src="data:image/png;base64,\(base64)" alt="App icon" />
                </div>
            """
        }

        let fallback = analysis.fileName.isEmpty ? "?" : String(analysis.fileName.prefix(1)).uppercased()
        return """
        <div class="fallback-icon">\(fallback.htmlEscaped)</div>
        """
    }

    private func renderHeroSection(iconHTML: String) -> String {
        let heroBadges = [
            renderBadge(title: analysis.isStripped ? "Binary stripped" : "Binary not stripped", type: analysis.isStripped ? .success : .warning),
            renderBadge(title: analysis.allowsArbitraryLoads ? "ATS relaxed" : "ATS enforced", type: analysis.allowsArbitraryLoads ? .warning : .success)
        ].joined(separator: "\n")

        let title = analysis.executableName ?? analysis.fileName
        let versionLine = versionSummaryText() ?? "No version metadata available"
        let sourcePath = analysis.url.path
        let sourceLine = sourcePath.isEmpty ? "" : "<p class=\"hero-source\">Source: \(sourcePath.htmlEscaped)</p>"
        let platformSubtitle = platform.subtitleLines
            .map { "<p class=\"hero-subtitle\">\($0.htmlEscaped)</p>" }
            .joined()
        let actionText = "Analyzed \(fileEntries.count) files · \(formattedBytes(analysis.totalSize)) uncompressed"
        let generated = iso8601String()

        return """
        <header class="dashboard-header">
            <div class="header-main">
                \(iconHTML)
                <div class="hero-text">
                    <p class="hero-eyebrow">\(platform.label.htmlEscaped)</p>
                    <h1 class="hero-title">\(title.htmlEscaped)</h1>
                    <p class="hero-subtitle">Bundle \(analysis.fileName.htmlEscaped) · \(versionLine.htmlEscaped)</p>
                    \(platformSubtitle)
                    <div class="hero-badges">
                        \(heroBadges)
                    </div>
                </div>
            </div>
            <div class="header-meta">
                <dl class="meta-list">
                    <div>
                        <dt>Version</dt>
                        <dd>\((analysis.version ?? "—").htmlEscaped)</dd>
                    </div>
                    <div>
                        <dt>Build</dt>
                        <dd>\((analysis.buildNumber ?? "n/a").htmlEscaped)</dd>
                    </div>
                    <div>
                        <dt>Bundle Size</dt>
                        <dd>\(formattedBytes(analysis.totalSize).htmlEscaped)</dd>
                    </div>
                    <div>
                        <dt>Generated</dt>
                        <dd>\(generated)</dd>
                    </div>
                </dl>
                <div class="header-actions">
                    <p class="header-note">\(actionText.htmlEscaped)</p>
                    <button class="link-button" type="button" onclick="const section=document.getElementById('file-explorer'); if(section){ section.scrollIntoView({behavior: 'smooth', block: 'start'}); }">Jump to explorer</button>
                    \(sourceLine)
                </div>
            </div>
        </header>
        """
    }

    private func renderBreakdownStack() -> String {
        let sections = [
            renderSummaryCards(),
            renderSizeBreakdownSection(),
            renderPlatformDetailsSection(),
            renderAssetPackSection(),
            renderComponentsSection(),
            renderDeepLinksSection(),
            categoryDataset.isEmpty ? "" : renderCategoryVisualizationSection(),
            renderTreemapSection(),
            renderTechnicalInventorySection(),
            renderLibraryExplorerSection(),
            renderFileExplorerSection()
        ].filter { !$0.isEmpty }
        return wrapSectionStack(sections)
    }

    private func renderAndroidTabContainer(breakdownContent: String, insightsContent: String, dynamicContent: String) -> String {
        let tabs = [
            TabItem(id: "tab-breakdown", label: "Breakdown", content: breakdownContent, emptyMessage: "No breakdown data available."),
            TabItem(id: "tab-insights", label: "Insights", content: insightsContent, emptyMessage: "No insights available for this build."),
            TabItem(id: "tab-dynamic", label: "Dynamic Features", content: dynamicContent, emptyMessage: "No dynamic features were detected in this bundle.")
        ]
        return renderTabScaffold(tabs: tabs)
    }

    private func renderInsightsSection() -> String {
        guard !tips.isEmpty else {
            return ""
        }
        let duplicatesMarkup = duplicateInsightSections.isEmpty ? "" : renderDuplicateInsightsPanel(sections: duplicateInsightSections)
        let duplicateKinds: Set<Tip.Kind> = [.duplicateFiles, .duplicateImages]
        let standardTips = tips.filter { tip in
            !duplicateKinds.contains(tip.kind)
        }
        let cards = standardTips.map { tipCard(for: $0) }.joined(separator: "\n")
        let cardsMarkup = cards.isEmpty ? "" : """
            <div class=\"insight-grid\">
                \(cards)
            </div>
        """
        if duplicatesMarkup.isEmpty && cardsMarkup.isEmpty {
            return ""
        }
        let contextDescription: String = platform.apkAnalysis != nil
            ? "Heuristic recommendations generated from the Android bundle contents."
            : "Heuristic recommendations generated from the bundle contents."
        return wrapSectionStack([
        """
        <section class=\"platform-section insights\">
            <div class=\"section-header\">
                <h2>Insights</h2>
                <span>\(contextDescription.htmlEscaped)</span>
            </div>
            \(duplicatesMarkup)
            \(cardsMarkup)
        </section>
        """
        ])
    }

    private func renderDuplicateInsightsPanel(sections: [DuplicateInsightSection]) -> String {
        guard !sections.isEmpty else { return "" }
        let cards = sections.map { duplicateCard(for: $0) }.joined(separator: "\n")
        return """
        <div class=\"duplicate-panel\">
            \(cards)
        </div>
        """
    }

    private func duplicateCard(for section: DuplicateInsightSection) -> String {
        let previewLimit = 5
        let visibleEntries = section.entries.prefix(previewLimit)
        let overflowCount = section.entries.count - visibleEntries.count
        let entryMarkup = visibleEntries.map { duplicateEntryMarkup(for: $0) }.joined(separator: "\n")
        let overflowNote = overflowCount > 0
            ? "<p class=\"duplicate-more\">+\(overflowCount) additional groups are included in the export.</p>"
            : ""
        let exportLink: String
        if section.exportPayload.isEmpty {
            exportLink = ""
        } else {
            exportLink = """
            <a class=\"ghost-button\" href=\"\(section.exportPayload.htmlAttributeEscaped)\" download=\"\(section.exportFileName.htmlAttributeEscaped)\">Export list</a>
            """
        }
        let body: String
        if entryMarkup.isEmpty {
            body = "<p class=\"empty-state\">No duplicate details available.</p>"
        } else {
            body = """
            <ol class=\"duplicate-list\">
                \(entryMarkup)
            </ol>
            \(overflowNote)
            """
        }
        return """
        <article class=\"duplicate-card\">
            <div class=\"duplicate-card-header\">
                <div>
                    <p class=\"duplicate-eyebrow\">\(section.title.htmlEscaped)</p>
                    <h3>\(section.summary.htmlEscaped)</h3>
                </div>
                \(exportLink)
            </div>
            \(body)
        </article>
        """
    }

    private func duplicateEntryMarkup(for entry: DuplicateEntry) -> String {
        let paths = entry.paths.map { path in
            "<li><code>\(path.htmlEscaped)</code></li>"
        }.joined(separator: "\n")
        let pathList = paths.isEmpty ? "" : """
            <ul class=\"duplicate-paths\">
                \(paths)
            </ul>
        """
        return """
        <li class=\"duplicate-entry\">
            <p class=\"duplicate-entry-title\">\(entry.summary.htmlEscaped)</p>
            \(pathList)
        </li>
        """
    }

    private func tipCard(for tip: Tip) -> String {
        let cleanText = tip.text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let text = cleanText.htmlEscaped.replacingOccurrences(of: "\n", with: "<br/>")
        let badge = "<span class=\"insight-category\">\(tip.category.rawValue.htmlEscaped)</span>"
        let subTips = tip.subTips.isEmpty ? "" : """
        <div class="insight-subtips">
            \(tip.subTips.map { "<p>\($0.text.htmlEscaped.replacingOccurrences(of: "\n", with: "<br/>"))</p>" }.joined())
        </div>
        """

        return """
        <article class="insight-card">
            \(badge)
            <div class="insight-text">\(text)</div>
            \(subTips)
        </article>
        """
    }

    private func buildDuplicateInsightSections() -> [DuplicateInsightSection] {
        guard !tips.isEmpty else { return [] }
        let orderedKinds: [Tip.Kind] = [.duplicateFiles, .duplicateImages]
        let baseName = sanitizedReportName()
        var sections: [DuplicateInsightSection] = []
        for kind in orderedKinds {
            guard let tip = tips.first(where: { $0.kind == kind }) else { continue }
            let entries = duplicateEntries(from: tip)
            guard !entries.isEmpty else { continue }
            let suffix = kind == .duplicateFiles ? "duplicate-files" : "duplicate-images"
            let exportFileName = baseName.isEmpty ? "duplicates.txt" : "\(baseName)-\(suffix).txt"
            let exportPayload = exportDataURI(for: entries, heading: tip.text)
            sections.append(DuplicateInsightSection(
                kind: kind,
                title: duplicateTitle(for: kind),
                summary: tip.text,
                entries: entries,
                exportFileName: exportFileName,
                exportPayload: exportPayload
            ))
        }
        return sections
    }

    private func duplicateEntries(from tip: Tip) -> [DuplicateEntry] {
        tip.subTips.compactMap { subTip in
            let lines = subTip.text
                .components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let summary = lines.first else { return nil }
            let paths = Array(lines.dropFirst())
            return DuplicateEntry(summary: summary, paths: paths)
        }
    }

    private func exportDataURI(for entries: [DuplicateEntry], heading: String) -> String {
        var lines: [String] = []
        lines.append("Report: \(analysis.fileName)")
        lines.append(heading)
        lines.append("")
        for entry in entries {
            lines.append(entry.summary)
            for path in entry.paths {
                lines.append(" - \(path)")
            }
            lines.append("")
        }
        let payload = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return "" }
        return "data:text/plain;base64,\(data.base64EncodedString())"
    }

    private func sanitizedReportName() -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let components = analysis.fileName.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        let joined = components.joined(separator: "-")
        if joined.isEmpty {
            return "frtm-report"
        }
        let condensed = joined.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return condensed.lowercased()
    }

    private func duplicateTitle(for kind: Tip.Kind) -> String {
        switch kind {
        case .duplicateFiles:
            return "Duplicate Files"
        case .duplicateImages:
            return "Duplicate Images"
        default:
            return "Duplicates"
        }
    }

    private func renderDynamicFeaturesPanel() -> String {
        guard let apk = platform.apkAnalysis else {
            return ""
        }
        let summary = renderDynamicFeaturesSummarySection(for: apk)
        let fileLists = renderDynamicFeatureFileListsSection(for: apk)
        let sections = [summary, fileLists].filter { !$0.isEmpty }
        if sections.isEmpty {
            return "<section class=\"platform-section\"><div class=\"empty-state\">No dynamic feature modules were bundled.</div></section>"
        }
        return wrapSectionStack(sections)
    }

    private func renderDynamicFeatureFileListsSection(for apk: APKAnalysis) -> String {
        guard !apk.dynamicFeatures.isEmpty else { return "" }
        let cards = apk.dynamicFeatures.map { feature in
            let header = """
            <div class="feature-card-header">
                <div>
                    <div class="name">\(feature.name.htmlEscaped)</div>
                    <div class="meta">Module \(feature.moduleName.htmlEscaped) · \(feature.deliveryType.displayName.htmlEscaped)</div>
                </div>
                <span class="feature-size">\(formattedBytes(feature.estimatedSizeBytes))</span>
            </div>
            """
            let rows: String
            if feature.files.isEmpty {
                rows = "<tr><td colspan=\"2\" class=\"empty-state compact\">File listing not available for this module.</td></tr>"
            } else {
                rows = feature.files.map { file in
                    """
                    <tr>
                        <td>
                            <div class="name">\(file.name.htmlEscaped)</div>
                            <div class="meta">\(file.path.htmlEscaped)</div>
                        </td>
                        <td class="numeric">\(formattedBytes(file.sizeBytes))</td>
                    </tr>
                    """
                }.joined(separator: "\n")
            }

            return """
            <div class="feature-card">
                \(header)
                <div class="table-wrapper compact">
                    <table class="feature-file-table">
                        <thead>
                            <tr>
                                <th>File</th>
                                <th>Size</th>
                            </tr>
                        </thead>
                        <tbody>
                            \(rows)
                        </tbody>
                    </table>
                </div>
            </div>
            """
        }.joined(separator: "\n")

        return """
        <section class="platform-section feature-details">
            <div class="section-header">
                <h2>Module Contents</h2>
                <span>Largest files bundled inside each dynamic feature</span>
            </div>
            <div class="feature-grid">
                \(cards)
            </div>
        </section>
        """
    }

    private func wrapSectionStack(_ sections: [String]) -> String {
        let filtered = sections.filter { !$0.isEmpty }
        guard !filtered.isEmpty else { return "" }
        return """
        <div class="section-stack">
            \(filtered.joined(separator: "\n"))
        </div>
        """
    }

    private func renderTabScaffold(tabs: [TabItem]) -> String {
        let normalized = tabs.map { tab -> (id: String, label: String, content: String) in
            let trimmed = tab.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let content: String
            if trimmed.isEmpty {
                content = wrapSectionStack([
                """
                <section>
                    <div class="empty-state">\(tab.emptyMessage.htmlEscaped)</div>
                </section>
                """
                ])
            } else {
                content = tab.content
            }
            return (id: tab.id, label: tab.label, content: content)
        }
        guard !normalized.isEmpty else { return "" }
        let navButtons = normalized.enumerated().map { index, tab in
            let activeClass = index == 0 ? " active" : ""
            return "<button class=\"tab-button\(activeClass)\" type=\"button\" data-tab-target=\"\(tab.id)\">\(tab.label.htmlEscaped)</button>"
        }.joined(separator: "\n")
        let sections = normalized.enumerated().map { index, tab in
            let activeClass = index == 0 ? " active" : ""
            return """
            <div class="tab-content\(activeClass)" id="\(tab.id)">
                \(tab.content)
            </div>
            """
        }.joined(separator: "\n")
        return """
        <div class="tab-container">
            <div class="tab-nav">
                \(navButtons)
            </div>
            \(sections)
        </div>
        """
    }

    private func renderSummaryCards() -> String {
        var entries: [SummaryCardEntry] = [
            SummaryCardEntry(title: "Uncompressed Size", value: formattedBytes(analysis.totalSize), meta: analysis.fileName, extraClass: nil),
            SummaryCardEntry(title: "Version", value: analysis.version ?? "Not set", meta: "Build \(analysis.buildNumber ?? "n/a")", extraClass: nil),
            SummaryCardEntry(title: "Total Files", value: "\(flattenedFiles.count)", meta: "Includes assets & binaries", extraClass: nil),
            SummaryCardEntry(title: "Generated", value: iso8601String(), meta: "Report created locally", extraClass: nil)
        ]

        var nextInsertIndex = 1
        if let installEntry = installedSizeSummaryEntry() {
            entries.insert(installEntry, at: nextInsertIndex)
            nextInsertIndex += 1
        }
        if let downloadEntry = downloadSizeSummaryEntry() {
            entries.insert(downloadEntry, at: nextInsertIndex)
            nextInsertIndex += 1
        }

        let cards = entries.map { entry in
            let extraClass = entry.extraClass.map { " \($0)" } ?? ""
            return """
            <article class="kpi\(extraClass)">
                <p class="kpi-label">\(entry.title.htmlEscaped)</p>
                <p class="kpi-value">\(entry.value.htmlEscaped)</p>
                <p class="kpi-meta">\(entry.meta.htmlEscaped)</p>
            </article>
            """
        }.joined(separator: "\n")

        return """
        <section class="kpi-section">
            <div class="section-header">
                <div>
                    <p class="section-eyebrow">Summary</p>
                    <h2>Build Snapshot</h2>
                </div>
                <span>Key metadata for this build</span>
            </div>
            <div class="kpi-strip">
                \(cards)
            </div>
        </section>
        """
    }

    private func renderTechnicalInventorySection() -> String {
        let cards = [
            localizationInventoryCard(),
            densityInventoryCard(),
            permissionsInventoryCard(),
            featuresInventoryCard(),
            librariesInventoryCard(),
            packagesInventoryCard()
        ].compactMap { $0 }
        guard !cards.isEmpty else { return "" }

        let grid = cards.map { card in
            """
            <div class="inventory-card">
                <div class="inventory-card-header">
                    <h3>\(card.title.htmlEscaped)</h3>
                    \(card.subtitle.map { "<span>\($0.htmlEscaped)</span>" } ?? "")
                </div>
                \(card.body)
            </div>
            """
        }.joined(separator: "\n")

        return """
        <section class="inventory-section" id="technical-inventory">
            <div class="section-header">
                <h2>Technical Inventory</h2>
                <span>Locales, density support, permissions & dependencies</span>
            </div>
            <div class="inventory-grid">
                \(grid)
            </div>
        </section>
        """
    }

    private func renderLibraryExplorerSection() -> String {
        guard case .apk(let apk) = platform, !apk.thirdPartyLibraries.isEmpty else { return "" }
        let total = apk.thirdPartyLibraries.count
        let rows = apk.thirdPartyLibraries.enumerated().map { index, library in
            let packages = library.packageMatches.joined(separator: ", ")
            let manifestClass = library.hasManifestComponent ? "manifest-pill yes" : "manifest-pill"
            let manifestLabel = library.hasManifestComponent ? "Manifest" : "—"
            let packagesMeta = packages.isEmpty ? "" : "<div class=\"meta\">Packages: \(packages.htmlEscaped)</div>"
            let haystack = "\(library.name) \(library.identifier) \(packages)".lowercased()
            return """
            <tr data-haystack="\(haystack.htmlAttributeEscaped)" data-manifest="\(library.hasManifestComponent)" data-index="\(index + 1)">
                <td>
                    <div class="name">\(library.name.htmlEscaped)</div>
                    <div class="meta">ID: \(library.identifier.htmlEscaped)</div>
                    \(packagesMeta)
                </td>
                <td>\((library.version ?? "—").htmlEscaped)</td>
                <td>\(formattedBytes(library.estimatedSize))</td>
                <td><span class="\(manifestClass)">\(manifestLabel)</span></td>
            </tr>
            """
        }.joined(separator: "\n")

        return """
        <section id="library-explorer">
            <div class="section-header">
                <h2>Third-Party Library Explorer</h2>
                <span>Search \(total) detected SDKs</span>
            </div>
            <div class="section-controls">
                <div class="search-group">
                    <input type="search" id="librarySearch" placeholder="Search name, identifier or package…" autocomplete="off" />
                    <span class="search-hint">⌘F</span>
                </div>
                <label class="filter-toggle">
                    <input type="checkbox" id="libraryManifestFilter" />
                    <span>Manifest components only</span>
                </label>
            </div>
            <div class="table-wrapper interactive">
                <table>
                    <thead>
                        <tr>
                            <th>Library</th>
                            <th>Version</th>
                            <th>Size</th>
                            <th>Manifest</th>
                        </tr>
                    </thead>
                    <tbody id="libraryTableBody">
                        \(rows)
                    </tbody>
                </table>
            </div>
            <div class="search-status" id="librarySearchStatus">Showing \(total) SDKs</div>
        </section>
        """
    }

    private func localizationInventoryCard() -> InventoryCard? {
        switch platform {
        case .ipa:
            let stats = iosLocalizationStats()
            guard !stats.isEmpty else { return nil }
            let limit = 12
            let rows = stats.prefix(limit).map { entry in
                """
                <tr>
                    <td>\(entry.code.uppercased().htmlEscaped)</td>
                    <td>\(formattedBytes(entry.size))</td>
                </tr>
                """
            }.joined(separator: "\n")
            let remainder = stats.count > limit ? "<div class=\"meta\">+\(stats.count - limit) more locales</div>" : ""
            let body = """
            <div class="table-wrapper compact">
                <table>
                    <thead>
                        <tr>
                            <th>Locale</th>
                            <th>Size</th>
                        </tr>
                    </thead>
                    <tbody>
                        \(rows)
                    </tbody>
                </table>
            </div>
            \(remainder)
            """
            return InventoryCard(
                title: "Localized Resources",
                subtitle: "\(stats.count) locales",
                body: body
            )
        case .apk(let apk):
            guard !apk.supportedLocales.isEmpty else { return nil }
            let tags = renderTagListSection(title: "", items: apk.supportedLocales, limit: 40)
            return InventoryCard(
                title: "Supported Locales",
                subtitle: "\(apk.supportedLocales.count) locales",
                body: tags
            )
        }
    }

    private func densityInventoryCard() -> InventoryCard? {
        guard case .apk(let apk) = platform else { return nil }
        let hasScreens = !apk.supportsScreens.isEmpty
        let hasDensities = !apk.densities.isEmpty
        let hasAnyDensity = apk.supportsAnyDensity ?? false
        guard hasScreens || hasDensities || hasAnyDensity else { return nil }

        var parts: [String] = []
        if hasScreens {
            parts.append(renderTagListSection(title: "Screens", items: apk.supportsScreens, limit: 12))
        }
        if hasDensities {
            parts.append(renderTagListSection(title: "Densities", items: apk.densities, limit: 20))
        }
        if hasAnyDensity {
            parts.append("<div class=\"meta\">Supports any density</div>")
        }

        return InventoryCard(
            title: "Screen & Density Support",
            subtitle: "Manifest declarations",
            body: parts.joined(separator: "\n")
        )
    }

    private func permissionsInventoryCard() -> InventoryCard? {
        guard case .apk(let apk) = platform, !apk.permissions.isEmpty else { return nil }
        let tags = renderTagListSection(title: "", items: apk.permissions, limit: 50)
        return InventoryCard(
            title: "Permissions",
            subtitle: "\(apk.permissions.count) declared",
            body: tags
        )
    }

    private func featuresInventoryCard() -> InventoryCard? {
        guard case .apk(let apk) = platform,
              !apk.requiredFeatures.isEmpty || !apk.optionalFeatures.isEmpty else { return nil }
        var parts: [String] = []
        if !apk.requiredFeatures.isEmpty {
            parts.append(renderTagListSection(title: "Required", items: apk.requiredFeatures, limit: 40))
        }
        if !apk.optionalFeatures.isEmpty {
            parts.append(renderTagListSection(title: "Optional", items: apk.optionalFeatures, limit: 40))
        }
        return InventoryCard(
            title: "Hardware & Software Features",
            subtitle: nil,
            body: parts.joined(separator: "\n")
        )
    }

    private func librariesInventoryCard() -> InventoryCard? {
        guard case .apk(let apk) = platform, !apk.thirdPartyLibraries.isEmpty else { return nil }
        let limit = min(10, apk.thirdPartyLibraries.count)
        let rows = apk.thirdPartyLibraries.prefix(limit).map { library in
            """
            <tr>
                <td>\(library.name.htmlEscaped)</td>
                <td>\(library.identifier.htmlEscaped)</td>
                <td>\((library.version ?? "—").htmlEscaped)</td>
                <td>\(formattedBytes(library.estimatedSize))</td>
            </tr>
            """
        }.joined(separator: "\n")
        let remainder = apk.thirdPartyLibraries.count > limit ? "<div class=\"meta\">+\(apk.thirdPartyLibraries.count - limit) more detected</div>" : ""

        let body = """
        <div class="table-wrapper compact">
            <table class="feature-file-table">
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>ID</th>
                        <th>Version</th>
                        <th>Size</th>
                    </tr>
                </thead>
                <tbody>
                    \(rows)
                </tbody>
            </table>
        </div>
        \(remainder)
        """

        return InventoryCard(
            title: "Third-Party Libraries",
            subtitle: "\(apk.thirdPartyLibraries.count) packages",
            body: body
        )
    }

    private func packagesInventoryCard() -> InventoryCard? {
        guard case .apk(let apk) = platform, !apk.packageAttributions.isEmpty else { return nil }
        let limit = min(10, apk.packageAttributions.count)
        let rows = apk.packageAttributions.prefix(limit).map { attribution in
            """
            <tr>
                <td>\(attribution.packageName.htmlEscaped)</td>
                <td>\(attribution.classCount)</td>
                <td>\(formattedBytes(attribution.estimatedSizeBytes))</td>
            </tr>
            """
        }.joined(separator: "\n")
        let remainder = apk.packageAttributions.count > limit ? "<div class=\"meta\">+\(apk.packageAttributions.count - limit) more packages</div>" : ""

        let body = """
        <div class="table-wrapper compact">
            <table class="feature-file-table">
                <thead>
                    <tr>
                        <th>Package</th>
                        <th>Classes</th>
                        <th>Estimated Size</th>
                    </tr>
                </thead>
                <tbody>
                    \(rows)
                </tbody>
            </table>
        </div>
        \(remainder)
        """

        return InventoryCard(
            title: "Package Attribution",
            subtitle: "\(apk.packageAttributions.count) tracked",
            body: body
        )
    }


    private func installedSizeSummaryEntry() -> SummaryCardEntry? {
        guard let metrics = resolvedInstalledSizeMetrics else { return nil }
        var meta = "Estimated footprint after install"
        if let apk = platform.apkAnalysis, apk.bundletoolInstallSizeBytes != nil {
            meta = "bundletool install estimate"
        }
        let title = platform.apkAnalysis == nil ? "Installed Size" : "Install Size"
        return SummaryCardEntry(title: title, value: formatMegabytes(metrics.total), meta: meta, extraClass: nil)
    }

    private func downloadSizeSummaryEntry() -> SummaryCardEntry? {
        guard let apk = platform.apkAnalysis,
              let downloadBytes = apk.bundletoolDownloadSizeBytes else { return nil }

        let value = formattedBytes(downloadBytes)
        let meta: String
        if let installBytes = apk.bundletoolInstallSizeBytes {
            meta = "Install \(formattedBytes(installBytes))"
        } else {
            meta = "bundletool download estimate"
        }

        let downloadMegabytes = Double(downloadBytes) / 1_048_576.0
        var extraClass: String? = nil
        if downloadMegabytes >= 200 {
            extraClass = "card-danger"
        } else if downloadMegabytes >= 180 {
            extraClass = "card-warning"
        }

        return SummaryCardEntry(title: "Download Size", value: value, meta: meta, extraClass: extraClass)
    }

    private func renderPlatformDetailsSection() -> String {
        switch platform {
        case .ipa(let ipa):
            return renderIOSDetailsSection(ipa)
        case .apk(let apk):
            return renderAndroidDetailsSection(apk)
        }
    }

    private func renderIOSDetailsSection(_ ipa: IPAAnalysis) -> String {
        struct DetailCardView {
            let title: String
            let value: String
            let meta: String?
        }

        var cards: [DetailCardView] = []

        let binarySize = flattenedFiles
            .filter { $0.type == .binary }
            .reduce(Int64(0)) { $0 + $1.size }
        if binarySize > 0 {
            cards.append(DetailCardView(
                title: "Main Binary",
                value: formattedBytes(binarySize),
                meta: ipa.isStripped ? "Stripped" : "Debug Symbols"
            ))
        }

        if let frameworksCategory = categories.first(where: { $0.type == .frameworks }) {
            let size = frameworksCategory.items.reduce(Int64(0)) { $0 + $1.size }
            cards.append(DetailCardView(
                title: "Embedded Frameworks",
                value: "\(frameworksCategory.items.count) · \(formattedBytes(size))",
                meta: "Frameworks folder"
            ))
        }

        if let bundlesCategory = categories.first(where: { $0.type == .bundles }) {
            let size = bundlesCategory.items.reduce(Int64(0)) { $0 + $1.size }
            cards.append(DetailCardView(
                title: "Bundles",
                value: "\(bundlesCategory.items.count) · \(formattedBytes(size))",
                meta: "Additional resource bundles"
            ))
        }

        cards.append(DetailCardView(
            title: "App Transport Security",
            value: analysis.allowsArbitraryLoads ? "Relaxed" : "Default",
            meta: analysis.allowsArbitraryLoads ? "NSAllowsArbitraryLoads enabled" : "ATS enforced"
        ))

        let cardHTML = cards.isEmpty ? "" : """
        <div class="detail-grid">
            \(cards.map { card in
                """
                <div class="detail-card">
                    <h3>\(card.title.htmlEscaped)</h3>
                    <div class="value">\(card.value.htmlEscaped)</div>
                    \(card.meta.map { "<div class=\"meta\">\($0.htmlEscaped)</div>" } ?? "")
                </div>
                """
            }.joined(separator: "\n"))
        </div>
        """

        guard !cardHTML.isEmpty else { return "" }

        return """
        <section class="platform-section">
            <div class="section-header">
                <h2>iOS App Details</h2>
                <span>Binary, frameworks and ATS configuration</span>
            </div>
            \(cardHTML)
        </section>
        """
    }

    private func renderAndroidDetailsSection(_ apk: APKAnalysis) -> String {
        struct DetailCardView {
            let title: String
            let value: String
            let meta: String?
        }

        var cards: [DetailCardView] = []
        if let installCard = androidInstallSizeCard(for: apk) {
            cards.append(installCard)
        }
        if let package = apk.packageName {
            cards.append(DetailCardView(title: "Package", value: package, meta: nil))
        }
        if let minSDK = apk.minSDK {
            cards.append(DetailCardView(title: "Min SDK", value: minSDK, meta: nil))
        }
        if let targetSDK = apk.targetSDK {
            cards.append(DetailCardView(title: "Target SDK", value: targetSDK, meta: nil))
        }
        if !apk.supportedABIs.isEmpty {
            cards.append(DetailCardView(title: "Supported ABIs", value: apk.supportedABIs.joined(separator: ", "), meta: nil))
        }
        if let signature = apk.signatureInfo {
            let primary = signature.certificates.first
            let signer = primary?.commonName ?? primary?.subject ?? "Unknown certificate"
            var metaParts: [String] = []
            if signature.isDebugSigned {
                metaParts.append("Debug Signed")
            }
            if !signature.signatureSchemes.isEmpty {
                metaParts.append(signature.signatureSchemesDescription)
            }
            cards.append(DetailCardView(title: "Signature", value: signer, meta: metaParts.isEmpty ? nil : metaParts.joined(separator: " · ")))
        }
        if let activity = apk.launchableActivity {
            cards.append(DetailCardView(title: "Launch Activity", value: activity, meta: apk.launchableActivityLabel))
        }

        let cardHTML = cards.isEmpty ? "" : """
        <div class="detail-grid">
            \(cards.map { card in
                """
                <div class="detail-card">
                    <h3>\(card.title.htmlEscaped)</h3>
                    <div class="value">\(card.value.htmlEscaped)</div>
                    \(card.meta.map { "<div class=\"meta\">\($0.htmlEscaped)</div>" } ?? "")
                </div>
                """
            }.joined(separator: "\n"))
        </div>
        """

        guard !cardHTML.isEmpty else { return "" }

        return """
        <section class="platform-section">
            <div class="section-header">
                <h2>Android App Details</h2>
                <span>Manifest metadata and capabilities</span>
            </div>
            \(cardHTML)
        </section>
        """

        func androidInstallSizeCard(for apk: APKAnalysis) -> DetailCardView? {
            if let installBytes = apk.bundletoolInstallSizeBytes {
                let meta = apk.bundletoolDownloadSizeBytes.map { "Download \(formattedBytes($0))" } ?? "bundletool universal APK"
                return DetailCardView(
                    title: "Install Size",
                    value: formattedBytes(installBytes),
                    meta: meta
                )
            } else if let metrics = apk.installedSize {
                return DetailCardView(
                    title: "Install Size",
                    value: formatMegabytes(metrics.total),
                    meta: "Estimated from archive"
                )
            }
            return nil
        }
    }

    private func renderAssetPackSection() -> String {
        guard let apk = platform.apkAnalysis, !apk.playAssetPacks.isEmpty else { return "" }
        let rows = apk.playAssetPacks.map { pack in
            """
            <tr>
                <td>
                    <div class="name">\(pack.name.htmlEscaped)</div>
                    <div class="meta">\(pack.deliveryType.displayName.htmlEscaped)</div>
                </td>
                <td class="numeric">\(formattedBytes(pack.compressedSizeBytes))</td>
            </tr>
            """
        }.joined(separator: "\n")

        return """
        <section class="platform-section">
            <div class="section-header">
                <h2>Play Asset Delivery</h2>
                <span>\(apk.playAssetPacks.count) asset pack\(apk.playAssetPacks.count == 1 ? "" : "s") detected</span>
            </div>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Pack</th>
                            <th>Compressed Size</th>
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

    private func renderDynamicFeaturesSummarySection(for analysis: APKAnalysis? = nil) -> String {
        let target = analysis ?? platform.apkAnalysis
        guard let apk = target, !apk.dynamicFeatures.isEmpty else { return "" }
        let rows = apk.dynamicFeatures.map { feature in
            """
            <tr>
                <td>
                    <div class="name">\(feature.name.htmlEscaped)</div>
                    <div class="meta">\(feature.deliveryType.displayName.htmlEscaped)</div>
                </td>
                <td class="numeric">\(formattedBytes(feature.estimatedSizeBytes))</td>
            </tr>
            """
        }.joined(separator: "\n")

        return """
        <section class="platform-section">
            <div class="section-header">
                <h2>Dynamic Feature Modules</h2>
                <span>\(apk.dynamicFeatures.count) module\(apk.dynamicFeatures.count == 1 ? "" : "s") detected</span>
            </div>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Module</th>
                            <th>Estimated Size</th>
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

    private func renderTagListSection(title: String, items: [String], limit: Int = 12) -> String {
        var seen = Set<String>()
        var uniqueItems: [String] = []
        for item in items {
            if !seen.contains(item) {
                seen.insert(item)
                uniqueItems.append(item)
            }
        }
        guard !uniqueItems.isEmpty else { return "" }
        let visible = Array(uniqueItems.prefix(limit))
        let remainder = uniqueItems.count - visible.count
        let tags = visible.map { "<li class=\"tag\">\($0.htmlEscaped)</li>" }.joined()
        let footer = remainder > 0 ? "<div class=\"meta\">+\(remainder) more</div>" : ""
        let heading = title.isEmpty ? "" : "<h3>\(title.htmlEscaped)</h3>"
        return """
        <div class="tag-section">
            \(heading)
            <ul class="tag-list">\(tags)</ul>
            \(footer)
        </div>
        """
    }

    private func renderSizeBreakdownSection() -> String {
        guard let metrics = resolvedInstalledSizeMetrics else { return "" }
        let rows: [(label: String, value: Int)] = [
            ("Binaries", metrics.binaries),
            ("Frameworks / Native libs", metrics.frameworks),
            ("Resources", metrics.resources)
        ].filter { $0.value > 0 || metrics.total > 0 }
        guard !rows.isEmpty else { return "" }
        let rawSum = rows.reduce(0) { $0 + $1.value }
        let total = max(rawSum > 0 ? rawSum : metrics.total, 1)
        let tableRows = rows.map { row in
            let percentage = Double(row.value) / Double(total) * 100
            return """
            <tr>
                <td>\(row.label.htmlEscaped)</td>
                <td>\(formatMegabytes(row.value))</td>
                <td>\(String(format: "%.1f%%", percentage))</td>
            </tr>
            """
        }.joined(separator: "\n")

        return """
        <section class="platform-section">
            <div class="section-header">
                <h2>Install Size Breakdown</h2>
                <span>Estimated footprint after installation</span>
            </div>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Category</th>
                            <th>Size</th>
                            <th>Share</th>
                        </tr>
                    </thead>
                    <tbody>
                        \(tableRows)
                    </tbody>
                </table>
            </div>
        </section>
        """
    }


    private func renderComponentsSection() -> String {
        guard case .apk(let apk) = platform, !apk.components.isEmpty else { return "" }
        let grouped = Dictionary(grouping: apk.components, by: { $0.type })
        let rows = grouped
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { type, components -> String in
                let exportedCount = components.filter { $0.exported == true }.count
                let exportSummary = exportedCount > 0 ? "\(exportedCount) exported" : "Not exported"
                return """
                <tr>
                    <td>\(displayName(for: type).htmlEscaped)</td>
                    <td>\(components.count)</td>
                    <td>\(exportSummary)</td>
                </tr>
                """
            }
            .joined(separator: "\n")

        return """
        <section class="platform-section">
            <div class="section-header">
                <h2>Application Components</h2>
                <span>Activities, services, receivers and providers</span>
            </div>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Type</th>
                            <th>Total</th>
                            <th>Exported</th>
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

    private func renderDeepLinksSection() -> String {
        guard case .apk(let apk) = platform, !apk.deepLinks.isEmpty else { return "" }
        let rows = apk.deepLinks.map { link in
            """
            <tr>
                <td>\(link.componentName.htmlEscaped)</td>
                <td>\((link.scheme ?? "—").htmlEscaped)</td>
                <td>\((link.host ?? "—").htmlEscaped)</td>
                <td>\((link.path ?? "—").htmlEscaped)</td>
                <td>\((link.mimeType ?? "—").htmlEscaped)</td>
            </tr>
            """
        }.joined(separator: "\n")
        return """
        <section class="platform-section">
            <div class="section-header">
                <h2>Deep Links</h2>
                <span>Intent filters exposing app content</span>
            </div>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Component</th>
                            <th>Scheme</th>
                            <th>Host</th>
                            <th>Path</th>
                            <th>MIME</th>
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


    private func renderCategoryVisualizationSection() -> String {
        let totalReadable = formattedBytes(analysis.totalSize).htmlEscaped
        return """
        <section class="viz-section" id="category-visualization">
            <div class="section-header">
                <h2>Distribution by Category</h2>
                <span>Hover segments for details, tap legend to isolate</span>
            </div>
            <div class="viz-section-content">
                <div class="category-chart-shell">
                    <canvas id="categoryChart" aria-label="Category distribution donut chart"></canvas>
                    <div class="category-chart-label" id="categoryChartLabel">
                        <p class="chart-label-title" data-chart-label-title>All categories</p>
                        <p class="chart-label-value" data-chart-label-value>\(totalReadable)</p>
                    </div>
                    <div class="category-tooltip" id="categoryChartTooltip" aria-hidden="true"></div>
                </div>
                <ul class="category-legend" id="categoryLegend"></ul>
            </div>
        </section>
        """
    }

    private func renderTreemapSection() -> String {
        return """
        <section class="treemap-section" id="treemap-section">
            <div class="section-header">
                <h2>Bundle Treemap</h2>
                <span>Explore folder composition visually</span>
            </div>
            <div class="treemap-wrapper">
                <div class="treemap-controls">
                    <div class="treemap-breadcrumb" id="treemapBreadcrumb">Root</div>
                    <button class="treemap-reset" type="button" id="treemapReset">Reset</button>
                </div>
                <div class="treemap" id="treemap"></div>
            </div>
        </section>
        """
    }

    private func renderFileExplorerSection(initialLimit: Int = 25) -> String {
        guard !fileEntries.isEmpty else {
            return """
            <section>
                <div class="section-header">
                    <h2>Interactive File Explorer</h2>
                    <span>No file data available</span>
                </div>
                <p class="empty-state">No file entries available in this analysis.</p>
            </section>
            """
        }

        let sorted = fileEntries.sorted { $0.size > $1.size }
        let initialRows = renderFileRows(for: sorted.prefix(initialLimit))
        let typeOptions = uniqueFileTypes
            .map { "<option value=\"\($0.htmlEscaped)\">\(displayName(forType: $0).htmlEscaped)</option>" }
            .joined(separator: "\n")
        let libraryFilterControl = renderLibraryFilterControl()
        let initialStatus = "Showing top \(min(initialLimit, fileEntries.count)) of \(fileEntries.count) files"

        return """
        <section id="file-explorer">
            <div class="section-header">
                <h2>Interactive File Explorer</h2>
                <span>Explore \(fileEntries.count) files without leaving the CLI</span>
            </div>
            <div class="section-controls">
                <div class="search-group">
                    <input type="search" id="fileSearch" placeholder="Search by path, name, type… (⌘K)" autocomplete="off" />
                    <span class="search-hint">⌘K</span>
                </div>
                <div class="filter-select">
                    <select id="typeFilter">
                        <option value="">All types</option>
                        \(typeOptions)
                    </select>
                </div>
                \(libraryFilterControl)
                <div class="sort-buttons" role="group" aria-label="Sort files">
                    <button class="sort-button active" data-sort="size" data-direction="desc">Size</button>
                    <button class="sort-button" data-sort="name" data-direction="asc">Name</button>
                </div>
            </div>
            <div class="table-wrapper interactive">
                <table>
                    <thead>
                        <tr>
                            <th>#</th>
                            <th>Path</th>
                            <th>Type</th>
                            <th>Library/SDK</th>
                            <th>Size</th>
                        </tr>
                    </thead>
                    <tbody id="fileTableBody">
                        \(initialRows)
                    </tbody>
                </table>
            </div>
            <div class="search-status" id="fileSearchStatus">\(initialStatus)</div>
        </section>
        """
    }

    private func renderLibraryFilterControl() -> String {
        guard !libraryNames.isEmpty else { return "" }
        let options = libraryNames
            .map { "<option value=\"\($0.htmlEscaped)\">\($0.htmlEscaped)</option>" }
            .joined(separator: "\n")
        return """
        <div class="filter-select">
            <select id="libraryFilter">
                <option value="">All libraries</option>
                \(options)
            </select>
        </div>
        """
    }

    private func renderFileRows(for entries: ArraySlice<FileEntry>) -> String {
        guard !entries.isEmpty else {
            return """
            <tr>
                <td colspan="5" class="empty-state">No file entries available.</td>
            </tr>
            """
        }

        return entries.enumerated().map { offset, entry in
            let displayIndex = offset + 1
            let meta = entry.internalName.flatMap { $0.isEmpty ? nil : $0 }
            let metaLine = meta.map { "<div class=\"path-meta\">Internal: \($0.htmlEscaped)</div>" } ?? ""
            return """
            <tr>
                <td>\(displayIndex)</td>
                <td>
                    <div class="path-main">\(entry.path.htmlEscaped)</div>
                    \(metaLine)
                </td>
                <td><span class="type-pill">\(entry.type.htmlEscaped)</span></td>
                <td>\(libraryTagHTML(for: entry.libraries ?? []))</td>
                <td>\(formattedBytes(entry.size))</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private func libraryTagHTML(for libraries: [String]) -> String {
        guard !libraries.isEmpty else {
            return "<span class=\"library-tag muted\">—</span>"
        }
        let tags = libraries.prefix(3).map { "<span class=\"library-tag\">\($0.htmlEscaped)</span>" }.joined(separator: "\n")
        let remainder = libraries.count > 3 ? "<span class=\"library-tag\">+\(libraries.count - 3)</span>" : ""
        return "<div class=\"library-tags\">\(tags)\(remainder)</div>"
    }

    private func normalizedTokens(for library: ThirdPartyLibraryInsight) -> [String] {
        var tokens = Set<String>()
        func addToken(_ value: String?) {
            guard let value = value else { return }
            let trimmed = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !trimmed.isEmpty else { return }
            tokens.insert(trimmed)
        }
        for package in library.packageMatches {
            addToken(package)
            addToken(package.replacingOccurrences(of: ".", with: "/"))
        }
        addToken(library.identifier.lowercased())
        addToken(library.identifier.replacingOccurrences(of: ":", with: "/").lowercased())
        let identifierComponents = library.identifier.split(separator: ":")
        if identifierComponents.count == 2 {
            addToken(identifierComponents[0].replacingOccurrences(of: ".", with: "/"))
            addToken(identifierComponents[1].replacingOccurrences(of: ".", with: "/"))
        }
        return Array(tokens)
    }

    private func librariesForFile(path: String, internalName: String?) -> [String] {
        guard !libraryMatchers.isEmpty else { return [] }
        let haystack = (path.lowercased() + " " + (internalName?.lowercased() ?? ""))
        var matches: [String] = []
        for matcher in libraryMatchers {
            if matcher.tokens.contains(where: { haystack.contains($0) }) {
                matches.append(matcher.name)
            }
        }
        return matches
    }

    private func renderBadge(title: String, type: BadgeType) -> String {
        return "<span class=\"badge \(type.rawValue)\">\(title.htmlEscaped)</span>"
    }

    private func renderFooter() -> String {
        return """
        <footer class="dashboard-footer">
            <p>Crafted with FRTMTools CLI • \(iso8601String())</p>
            <p>\(analysis.fileName.htmlEscaped) · \(analysis.url.path.htmlEscaped)</p>
        </footer>
        """
    }

    private func renderDashboardDataScriptTag() -> String {
        guard !fileEntries.isEmpty else { return "" }
        return """
        <script type="application/json" id="dashboard-data">
        \(dashboardPayloadJSON())
        </script>
        """
    }

    private func renderClientScripts() -> String {
        guard !fileEntries.isEmpty else { return "" }
        return """
        <script>
        (function () {
            const dataElement = document.getElementById('dashboard-data');
            if (!dataElement) { return; }
            let payload = {};
            try {
                payload = JSON.parse(dataElement.textContent || '{}');
            } catch (error) {
                console.error('Unable to parse dashboard data', error);
            }
            dataElement.remove();

            const tabContainer = document.querySelector('.tab-container');
            if (tabContainer) {
                const tabButtons = tabContainer.querySelectorAll('.tab-button');
                const tabContents = tabContainer.querySelectorAll('.tab-content');
                tabButtons.forEach(function (button) {
                    button.addEventListener('click', function () {
                        const target = button.getAttribute('data-tab-target');
                        tabButtons.forEach(function (entry) {
                            entry.classList.toggle('active', entry === button);
                        });
                        tabContents.forEach(function (content) {
                            content.classList.toggle('active', content.id === target);
                        });
                    });
                });
            }

            const files = payload.files || [];
            const categories = payload.categories || [];
            const tree = payload.treemap;

            function hashString(value) {
                let hash = 0;
                const input = String(value || '');
                for (let i = 0; i < input.length; i += 1) {
                    hash = ((hash << 5) - hash) + input.charCodeAt(i);
                    hash |= 0;
                }
                return Math.abs(hash);
            }

            function colorForNode(node, depth) {
                const hash = hashString(node.name);
                const hue = (hash % 360 + depth * 11) % 360;
                const saturation = depth === 0 ? 40 : 55;
                const lightness = Math.max(75 - depth * 8, 35);
                return 'hsl(' + hue + ', ' + saturation + '%, ' + lightness + '%)';
            }

            const tableBody = document.getElementById('fileTableBody');
            const statusLabel = document.getElementById('fileSearchStatus');
            const searchInput = document.getElementById('fileSearch');
            const typeFilter = document.getElementById('typeFilter');
            const libraryFilter = document.getElementById('libraryFilter');
            const sortButtons = document.querySelectorAll('.sort-button');
            if (!tableBody || !statusLabel || !searchInput) { return; }

            const MAX_ROWS = 200;
            const numberFormatter = new Intl.NumberFormat('en', { maximumFractionDigits: 1 });

            let sortKey = 'size';
            let sortDirection = 'desc';

            function escapeHTML(value) {
                return String(value || '').replace(/[&<>"']/g, function (character) {
                    return {
                        '&': '&amp;',
                        '<': '&lt;',
                        '>': '&gt;',
                        '"': '&quot;',
                        "'": '&#39;'
                    }[character];
                });
            }

            function formatBytes(bytes) {
                if (!Number.isFinite(bytes)) { return '0 B'; }
                const units = ['B', 'KB', 'MB', 'GB', 'TB'];
                let size = bytes;
                let unitIndex = 0;
                while (size >= 1024 && unitIndex < units.length - 1) {
                    size /= 1024;
                    unitIndex += 1;
                }
                return numberFormatter.format(size) + ' ' + units[unitIndex];
            }

            function render(entries) {
                if (!entries.length) {
                    tableBody.innerHTML = '<tr><td colspan="5" class="empty-state">No files match your filters.</td></tr>';
                    statusLabel.textContent = 'No matches found';
                    return;
                }

                const visibleRows = entries.slice(0, MAX_ROWS).map(function (entry, index) {
                    const meta = entry.internalName
                        ? '<div class="path-meta">Internal: ' + escapeHTML(entry.internalName) + '</div>'
                        : '';
                    const libraryCell = renderLibraryCell(entry);
                    return '<tr>' +
                        '<td>' + (index + 1) + '</td>' +
                        '<td><div class="path-main">' + escapeHTML(entry.path || entry.name || '') + '</div>' + meta + '</td>' +
                        '<td><span class="type-pill">' + escapeHTML(entry.type || 'file') + '</span></td>' +
                        '<td>' + libraryCell + '</td>' +
                        '<td>' + formatBytes(entry.size || 0) + '</td>' +
                    '</tr>';
                }).join('');

                tableBody.innerHTML = visibleRows;
                const shown = Math.min(entries.length, MAX_ROWS);
                const suffix = entries.length === files.length ? 'files' : 'matched files';
                statusLabel.textContent = 'Showing ' + shown + ' of ' + entries.length + ' ' + suffix;
            }

            function renderLibraryCell(entry) {
                const libs = entry.libraries || [];
                if (!libs.length) {
                    return '<span class="library-tag muted">—</span>';
                }
                const parts = libs.slice(0, 3).map(function (name) {
                    return '<span class="library-tag">' + escapeHTML(name) + '</span>';
                });
                if (libs.length > 3) {
                    parts.push('<span class="library-tag">+' + (libs.length - 3) + '</span>');
                }
                return '<div class="library-tags">' + parts.join('') + '</div>';
            }

            function sortEntries(list) {
                const sorted = list.slice();
                sorted.sort(function (a, b) {
                    if (sortKey === 'name' || sortKey === 'path') {
                        const left = (a.path || a.name || '').toLowerCase();
                        const right = (b.path || b.name || '').toLowerCase();
                        if (left === right) { return 0; }
                        return left < right ? -1 : 1;
                    }
                    const diff = (a.size || 0) - (b.size || 0);
                    return diff;
                });
                if (sortDirection === 'desc') {
                    sorted.reverse();
                }
                return sorted;
            }

            function applyFilters() {
                const query = (searchInput.value || '').trim().toLowerCase();
                const typeValue = typeFilter ? (typeFilter.value || '').toLowerCase() : '';
                const libraryValue = libraryFilter ? libraryFilter.value : '';

                let filtered = files;
                if (typeValue) {
                    filtered = filtered.filter(function (entry) {
                        return (entry.type || '').toLowerCase() === typeValue;
                    });
                }
                if (query) {
                    filtered = filtered.filter(function (entry) {
                        return (
                            (entry.path && entry.path.toLowerCase().includes(query)) ||
                            (entry.name && entry.name.toLowerCase().includes(query)) ||
                            (entry.internalName && entry.internalName.toLowerCase().includes(query))
                        );
                    });
                }

                if (libraryValue) {
                    filtered = filtered.filter(function (entry) {
                        return (entry.libraries || []).indexOf(libraryValue) !== -1;
                    });
                }

                filtered = sortEntries(filtered);
                render(filtered);
            }

            searchInput.addEventListener('input', applyFilters);
            if (typeFilter) {
                typeFilter.addEventListener('change', applyFilters);
            }
            if (libraryFilter) {
                libraryFilter.addEventListener('change', applyFilters);
            }

            sortButtons.forEach(function (button) {
                button.addEventListener('click', function () {
                    const targetSort = button.dataset.sort;
                    if (!targetSort) { return; }
                    if (sortKey === targetSort) {
                        sortDirection = sortDirection === 'desc' ? 'asc' : 'desc';
                    } else {
                        sortKey = targetSort;
                        sortDirection = button.dataset.direction || 'asc';
                    }
                    sortButtons.forEach(function (entry) {
                        entry.classList.toggle('active', entry === button);
                    });
                    applyFilters();
                });
            });

            document.addEventListener('keydown', function (event) {
                if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
                    event.preventDefault();
                    searchInput.focus();
                    searchInput.select();
                }
            });

            applyFilters();

            const libraryTable = document.getElementById('libraryTableBody');
            if (libraryTable) {
                const libraryRows = Array.from(libraryTable.querySelectorAll('tr'));
                const librarySearch = document.getElementById('librarySearch');
                const manifestToggle = document.getElementById('libraryManifestFilter');
                const libraryStatus = document.getElementById('librarySearchStatus');

                function applyLibraryFilters() {
                    const query = (librarySearch && librarySearch.value ? librarySearch.value : '').trim().toLowerCase();
                    const manifestOnly = manifestToggle ? manifestToggle.checked : false;
                    let visible = 0;
                    libraryRows.forEach(function (row) {
                        const haystack = row.getAttribute('data-haystack') || '';
                        const manifest = row.getAttribute('data-manifest') === 'true';
                        const matchesQuery = !query || haystack.indexOf(query) !== -1;
                        const matchesManifest = !manifestOnly || manifest;
                        const shouldShow = matchesQuery && matchesManifest;
                        row.style.display = shouldShow ? '' : 'none';
                        if (shouldShow) { visible += 1; }
                    });
                    if (libraryStatus) {
                        libraryStatus.textContent = 'Showing ' + visible + ' of ' + libraryRows.length + ' SDKs';
                    }
                }

                if (librarySearch) {
                    librarySearch.addEventListener('input', applyLibraryFilters);
                }
                if (manifestToggle) {
                    manifestToggle.addEventListener('change', applyLibraryFilters);
                }
                applyLibraryFilters();
            }

            function renderCategoryChart() {
                const canvas = document.getElementById('categoryChart');
                const legend = document.getElementById('categoryLegend');
                const label = document.getElementById('categoryChartLabel');
                const labelTitle = label ? label.querySelector('[data-chart-label-title]') : null;
                const labelValue = label ? label.querySelector('[data-chart-label-value]') : null;
                const tooltip = document.getElementById('categoryChartTooltip');
                if (!canvas || !legend || !categories.length) { return; }

                const ctx = canvas.getContext('2d');
                const palette = ['#6366f1', '#8b5cf6', '#ec4899', '#14b8a6', '#f97316', '#0ea5e9', '#22c55e', '#facc15'];
                const activeSegments = new Set(categories.map(function (_item, index) { return index; }));
                const totalBytes = categories.reduce(function (acc, item) {
                    return acc + (item.size || 0);
                }, 0);
                let segmentsMeta = [];
                let hoveredIndex = null;
                let hoverSource = null;

                function resizeCanvas() {
                    const size = canvas.parentElement ? canvas.parentElement.clientWidth - 20 : 320;
                    const resolved = Math.max(Math.min(size, 420), 220);
                    canvas.width = resolved;
                    canvas.height = resolved;
                }

                resizeCanvas();
                window.addEventListener('resize', function () {
                    resizeCanvas();
                    drawChart();
                });

                function drawChart() {
                    const radius = canvas.width / 2 - 12;
                    const centerX = canvas.width / 2;
                    const centerY = canvas.height / 2;
                    ctx.clearRect(0, 0, canvas.width, canvas.height);
                    const activeItems = categories.filter(function (_category, index) {
                        return activeSegments.has(index);
                    });
                    const total = activeItems.reduce(function (acc, item) {
                        return acc + (item.size || 0);
                    }, 0) || 1;
                    let startAngle = -Math.PI / 2;
                    let runningFraction = 0;
                    segmentsMeta = [];
                    const highlightActive = hoveredIndex !== null && activeSegments.has(hoveredIndex);

                    categories.forEach(function (category, index) {
                        if (!activeSegments.has(index)) { return; }
                        const value = Math.max(category.size || 0, 0);
                        if (value <= 0) { return; }
                        const fraction = value / total;
                        const sweep = Math.max(fraction * Math.PI * 2, 0.01);
                        const isHovered = hoveredIndex === index;
                        ctx.beginPath();
                        ctx.moveTo(centerX, centerY);
                        ctx.arc(centerX, centerY, radius, startAngle, startAngle + sweep);
                        ctx.closePath();
                        ctx.fillStyle = palette[index % palette.length];
                        ctx.globalAlpha = highlightActive && !isHovered ? 0.35 : 1;
                        ctx.fill();
                        ctx.globalAlpha = 1;

                        segmentsMeta.push({
                            index: index,
                            startFraction: runningFraction,
                            endFraction: runningFraction + fraction,
                            color: palette[index % palette.length],
                            size: category.size || 0,
                            percent: (category.percent || 0) * 100
                        });

                        runningFraction += fraction;
                        startAngle += sweep;
                    });

                    ctx.beginPath();
                    ctx.arc(centerX, centerY, radius * 0.5, 0, Math.PI * 2);
                    ctx.fillStyle = '#f8fafc';
                    ctx.fill();
                }

                function updateLabel(index) {
                    if (!labelTitle || !labelValue) { return; }
                    if (index === null || !categories[index]) {
                        labelTitle.textContent = 'All categories';
                        labelValue.textContent = formatBytes(totalBytes);
                        return;
                    }
                    const category = categories[index];
                    labelTitle.textContent = category.name || 'Category';
                    labelValue.textContent = formatBytes(category.size || 0);
                }

                function renderLegend() {
                    const markup = categories.map(function (category, index) {
                        const color = palette[index % palette.length];
                        const percent = Math.round((category.percent || 0) * 1000) / 10;
                        const isActive = activeSegments.has(index);
                        return '<li role="button" tabindex="0" data-index="' + index + '" data-active="' + isActive + '" aria-pressed="' + isActive + '">' +
                            '<span class="legend-color" style="background:' + color + '"></span>' +
                            '<span>' + escapeHTML(category.name || 'Unknown') + '</span>' +
                            '<span class="legend-value">' + percent + '%</span>' +
                        '</li>';
                    }).join('');
                    legend.innerHTML = markup;
                    updateLegendState();
                }

                function updateLegendState() {
                    const items = legend.querySelectorAll('li[data-index]');
                    items.forEach(function (item) {
                        const index = Number(item.dataset.index);
                        item.dataset.active = String(activeSegments.has(index));
                        item.setAttribute('aria-pressed', String(activeSegments.has(index)));
                        item.classList.toggle('is-hovered', hoveredIndex === index);
                    });
                }

                function toggleSegment(index) {
                    if (activeSegments.has(index)) {
                        if (activeSegments.size === 1) { return; }
                        activeSegments.delete(index);
                    } else {
                        activeSegments.add(index);
                    }
                    if (!activeSegments.has(index) && hoveredIndex === index) {
                        hoveredIndex = null;
                    }
                    drawChart();
                    renderLegend();
                    updateLabel(hoveredIndex);
                }

                legend.addEventListener('click', function (event) {
                    const target = event.target.closest('li[data-index]');
                    if (!target) { return; }
                    toggleSegment(Number(target.dataset.index));
                });

                legend.addEventListener('keydown', function (event) {
                    if (event.key !== 'Enter' && event.key !== ' ') { return; }
                    const target = event.target.closest('li[data-index]');
                    if (!target) { return; }
                    event.preventDefault();
                    toggleSegment(Number(target.dataset.index));
                });

                legend.addEventListener('mouseover', function (event) {
                    const target = event.target.closest('li[data-index]');
                    if (!target) { return; }
                    setHover(Number(target.dataset.index), 'legend');
                });
                legend.addEventListener('mouseout', function (event) {
                    if (legend.contains(event.relatedTarget)) { return; }
                    clearHover('legend');
                });

                function normalizeAngle(angle) {
                    let normalized = angle + Math.PI / 2;
                    normalized = normalized % (Math.PI * 2);
                    if (normalized < 0) {
                        normalized += Math.PI * 2;
                    }
                    return normalized;
                }

                function findSegmentFromPointer(x, y) {
                    const center = canvas.width / 2;
                    const dx = x - center;
                    const dy = y - center;
                    const radius = canvas.width / 2 - 12;
                    const distance = Math.sqrt(dx * dx + dy * dy);
                    if (distance > radius || distance < radius * 0.5) {
                        return null;
                    }
                    const angle = Math.atan2(dy, dx);
                    const fraction = normalizeAngle(angle) / (Math.PI * 2);
                    for (let i = 0; i < segmentsMeta.length; i += 1) {
                        const segment = segmentsMeta[i];
                        const endFraction = i === segmentsMeta.length - 1 ? 1 : segment.endFraction;
                        if (fraction >= segment.startFraction && fraction <= endFraction + 1e-4) {
                            return segment;
                        }
                    }
                    return null;
                }

                function showTooltip(event, segment) {
                    if (!tooltip || !segment) { return; }
                    const shell = canvas.parentElement;
                    if (!shell) { return; }
                    const rect = shell.getBoundingClientRect();
                    tooltip.textContent = (categories[segment.index].name || 'Category') + ' · ' + formatBytes(segment.size || 0);
                    tooltip.style.left = (event.clientX - rect.left) + 'px';
                    tooltip.style.top = (event.clientY - rect.top) + 'px';
                    tooltip.classList.add('visible');
                    tooltip.setAttribute('aria-hidden', 'false');
                }

                function hideTooltip() {
                    if (!tooltip) { return; }
                    tooltip.classList.remove('visible');
                    tooltip.setAttribute('aria-hidden', 'true');
                }

                function setHover(index, source) {
                    if (hoveredIndex === index && hoverSource === source) { return; }
                    hoveredIndex = index;
                    hoverSource = source;
                    updateLabel(index);
                    updateLegendState();
                    drawChart();
                }

                function clearHover(source) {
                    if (hoverSource !== source) { return; }
                    hoveredIndex = null;
                    hoverSource = null;
                    updateLabel(null);
                    updateLegendState();
                    drawChart();
                    hideTooltip();
                }

                canvas.addEventListener('mousemove', function (event) {
                    const rect = canvas.getBoundingClientRect();
                    const segment = findSegmentFromPointer(event.clientX - rect.left, event.clientY - rect.top);
                    if (!segment) {
                        hideTooltip();
                        clearHover('canvas');
                        return;
                    }
                    setHover(segment.index, 'canvas');
                    showTooltip(event, segment);
                });

                canvas.addEventListener('mouseleave', function () {
                    hideTooltip();
                    clearHover('canvas');
                });

                drawChart();
                renderLegend();
                updateLabel(null);
            }

            function renderTreemapRoot() {
                if (!tree) { return; }
                const container = document.getElementById('treemap');
                const breadcrumb = document.getElementById('treemapBreadcrumb');
                const resetButton = document.getElementById('treemapReset');
                if (!container || !breadcrumb || !resetButton) { return; }

                const stack = [tree];

                function formatSize(value) {
                    return formatBytes(value);
                }

                function hasChildren(node) {
                    return node && Array.isArray(node.children) && node.children.some(function (child) {
                        return (child.size || 0) > 0;
                    });
                }

                function setBreadcrumb() {
                    breadcrumb.textContent = stack.map(function (node) { return node.name; }).join(' / ');
                }

                function tessellateNodes(children, bounds) {
                    const sorted = children
                        .slice()
                        .filter(function (child) { return (child.size || 0) > 0; })
                        .sort(function (a, b) { return (b.size || 0) - (a.size || 0); });
                    if (!sorted.length) { return []; }

                    const values = sorted.map(function (child) { return Math.max(child.size || 0, 0); });
                    const total = values.reduce(function (sum, value) { return sum + value; }, 0) || 1;
                    const weights = values.map(function (value) { return value / total; });

                    function tessellate(weightsList, rect) {
                        const rects = [];
                        const rectArea = rect.width * rect.height;
                        const areas = weightsList.map(function (weight) { return weight * rectArea; });
                        let remaining = { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
                        let remainingAreas = areas.slice();

                        while (remainingAreas.length > 0 && remaining.width > 0 && remaining.height > 0) {
                            const result = tessellateRow(remainingAreas, remaining);
                            rects.push(...result.rects);
                            remaining = result.remaining;
                            remainingAreas = remainingAreas.slice(result.used);
                        }

                        return rects;
                    }

                    function tessellateRow(areasList, rect) {
                        let direction;
                        let length;
                        if (rect.width >= rect.height) {
                            direction = 'horizontal';
                            length = rect.height || 1;
                        } else {
                            direction = 'vertical';
                            length = rect.width || 1;
                        }

                        let aspectRatio = Infinity;
                        let groupWeight = 0;
                        const accepted = [];
                        let used = 0;
                        for (let i = 0; i < areasList.length; i += 1) {
                            const area = areasList[i];
                            const worst = worstAspect(accepted, groupWeight, area, length, aspectRatio);
                            if (worst > aspectRatio && accepted.length > 0) {
                                break;
                            }
                            accepted.push(area);
                            groupWeight += area;
                            aspectRatio = worst;
                            used += 1;
                        }

                        if (!accepted.length) {
                            accepted.push(areasList[0]);
                            used = 1;
                            groupWeight = areasList[0];
                        }

                        const width = groupWeight / length;
                        let offset = direction === 'horizontal' ? rect.y : rect.x;
                        const produced = accepted.map(function (area) {
                            const height = area / width;
                            const tileRect = direction === 'horizontal'
                                ? { x: rect.x, y: offset, width: width, height: height }
                                : { x: offset, y: rect.y, width: height, height: width };
                            offset += height;
                            return tileRect;
                        });

                        let remaining;
                        if (direction === 'horizontal') {
                            remaining = {
                                x: rect.x + width,
                                y: rect.y,
                                width: Math.max(0, rect.width - width),
                                height: rect.height
                            };
                        } else {
                            remaining = {
                                x: rect.x,
                                y: rect.y + width,
                                width: rect.width,
                                height: Math.max(0, rect.height - width)
                            };
                        }

                        return { rects: produced, remaining: remaining, used: used };
                    }

                    function worstAspect(currentAreas, currentGroupWeight, proposedArea, length, limit) {
                        const groupWeight = currentGroupWeight + proposedArea;
                        if (length <= 0 || groupWeight <= 0) { return Infinity; }
                        const width = groupWeight / length;
                        const proposedAspect = aspectRatio(width, proposedArea / width);
                        let worst = proposedAspect;
                        for (let i = 0; i < currentAreas.length; i += 1) {
                            const existing = aspectRatio(width, currentAreas[i] / width);
                            worst = Math.max(worst, existing);
                            if (worst > limit) {
                                break;
                            }
                        }
                        return worst;
                    }

                    function aspectRatio(edge1, edge2) {
                        const a = Math.max(edge1, edge2);
                        const b = Math.min(edge1, edge2);
                        if (b <= 0) { return Infinity; }
                        return a / b;
                    }

                    const rects = tessellate(weights, {
                        x: bounds.x,
                        y: bounds.y,
                        width: Math.max(bounds.width, 1),
                        height: Math.max(bounds.height, 1)
                    });

                    const mapped = [];
                    sorted.forEach(function (node, index) {
                        const rect = rects[index];
                        if (rect && rect.width > 0 && rect.height > 0) {
                            mapped.push({ node: node, rect: rect });
                        }
                    });
                    return mapped;
                }

                function renderCurrent() {
                    const node = stack[stack.length - 1];
                    container.innerHTML = '';
                    const children = (node.children || []).filter(function (child) { return (child.size || 0) > 0; });
                    if (!children.length) {
                        container.innerHTML = '<div class="empty-state" style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center;background:#f8fafc;">No further items</div>';
                        return;
                    }
                    const rect = container.getBoundingClientRect();
                    const layouts = tessellateNodes(children, {
                        x: 0,
                        y: 0,
                        width: Math.max(rect.width, 1),
                        height: Math.max(rect.height, 1)
                    });
                    layouts.forEach(function (segment, index) {
                        const tile = document.createElement('div');
                        tile.className = 'treemap-tile';
                        tile.style.left = segment.rect.x + 'px';
                        tile.style.top = segment.rect.y + 'px';
                        tile.style.width = Math.max(segment.rect.width, 2) + 'px';
                        tile.style.height = Math.max(segment.rect.height, 2) + 'px';
                        const background = colorForNode(segment.node, stack.length - 1);
                        tile.style.background = background;
                        tile.style.borderColor = 'rgba(15, 23, 42, 0.08)';
                        tile.innerHTML = '<div class="tile-name">' + escapeHTML(segment.node.name) + '</div>' +
                            '<div class="tile-size">' + formatSize(segment.node.size || 0) + '</div>';
                        tile.title = segment.node.name + ' • ' + formatSize(segment.node.size || 0) + ' (' + segment.node.type + ')';

                        if (hasChildren(segment.node)) {
                            tile.style.cursor = 'pointer';
                            tile.addEventListener('click', function (event) {
                                event.stopPropagation();
                                stack.push(segment.node);
                                setBreadcrumb();
                                renderCurrent();
                            });
                        }

                        container.appendChild(tile);
                    });
                }

                resetButton.addEventListener('click', function () {
                    stack.length = 1;
                    setBreadcrumb();
                    renderCurrent();
                });

                container.addEventListener('click', function () {
                    if (stack.length > 1) {
                        stack.pop();
                        setBreadcrumb();
                        renderCurrent();
                    }
                });

                setBreadcrumb();
                renderCurrent();
            }

            renderCategoryChart();
            renderTreemapRoot();
        })();
        </script>
        """
    }

    private func dashboardPayloadJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let payload = DashboardPayload(files: fileEntries, categories: categoryDataset, treemap: treemapRoot)
        guard let data = try? encoder.encode(payload) else { return "{}" }
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return json.replacingOccurrences(of: "</", with: "<\\/")
    }

    private var resolvedInstalledSizeMetrics: InstalledSizeMetrics? {
        if let metrics = analysis.installedSize {
            return metrics
        }
        return estimateInstalledSizeMetrics()
    }

    private func estimateInstalledSizeMetrics() -> InstalledSizeMetrics? {
        let totalBytes = analysis.rootFile.size
        guard totalBytes > 0 else { return nil }
        let binaryBytes = sumBytes { file in
            switch file.type {
            case .binary, .dex:
                return true
            default:
                return false
            }
        }
        let frameworkBytes = sizeForCategories(types: Set([.frameworks, .nativeLibs]))
        var remainingBytes = totalBytes - binaryBytes - frameworkBytes
        if remainingBytes < 0 { remainingBytes = 0 }

        let totalMB = megabytes(from: totalBytes)
        let binariesMB = megabytes(from: binaryBytes)
        let frameworksMB = megabytes(from: frameworkBytes)
        let resourcesMB = max(totalMB - binariesMB - frameworksMB, 0)

        return InstalledSizeMetrics(
            total: max(totalMB, 1),
            binaries: binariesMB,
            frameworks: frameworksMB,
            resources: resourcesMB
        )
    }

    private func sumBytes(where predicate: (FileInfo) -> Bool) -> Int64 {
        flattenedFiles.reduce(Int64(0)) { partial, file in
            predicate(file) ? partial + file.size : partial
        }
    }

    private func sizeForCategories(types: Set<CategoryType>) -> Int64 {
        categories
            .filter { types.contains($0.type) }
            .reduce(Int64(0)) { partial, category in
                partial + category.items.reduce(Int64(0)) { $0 + $1.size }
            }
    }

    private func formattedBytes(_ size: Int64) -> String {
        return byteFormatter.string(fromByteCount: size)
    }

    private func megabytes(from bytes: Int64) -> Int {
        if bytes <= 0 { return 0 }
        return Int((bytes + 1_048_575) / 1_048_576)
    }

    private func formatMegabytes(_ value: Int) -> String {
        return "\(value) MB"
    }

    private func iosLocalizationStats() -> [(code: String, size: Int64)] {
        var stats: [String: Int64] = [:]
        collectLocalizationSizes(from: analysis.rootFile, into: &stats)
        return stats
            .map { (code: $0.key, size: $0.value) }
            .sorted { $0.size > $1.size }
    }

    private func collectLocalizationSizes(from node: FileInfo, into stats: inout [String: Int64]) {
        let name = node.name.lowercased()
        if name.hasSuffix(".lproj") {
            let code = String(name.dropLast(6))
            stats[code, default: 0] += node.size
            return
        }
        for child in node.subItems ?? [] {
            collectLocalizationSizes(from: child, into: &stats)
        }
    }

    private func displayName(for type: AndroidComponentType) -> String {
        switch type {
        case .activity: return "Activity"
        case .activityAlias: return "Activity Alias"
        case .service: return "Service"
        case .receiver: return "Broadcast Receiver"
        case .provider: return "Content Provider"
        }
    }

    private func versionSummaryText() -> String? {
        var components: [String] = []
        if let version = analysis.version, !version.isEmpty {
            components.append("Version \(version)")
        }
        if let build = analysis.buildNumber, !build.isEmpty {
            components.append("Build \(build)")
        }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: " · ")
    }

    private func displayName(forType type: String) -> String {
        switch type.lowercased() {
        case "app": return "App Bundle"
        case "binary": return "Binary"
        case "framework": return "Framework"
        case "bundle": return "Bundle"
        case "assets": return "Asset Catalog"
        case "plist": return "Property List"
        case "lproj": return "Localization"
        default:
            return type.capitalized
        }
    }

    private func percentString(for part: Int64) -> String {
        guard analysis.totalSize > 0 else { return "0" }
        let value = (Double(part) / Double(analysis.totalSize)) * 100
        return String(format: "%.1f", value)
    }

    private func percentWidth(for part: Int64) -> String {
        guard analysis.totalSize > 0 else { return "0" }
        let value = min(100, max(0, (Double(part) / Double(analysis.totalSize)) * 100))
        return String(format: "%.2f", value)
    }

    private func iso8601String() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    private enum BadgeType: String {
        case success = "badge-success"
        case warning = "badge-warning"
        case critical = "badge-critical"
    }

    private struct InventoryCard {
        let title: String
        let subtitle: String?
        let body: String
    }

    private struct DuplicateInsightSection {
        let kind: Tip.Kind
        let title: String
        let summary: String
        let entries: [DuplicateEntry]
        let exportFileName: String
        let exportPayload: String
    }

    private struct DuplicateEntry {
        let summary: String
        let paths: [String]
    }

    private struct FileEntry: Codable {
        let index: Int
        let name: String
        let path: String
        let type: String
        let size: Int64
        let internalName: String?
        let libraries: [String]?
    }

    private struct LibraryMatcher {
        let name: String
        let tokens: [String]
    }

    private struct SummaryCardEntry {
        let title: String
        let value: String
        let meta: String
        let extraClass: String?
    }
    
    private struct TabItem {
        let id: String
        let label: String
        let content: String
        let emptyMessage: String
    }

    private struct CategoryDatum: Codable {
        let id: String
        let name: String
        let size: Int64
        let percent: Double
    }

    private struct TreemapNode: Codable {
        let id: UUID
        let name: String
        let size: Int64
        let type: String
        let children: [TreemapNode]?

        init(file: FileInfo, depth: Int, maxChildren: Int = 18) {
            self.id = file.id
            self.name = file.name
            self.size = file.size
            self.type = file.type.rawValue

            if let subItems = file.subItems, !subItems.isEmpty {
                let limit = depth == 0 ? maxChildren : min(maxChildren, 12)
                let sortedChildren = subItems.sorted { $0.size > $1.size }
                let selected = Array(sortedChildren.prefix(limit))
                let nodes = selected.map { TreemapNode(file: $0, depth: depth + 1, maxChildren: maxChildren) }
                self.children = nodes.isEmpty ? nil : nodes
            } else {
                self.children = nil
            }
        }
    }

    private struct DashboardPayload: Codable {
        let files: [FileEntry]
        let categories: [CategoryDatum]
        let treemap: TreemapNode
    }
}

enum DashboardHTMLStyle {
    static let baseCSS = """
:root {
    color-scheme: light;
    --font-sans: 'Inter', 'SF Pro Display', -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
    --font-mono: 'JetBrains Mono', 'SFMono-Regular', ui-monospace, Menlo, Consolas, monospace;
    --color-bg: #eff2f7;
    --color-surface: #ffffff;
    --color-elevated: #f7f9fd;
    --color-muted-surface: #f0f4ff;
    --color-border: #dfe5f1;
    --color-border-strong: #c5cfdf;
    --color-text: #0f172a;
    --color-muted: #5b6474;
    --color-subtle: #7c869a;
    --color-primary: #2563eb;
    --color-primary-strong: #1d4ed8;
    --color-primary-soft: rgba(37, 99, 235, 0.12);
    --color-positive: #0d9488;
    --color-negative: #b91c1c;
    --color-warning: #c2410c;
    --radius-lg: 28px;
    --radius-md: 20px;
    --radius-sm: 12px;
    --shadow-soft: 0 25px 60px rgba(15, 23, 42, 0.08);
    --shadow-card: 0 12px 30px rgba(15, 23, 42, 0.06);
    --shadow-faint: 0 1px 3px rgba(15, 23, 42, 0.12);
    --layout-max: 1180px;
}

*, *::before, *::after {
    box-sizing: border-box;
}

body {
    margin: 0;
    font-family: var(--font-sans);
    background: radial-gradient(circle at top, rgba(37, 99, 235, 0.08), transparent 55%), var(--color-bg);
    color: var(--color-text);
    line-height: 1.6;
    -webkit-font-smoothing: antialiased;
}

img { max-width: 100%; height: auto; display: block; }
button, input, select { font: inherit; color: inherit; }
a { color: var(--color-primary); text-decoration: none; }
a:hover { text-decoration: underline; }

.dashboard-shell {
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    gap: clamp(1.25rem, 2vw, 1.75rem);
}

.dashboard-header {
    width: 100%;
    margin: clamp(1.25rem, 2vw, 2.5rem) 0 0;
    padding: clamp(1.5rem, 2vw, 2.75rem) clamp(1.5rem, 4vw, 4rem);
    background: var(--color-surface);
    border-radius: var(--radius-lg);
    display: grid;
    gap: clamp(1.5rem, 2vw, 2rem);
    border: 1px solid var(--color-border);
    box-shadow: var(--shadow-soft);
}

@media (min-width: 960px) {
    .dashboard-header {
        grid-template-columns: minmax(0, 1fr) 360px;
        align-items: stretch;
    }
}

.header-main {
    display: flex;
    gap: 1.5rem;
    align-items: flex-start;
    min-width: 0;
    flex-wrap: wrap;
}

.app-icon img,
.fallback-icon {
    width: 96px;
    height: 96px;
    border-radius: 22px;
    object-fit: cover;
    background: var(--color-elevated);
    border: 1px solid var(--color-border);
    box-shadow: var(--shadow-faint);
}

.fallback-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 2rem;
    font-weight: 600;
    color: var(--color-primary-strong);
}

.hero-text { display: flex; flex-direction: column; gap: 0.4rem; min-width: 0; }
.hero-eyebrow {
    margin: 0;
    text-transform: uppercase;
    letter-spacing: 0.18em;
    font-size: 0.72rem;
    color: var(--color-subtle);
}
.hero-title {
    margin: 0;
    font-size: clamp(2rem, 4vw, 2.9rem);
    line-height: 1.2;
    word-break: break-word;
}
.hero-subtitle, .hero-source {
    margin: 0;
    color: var(--color-muted);
    font-size: 1rem;
    overflow-wrap: anywhere;
}
.hero-source {
    font-family: var(--font-mono);
    font-size: 0.85rem;
}
.hero-badges {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin-top: 0.35rem;
}

.badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: 999px;
    padding: 0.35rem 0.9rem;
    font-size: 0.75rem;
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    border: 1px solid var(--color-border);
    background: var(--color-primary-soft);
    color: var(--color-primary-strong);
}
.badge-success { background: rgba(13, 148, 136, 0.15); color: var(--color-positive); border-color: rgba(13, 148, 136, 0.4); }
.badge-warning { background: rgba(194, 65, 12, 0.15); color: var(--color-warning); border-color: rgba(194, 65, 12, 0.4); }
.badge-critical { background: rgba(185, 28, 28, 0.12); color: var(--color-negative); border-color: rgba(185, 28, 28, 0.35); }
.badge-neutral { background: var(--color-elevated); color: var(--color-muted); }
.badge-soft { background: var(--color-muted-surface); color: var(--color-text); }

.header-meta {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    min-width: 0;
}
.meta-list {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
    gap: 0.85rem 1rem;
    margin: 0;
    padding: 0;
}
.meta-list > div { display: flex; flex-direction: column; gap: 0.3rem; min-width: 0; }
.meta-list dt {
    margin: 0;
    font-size: 0.72rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--color-subtle);
}
.meta-list dd {
    margin: 0;
    font-weight: 600;
    font-size: 1rem;
    word-break: break-word;
}

.header-actions {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
}
.header-note {
    margin: 0;
    font-size: 0.9rem;
    color: var(--color-muted);
}

.link-button {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    padding: 0.4rem 0.9rem;
    border-radius: 999px;
    border: 1px solid transparent;
    background: var(--color-primary);
    color: #fff;
    font-weight: 600;
    cursor: pointer;
    transition: background 0.2s ease;
}
.link-button:hover { background: var(--color-primary-strong); }


.dashboard-main {
    width: 100%;
    padding: 0 clamp(1.5rem, 4vw, 4rem) clamp(2rem, 3vw, 3.5rem);
    display: flex;
    flex-direction: column;
    gap: clamp(1.2rem, 2vw, 1.75rem);
}

.section-stack { display: flex; flex-direction: column; gap: clamp(1.25rem, 2vw, 1.75rem); }

section, .section {
    background: var(--color-surface);
    border-radius: var(--radius-md);
    border: 1px solid var(--color-border);
    padding: clamp(1.25rem, 2vw, 2rem);
    box-shadow: var(--shadow-card);
}

.section-header {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-start;
    justify-content: space-between;
    gap: 1rem;
    padding-bottom: 0.75rem;
    margin-bottom: 1.25rem;
    border-bottom: 1px solid rgba(15, 23, 42, 0.08);
}
.section-header h2 { margin: 0; font-size: 1.4rem; }
.section-header span, .section-header p { margin: 0; color: var(--color-muted); }
.section-eyebrow { margin: 0 0 0.35rem; text-transform: uppercase; letter-spacing: 0.18em; font-size: 0.72rem; color: var(--color-subtle); }

.kpi-strip {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 1rem;
}
.kpi-card {
    background: var(--color-elevated);
    border-radius: var(--radius-sm);
    border: 1px solid var(--color-border);
    padding: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.3rem;
    box-shadow: var(--shadow-faint);
}
.kpi-label { font-size: 0.85rem; color: var(--color-muted); margin: 0; }
.kpi-value { font-size: 1.8rem; margin: 0; font-weight: 600; line-height: 1.2; word-break: break-word; }
.kpi-meta { margin: 0; font-size: 0.85rem; color: var(--color-subtle); }

.table-wrapper {
    width: 100%;
    overflow-x: auto;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-surface);
}
.table-wrapper table { min-width: 100%; }
table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.95rem;
}
thead th {
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-size: 0.75rem;
    color: var(--color-subtle);
    background: var(--color-elevated);
}
th, td {
    padding: 0.85rem 1rem;
    border-bottom: 1px solid var(--color-border);
    text-align: left;
    vertical-align: top;
}
tbody tr:nth-child(even) { background: rgba(15, 23, 42, 0.015); }

td { color: var(--color-text); word-break: break-word; hyphens: auto; }

.td-numeric, .th-numeric, .numeric { text-align: right; font-variant-numeric: tabular-nums; }
.td-delta.positive { color: var(--color-negative); }
.td-delta.negative { color: var(--color-positive); }
.td-delta.neutral { color: var(--color-muted); }
.td-path, .path-main, .hero-source { font-family: var(--font-mono); }
.path-main { font-weight: 600; }
.path-meta, .meta, .value { color: var(--color-muted); font-size: 0.9rem; }

.section-controls {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    padding: 1rem;
    border-radius: var(--radius-sm);
    border: 1px solid var(--color-border);
    background: var(--color-elevated);
    margin-bottom: 1rem;
}
.search-group { position: relative; min-width: 220px; flex: 1; }
.search-group input {
    width: 100%;
    padding-right: 2.5rem;
}
.search-hint {
    position: absolute;
    right: 0.75rem;
    top: 50%;
    transform: translateY(-50%);
    font-size: 0.75rem;
    color: var(--color-subtle);
    background: var(--color-surface);
    border-radius: 6px;
    padding: 0.1rem 0.4rem;
}
.filter-select select, input[type="search"], select {
    padding: 0.55rem 0.85rem;
    border-radius: 10px;
    border: 1px solid var(--color-border-strong);
    background: var(--color-surface);
}
.filter-select { min-width: 180px; }
.filter-toggle { display: inline-flex; align-items: center; gap: 0.35rem; font-size: 0.9rem; color: var(--color-text); }
.filter-toggle input { accent-color: var(--color-primary); }
.sort-buttons { display: inline-flex; border-radius: 999px; border: 1px solid var(--color-border); overflow: hidden; }
.sort-button {
    border: none;
    background: transparent;
    padding: 0.4rem 0.9rem;
    font-weight: 600;
    color: var(--color-muted);
    cursor: pointer;
}
.sort-button.active { background: var(--color-primary); color: #fff; }

.search-status { margin-top: 0.75rem; font-size: 0.9rem; color: var(--color-muted); }

.tab-container {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    padding: 1rem;
    background: var(--color-elevated);
}
.tab-nav {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
}
.tab-button {
    border: none;
    border-radius: 999px;
    padding: 0.4rem 1rem;
    font-weight: 600;
    background: var(--color-surface);
    color: var(--color-muted);
    cursor: pointer;
    transition: all 0.2s ease;
}
.tab-button.active {
    background: var(--color-primary);
    color: #fff;
    box-shadow: var(--shadow-faint);
}
.tab-content { display: none; }
.tab-content.active { display: block; }

.viz-section-content {
    display: flex;
    flex-wrap: wrap;
    gap: 1.5rem;
    align-items: flex-start;
}
.category-chart-shell {
    position: relative;
    flex: 0 0 320px;
    width: min(360px, 45vw);
    aspect-ratio: 1 / 1;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0.5rem;
}
.category-chart-shell canvas {
    width: 100%;
    height: 100%;
}
.category-chart-label {
    position: absolute;
    text-align: center;
    pointer-events: none;
    background: rgba(255, 255, 255, 0.9);
    backdrop-filter: blur(6px);
    border-radius: 50%;
    padding: 0.9rem 1.1rem;
    min-width: 130px;
}
.chart-label-title {
    margin: 0;
    font-size: 0.85rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--color-subtle);
}
.chart-label-value {
    margin: 0.1rem 0 0;
    font-size: 1.15rem;
    font-weight: 600;
}
.category-tooltip {
    position: absolute;
    pointer-events: none;
    background: var(--color-text);
    color: #fff;
    font-size: 0.8rem;
    padding: 0.35rem 0.6rem;
    border-radius: 6px;
    opacity: 0;
    transform: translate(-50%, -120%);
    transition: opacity 0.12s ease;
    z-index: 5;
}
.category-tooltip.visible {
    opacity: 1;
}
.category-legend {
    list-style: none;
    margin: 0;
    padding: 0;
    max-height: 360px;
    overflow-y: auto;
    font-size: 0.9rem;
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
}
.category-legend li {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    cursor: pointer;
    padding: 0.35rem 0.5rem;
    border-radius: var(--radius-sm);
    transition: background 0.15s ease, transform 0.15s ease, opacity 0.15s ease;
}
.category-legend li[data-active="false"] {
    opacity: 0.4;
}
.category-legend li.is-hovered {
    background: var(--color-muted-surface);
    transform: translateX(6px);
}
.category-legend li:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
}
.legend-color { width: 12px; height: 12px; border-radius: 3px; }
.legend-value { margin-left: auto; font-weight: 600; color: var(--color-muted); }

.treemap-section .treemap-wrapper {
    position: relative;
    min-height: 400px;
    background: var(--color-elevated);
    border-radius: var(--radius-sm);
    border: 1px dashed var(--color-border);
}
.treemap-controls {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 48px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 1rem;
    background: rgba(255,255,255,0.9);
    backdrop-filter: blur(4px);
    border-bottom: 1px solid var(--color-border);
}
.treemap-breadcrumb { font-family: var(--font-mono); font-size: 0.85rem; }
.treemap-reset { border: none; background: none; color: var(--color-primary); cursor: pointer; font-weight: 600; }
.treemap { position: absolute; inset: 48px 12px 12px; }
.treemap-tile {
    position: absolute;
    border: 1px solid rgba(255,255,255,0.65);
    border-radius: 0;
    padding: 0.25rem;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    overflow: hidden;
    font-size: 0.8rem;
    color: rgba(15, 23, 42, 0.8);
}
.tile-name { font-weight: 600; word-break: break-word; }
.tile-size { font-size: 0.75rem; color: var(--color-subtle); }

.insight-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
    gap: 1rem;
}
.insight-card {
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    padding: 1rem;
    background: var(--color-elevated);
}
.insight-category {
    display: inline-flex;
    padding: 0.2rem 0.75rem;
    border-radius: 999px;
    background: var(--color-primary-soft);
    color: var(--color-primary);
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-weight: 600;
}
.insight-text { margin-top: 0.5rem; }
.insight-subtips { margin-top: 0.75rem; padding-top: 0.5rem; border-top: 1px dashed var(--color-border); color: var(--color-muted); font-size: 0.9rem; }

.duplicate-panel {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 1rem;
    margin-bottom: 1.25rem;
}
.duplicate-card {
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    padding: 1rem;
    background: var(--color-elevated);
    box-shadow: var(--shadow-faint);
}
.duplicate-card-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 0.75rem;
    margin-bottom: 1rem;
}
.duplicate-eyebrow {
    margin: 0 0 0.25rem;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    font-size: 0.72rem;
    color: var(--color-subtle);
}
.duplicate-card h3 {
    margin: 0;
    font-size: 1.05rem;
    color: var(--color-text);
}
.duplicate-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
}
.duplicate-entry {
    border: 1px dashed var(--color-border);
    border-radius: var(--radius-sm);
    padding: 0.75rem;
    background: var(--color-surface);
}
.duplicate-entry-title {
    margin: 0 0 0.4rem;
    font-weight: 600;
    font-size: 0.95rem;
    color: var(--color-text);
}
.duplicate-paths {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 0.3rem;
    font-family: var(--font-mono);
    font-size: 0.85rem;
    word-break: break-all;
}
.duplicate-more {
    margin-top: 0.5rem;
    color: var(--color-muted);
    font-size: 0.85rem;
}
.ghost-button {
    display: inline-flex;
    align-items: center;
    border: 1px solid var(--color-border);
    border-radius: 999px;
    padding: 0.45rem 0.9rem;
    font-weight: 600;
    color: var(--color-text);
    text-decoration: none;
    background: transparent;
    white-space: nowrap;
}
.ghost-button:hover {
    background: var(--color-elevated);
}

.inventory-grid, .feature-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 1rem;
}
.inventory-card, .feature-card {
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    padding: 1rem;
    background: var(--color-elevated);
}
.inventory-card-header { margin-bottom: 0.75rem; display: flex; flex-direction: column; gap: 0.25rem; }
.inventory-card-header h3 { margin: 0; font-size: 1rem; }
.inventory-card-header span { color: var(--color-muted); font-size: 0.85rem; }
.tag-section { margin-top: 0.75rem; }
.tag-section h3 { margin: 0 0 0.35rem; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--color-subtle); }
.tag-list {
    list-style: none;
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem;
    padding: 0;
    margin: 0;
}
.tag, .library-tag {
    border-radius: 999px;
    padding: 0.2rem 0.65rem;
    font-size: 0.8rem;
    background: var(--color-muted-surface);
    color: var(--color-muted);
}
.library-tags { display: flex; flex-wrap: wrap; gap: 0.35rem; margin-top: 0.5rem; }
.type-pill { display: inline-flex; align-items: center; padding: 0.15rem 0.6rem; border-radius: 999px; background: var(--color-muted-surface); color: var(--color-subtle); font-size: 0.75rem; font-family: var(--font-mono); }
.library-tag.muted { background: transparent; color: var(--color-subtle); }
.manifest-pill {
    border-radius: 999px;
    padding: 0.2rem 0.6rem;
    font-size: 0.75rem;
    background: var(--color-elevated);
    color: var(--color-muted);
}
.manifest-pill.yes { background: rgba(13, 148, 136, 0.15); color: var(--color-positive); }

.feature-card-header { display: flex; justify-content: space-between; align-items: baseline; gap: 0.5rem; }
.feature-card-header h3 { margin: 0; font-size: 1rem; }
.feature-card-header span { color: var(--color-muted); font-size: 0.85rem; }
.feature-size { font-weight: 600; }
.feature-details { margin: 0.5rem 0 0; color: var(--color-muted); }

.platform-section { background: var(--color-surface); }

.comparison-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
    gap: 1rem;
}
.build-card {
    padding: 1.25rem;
    border-radius: var(--radius-sm);
    border: 1px solid var(--color-border);
    background: var(--color-elevated);
    box-shadow: var(--shadow-faint);
}
.build-card h3 { margin: 0 0 0.75rem; font-size: 1.1rem; }
.build-card dl {
    margin: 0;
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 0.4rem 0.75rem;
}
.build-card dt { font-weight: 600; color: var(--color-muted); }
.build-card dd { margin: 0; word-break: break-word; }

.narrative { margin: 0; padding-left: 1.25rem; color: var(--color-text); }
.narrative li { margin-bottom: 0.5rem; }

.empty-state {
    padding: 1.5rem;
    text-align: center;
    background: var(--color-elevated);
    border-radius: var(--radius-sm);
    color: var(--color-muted);
    border: 1px dashed var(--color-border);
}

.dashboard-footer {
    width: 100%;
    padding: 0 clamp(1.5rem, 4vw, 4rem) clamp(2rem, 3vw, 3.5rem);
    text-align: center;
    color: var(--color-subtle);
    font-size: 0.85rem;
}
.dashboard-footer p { margin: 0.3rem 0; word-break: break-word; }

@media (max-width: 720px) {
    .dashboard-header { padding: 1.5rem; }
    .meta-list { grid-template-columns: repeat(auto-fit, minmax(120px, 1fr)); }
    .section-controls { flex-direction: column; }
}
"""
}
