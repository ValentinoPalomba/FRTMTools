import Foundation

struct BuildLogReport {
    let status: String
    let schema: String?
    let buildIdentifier: String?
    let machineName: String?
    let duration: TimeInterval?
    let startTimestamp: Double?
    let endTimestamp: Double?
    let warningCount: Int
    let errorCount: Int
    let stepCount: Int
    let cacheRate: Double?
    let detailCacheRate: Double?
    let trackedDuration: TimeInterval
    let compilationDurationTotal: TimeInterval
    let parallelization: Double?
    let bottlenecks: [BuildLogStep]
    let categories: [BuildLogCategory]
    let targets: [BuildLogTarget]
    let scripts: [BuildLogScript]
    let gaps: [BuildLogGap]
    let warningSources: [BuildLogIssueSource]
    let errorSources: [BuildLogIssueSource]
    let swiftFunctions: [SwiftTiming]
    let swiftTypeChecks: [SwiftTiming]
    let swiftCompilations: [BuildLogStep]
    let warnings: [String]
    let errors: [String]
}

struct BuildLogStep {
    let title: String?
    let signature: String?
    let duration: TimeInterval?
    let compilationDuration: TimeInterval?
    let startTimestamp: Double?
    let endTimestamp: Double?
    let warningCount: Int
    let errorCount: Int
    let fetchedFromCache: Bool?
    let buildStatus: String?
    let stepType: String?
    let detailStepType: String?
    let schema: String?
    let buildIdentifier: String?
    let machineName: String?
    let detail: String?

    var displayName: String {
        if let signature, !signature.isEmpty { return signature }
        if let title, !title.isEmpty { return title }
        return "Unnamed Step"
    }
}

struct BuildLogCategory {
    let name: String
    let duration: TimeInterval
    let percent: Double
}

struct BuildLogTarget {
    let name: String
    let duration: TimeInterval?
    let compilationDuration: TimeInterval?
    let warningCount: Int
    let errorCount: Int
    let fetchedFromCache: Bool?
}

struct BuildLogScript {
    let name: String
    let duration: TimeInterval
    let detail: String?
}

struct BuildLogGap {
    let before: String
    let after: String
    let duration: TimeInterval
    let endTimestamp: Double
    let startTimestamp: Double
}

struct BuildLogIssueSource {
    let name: String
    let count: Int
}

struct SwiftTiming {
    let signature: String
    let file: String
    let durationMS: Double
    let occurrences: Int

    var totalDurationMS: Double {
        durationMS * Double(max(occurrences, 1))
    }
}

final class BuildLogReportParser {
    func parse(json: Any) -> BuildLogReport {
        var steps: [BuildLogStep] = []
        var warnings: [String] = []
        var errors: [String] = []
        var warningSet = Set<String>()
        var errorSet = Set<String>()
        var swiftFunctions: [SwiftTiming] = []
        var swiftTypeChecks: [SwiftTiming] = []

        collect(
            from: json,
            steps: &steps,
            warnings: &warnings,
            errors: &errors,
            warningSet: &warningSet,
            errorSet: &errorSet,
            swiftFunctions: &swiftFunctions,
            swiftTypeChecks: &swiftTypeChecks
        )

        let mainStep = steps.first { $0.stepType == "main" } ?? steps.first { $0.buildStatus != nil } ?? steps.first
        let status = mainStep?.buildStatus?.capitalized ?? "Unknown"
        let schema = mainStep?.schema
        let buildIdentifier = mainStep?.buildIdentifier
        let machineName = mainStep?.machineName

        let startTimestamp = steps.compactMap(\.startTimestamp).min()
        let endTimestamp = steps.compactMap(\.endTimestamp).max()
        let computedDuration: TimeInterval?
        if let startTimestamp, let endTimestamp, endTimestamp >= startTimestamp {
            computedDuration = endTimestamp - startTimestamp
        } else {
            computedDuration = mainStep?.duration
        }

        let warningCount = resolveAggregateCount(primary: mainStep?.warningCount, fallback: steps.map(\.warningCount).reduce(0, +))
        let errorCount = resolveAggregateCount(primary: mainStep?.errorCount, fallback: steps.map(\.errorCount).reduce(0, +))

        let trackedDuration = steps.compactMap(\.duration).reduce(0, +)
        let compilationDurationTotal = steps.compactMap(\.compilationDuration).reduce(0, +)
        let bottlenecks = steps
            .filter { ($0.duration ?? 0) > 0 }
            .filter { $0.stepType == "detail" || $0.stepType == nil }
            .sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
            .prefix(10)
            .map { $0 }

        let categories = summarizeCategories(from: steps, trackedDuration: trackedDuration)
        let cacheRate = computeCacheRate(from: steps)
        let detailCacheRate = computeCacheRate(from: steps.filter { $0.stepType == "detail" || $0.stepType == nil })
        let parallelization = computeParallelization(from: steps)
        let targets = buildTargets(from: steps)
        let scripts = buildScripts(from: steps)
        let gaps = buildGaps(from: steps)
        let warningSources = buildIssueSources(from: steps, keyPath: \.warningCount)
        let errorSources = buildIssueSources(from: steps, keyPath: \.errorCount)
        let swiftCompilations = steps.filter { $0.detailStepType == "swiftCompilation" }
            .sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }

        return BuildLogReport(
            status: status,
            schema: schema,
            buildIdentifier: buildIdentifier,
            machineName: machineName,
            duration: computedDuration,
            startTimestamp: startTimestamp,
            endTimestamp: endTimestamp,
            warningCount: warningCount,
            errorCount: errorCount,
            stepCount: steps.count,
            cacheRate: cacheRate,
            detailCacheRate: detailCacheRate,
            trackedDuration: trackedDuration,
            compilationDurationTotal: compilationDurationTotal,
            parallelization: parallelization,
            bottlenecks: bottlenecks,
            categories: categories,
            targets: targets,
            scripts: scripts,
            gaps: gaps,
            warningSources: warningSources,
            errorSources: errorSources,
            swiftFunctions: swiftFunctions.sorted { $0.totalDurationMS > $1.totalDurationMS },
            swiftTypeChecks: swiftTypeChecks.sorted { $0.totalDurationMS > $1.totalDurationMS },
            swiftCompilations: swiftCompilations,
            warnings: warnings,
            errors: errors
        )
    }

    private func resolveAggregateCount(primary: Int?, fallback: Int) -> Int {
        if let primary, primary > 0 {
            return primary
        }
        return fallback
    }

    private func computeCacheRate(from steps: [BuildLogStep]) -> Double? {
        let cacheFlags = steps.compactMap(\.fetchedFromCache)
        guard !cacheFlags.isEmpty else { return nil }
        let hitCount = cacheFlags.filter { $0 }.count
        return Double(hitCount) / Double(cacheFlags.count)
    }

    private func computeParallelization(from steps: [BuildLogStep]) -> Double? {
        let relevantSteps = steps
            .filter { $0.stepType == "detail" || $0.stepType == nil }
            .filter { ($0.duration ?? 0) > 0.01 }
            .compactMap { step -> (start: Double, end: Double)? in
                guard let start = step.startTimestamp, let end = step.endTimestamp else { return nil }
                return (start, end)
            }
        guard relevantSteps.count > 1 else { return 1.0 }
        let minTime = relevantSteps.map(\.start).min() ?? 0
        let maxTime = relevantSteps.map(\.end).max() ?? 0
        let totalDuration = maxTime - minTime
        guard totalDuration > 0 else { return 1.0 }

        let timeSlice = 0.1
        var currentTime = minTime
        var totalConcurrency: Double = 0
        var sliceCount: Double = 0

        while currentTime < maxTime {
            let sliceEnd = currentTime + timeSlice
            let activeSteps = relevantSteps.filter { $0.start < sliceEnd && $0.end > currentTime }.count
            totalConcurrency += Double(activeSteps)
            sliceCount += 1
            currentTime += timeSlice
        }
        return sliceCount > 0 ? totalConcurrency / sliceCount : 1.0
    }

    private func buildTargets(from steps: [BuildLogStep]) -> [BuildLogTarget] {
        let targets = steps.filter { $0.stepType == "target" }
        return targets.map { step in
            BuildLogTarget(
                name: step.displayName,
                duration: step.duration,
                compilationDuration: step.compilationDuration,
                warningCount: step.warningCount,
                errorCount: step.errorCount,
                fetchedFromCache: step.fetchedFromCache
            )
        }.sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
    }

    private func buildScripts(from steps: [BuildLogStep]) -> [BuildLogScript] {
        let scripts = steps.filter {
            $0.detailStepType == "scriptExecution" ||
            ($0.signature?.lowercased().contains("phasescriptexecution") ?? false)
        }
        return scripts.compactMap { step in
            guard let duration = step.duration else { return nil }
            return BuildLogScript(
                name: step.displayName,
                duration: duration,
                detail: step.detail
            )
        }.sorted { $0.duration > $1.duration }
    }

    private func buildGaps(from steps: [BuildLogStep]) -> [BuildLogGap] {
        let detailSteps = steps
            .filter { $0.stepType == "detail" || $0.stepType == nil }
            .compactMap { step -> (BuildLogStep, Double, Double)? in
                guard let start = step.startTimestamp, let end = step.endTimestamp, end > 0 else { return nil }
                return (step, start, end)
            }
            .sorted { $0.1 < $1.1 }
        guard detailSteps.count > 1 else { return [] }

        var gaps: [BuildLogGap] = []
        for index in 0..<(detailSteps.count - 1) {
            let current = detailSteps[index]
            let next = detailSteps[index + 1]
            let gap = next.1 - current.2
            if gap >= 5 {
                gaps.append(
                    BuildLogGap(
                        before: current.0.displayName,
                        after: next.0.displayName,
                        duration: gap,
                        endTimestamp: current.2,
                        startTimestamp: next.1
                    )
                )
            }
        }
        return gaps.sorted { $0.duration > $1.duration }
    }

    private func buildIssueSources(from steps: [BuildLogStep], keyPath: KeyPath<BuildLogStep, Int>) -> [BuildLogIssueSource] {
        let sources = steps.filter { $0[keyPath: keyPath] > 0 }
            .map { BuildLogIssueSource(name: $0.displayName, count: $0[keyPath: keyPath]) }
            .sorted { $0.count > $1.count }
        return Array(sources.prefix(8))
    }

    private func summarizeCategories(from steps: [BuildLogStep], trackedDuration: TimeInterval) -> [BuildLogCategory] {
        var totals: [String: TimeInterval] = [:]
        for step in steps {
            guard let duration = step.duration, duration > 0 else { continue }
            let category = categorize(step: step)
            totals[category, default: 0] += duration
        }
        let denominator = trackedDuration > 0 ? trackedDuration : totals.values.reduce(0, +)
        let categories = totals.map { name, duration in
            BuildLogCategory(
                name: name,
                duration: duration,
                percent: denominator > 0 ? duration / denominator : 0
            )
        }
        return categories.sorted { $0.duration > $1.duration }
    }

    private func categorize(step: BuildLogStep) -> String {
        if let detailType = step.detailStepType {
            switch detailType {
            case "swiftCompilation", "swiftAggregatedCompilation", "mergeSwiftModule":
                return "Swift Compile"
            case "cCompilation", "precompileBridgingHeader":
                return "C/ObjC Compile"
            case "linker", "createStaticLibrary":
                return "Linking"
            case "scriptExecution":
                return "Run Scripts"
            case "compileAssetsCatalog", "compileStoryboard", "linkStoryboards", "XIBCompilation":
                return "Assets & Storyboards"
            case "copySwiftLibs", "copyResourceFile", "writeAuxiliaryFile":
                return "Resources"
            default:
                break
            }
        }
        let name = "\(step.signature ?? "") \(step.title ?? "")".lowercased()
        if name.contains("compileswift") || name.contains("swiftdriver") || name.contains("swiftemit") {
            return "Swift Compile"
        }
        if name.contains("compilec") || name.contains("clang") {
            return "C/ObjC Compile"
        }
        if name.contains("link") || name.contains(" ld ") {
            return "Linking"
        }
        if name.contains("codesign") {
            return "Code Sign"
        }
        if name.contains("resource") || name.contains("copy") || name.contains("ibtool") {
            return "Resources"
        }
        if name.contains("test") {
            return "Tests"
        }
        if name.contains("analyze") {
            return "Analyze"
        }
        if name.contains("script") {
            return "Run Scripts"
        }
        return "Other"
    }

    private func collect(
        from node: Any,
        steps: inout [BuildLogStep],
        warnings: inout [String],
        errors: inout [String],
        warningSet: inout Set<String>,
        errorSet: inout Set<String>,
        swiftFunctions: inout [SwiftTiming],
        swiftTypeChecks: inout [SwiftTiming]
    ) {
        if let dict = node as? [String: Any] {
            if let step = parseStep(from: dict) {
                steps.append(step)
            }

            if let extracted = extractMessages(from: dict["warnings"]) {
                appendMessages(extracted, to: &warnings, set: &warningSet)
            }
            if let extracted = extractMessages(from: dict["errors"]) {
                appendMessages(extracted, to: &errors, set: &errorSet)
            }

            if let newItems = parseSwiftTimings(from: dict["swiftFunctionTimes"]) {
                swiftFunctions.append(contentsOf: newItems)
            }
            if let newItems = parseSwiftTimings(from: dict["swiftTypeCheckTimes"]) {
                swiftTypeChecks.append(contentsOf: newItems)
            }

            for value in dict.values {
                collect(
                    from: value,
                    steps: &steps,
                    warnings: &warnings,
                    errors: &errors,
                    warningSet: &warningSet,
                    errorSet: &errorSet,
                    swiftFunctions: &swiftFunctions,
                    swiftTypeChecks: &swiftTypeChecks
                )
            }
        } else if let array = node as? [Any] {
            for value in array {
                collect(
                    from: value,
                    steps: &steps,
                    warnings: &warnings,
                    errors: &errors,
                    warningSet: &warningSet,
                    errorSet: &errorSet,
                    swiftFunctions: &swiftFunctions,
                    swiftTypeChecks: &swiftTypeChecks
                )
            }
        }
    }

    private func appendMessages(_ messages: [String], to list: inout [String], set: inout Set<String>) {
        for message in messages {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !set.contains(trimmed) else { continue }
            list.append(trimmed)
            set.insert(trimmed)
        }
    }

    private func parseStep(from dict: [String: Any]) -> BuildLogStep? {
        let title = stringValue(from: dict, keys: ["title", "name", "sectionTitle"])
        let signature = stringValue(from: dict, keys: ["signature", "summaryString", "xcbuildSignature"])
        let duration = doubleValue(from: dict, keys: ["duration", "timeElapsed", "durationSeconds"])
        let compilationDuration = doubleValue(from: dict, keys: ["compilationDuration"])
        let startTimestamp = doubleValue(from: dict, keys: ["startTimestamp", "timeStartedRecording", "startTime"])
        let endTimestamp = doubleValue(from: dict, keys: ["endTimestamp", "timeStoppedRecording", "endTime"])
        let warningCount = intValue(from: dict, keys: ["warningCount", "warningsCount"])
        let errorCount = intValue(from: dict, keys: ["errorCount", "errorsCount"])
        let fetchedFromCache = boolValue(from: dict, keys: ["fetchedFromCache", "wasFetchedFromCache", "fromCache"])
        let buildStatus = stringValue(from: dict, keys: ["buildStatus", "status"])
        let stepType = stringValue(from: dict, keys: ["type"])
        let detailStepType = stringValue(from: dict, keys: ["detailStepType"])
        let schema = stringValue(from: dict, keys: ["schema"])
        let buildIdentifier = stringValue(from: dict, keys: ["buildIdentifier"])
        let machineName = stringValue(from: dict, keys: ["machineName"])
        let detail = stringValue(from: dict, keys: ["commandDetailDesc", "commandDetail", "documentURL", "location"])

        let hasSignal = title != nil || signature != nil || duration != nil || startTimestamp != nil || endTimestamp != nil || buildStatus != nil || stepType != nil
        guard hasSignal else { return nil }

        return BuildLogStep(
            title: title,
            signature: signature,
            duration: duration,
            compilationDuration: compilationDuration,
            startTimestamp: startTimestamp,
            endTimestamp: endTimestamp,
            warningCount: warningCount,
            errorCount: errorCount,
            fetchedFromCache: fetchedFromCache,
            buildStatus: buildStatus,
            stepType: stepType,
            detailStepType: detailStepType,
            schema: schema,
            buildIdentifier: buildIdentifier,
            machineName: machineName,
            detail: detail
        )
    }

    private func extractMessages(from value: Any?) -> [String]? {
        guard let value else { return nil }
        if let strings = value as? [String] {
            return strings
        }
        if let array = value as? [Any] {
            return array.compactMap { stringify($0) }
        }
        if let dict = value as? [String: Any] {
            if let message = stringify(dict) {
                return [message]
            }
        }
        if let string = value as? String {
            return [string]
        }
        return nil
    }

    private func parseSwiftTimings(from value: Any?) -> [SwiftTiming]? {
        guard let value else { return nil }
        guard let array = value as? [[String: Any]] else { return nil }
        return array.compactMap { entry in
            guard let signature = stringValue(from: entry, keys: ["signature"]) else { return nil }
            let file = stringValue(from: entry, keys: ["file"]) ?? "Unknown file"
            let durationMS = doubleValue(from: entry, keys: ["durationMS"]) ?? 0
            let occurrences = intValue(from: entry, keys: ["occurrences"])
            return SwiftTiming(signature: signature, file: file, durationMS: durationMS, occurrences: occurrences)
        }
    }

    private func stringify(_ value: Any) -> String? {
        if let string = value as? String {
            return string
        }
        if let dict = value as? [String: Any] {
            if let message = stringValue(from: dict, keys: ["message", "detail", "summary", "description", "reason", "title"]) {
                return message
            }
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        return nil
    }

    private func stringValue(from dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func doubleValue(from dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dict[key] as? Double {
                return value
            }
            if let value = dict[key] as? Int {
                return Double(value)
            }
            if let value = dict[key] as? String, let parsed = Double(value) {
                return parsed
            }
        }
        return nil
    }

    private func intValue(from dict: [String: Any], keys: [String]) -> Int {
        for key in keys {
            if let value = dict[key] as? Int {
                return value
            }
            if let value = dict[key] as? Double {
                return Int(value)
            }
            if let value = dict[key] as? String, let parsed = Int(value) {
                return parsed
            }
        }
        return 0
    }

    private func boolValue(from dict: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dict[key] as? Bool {
                return value
            }
            if let value = dict[key] as? String {
                if value.lowercased() == "true" { return true }
                if value.lowercased() == "false" { return false }
            }
        }
        return nil
    }
}

final class BuildLogDashboardHTMLBuilder {
    private let report: BuildLogReport
    private let sourceName: String
    private let sourcePath: String

    init(report: BuildLogReport, sourceName: String, sourcePath: String) {
        self.report = report
        self.sourceName = sourceName
        self.sourcePath = sourcePath
    }

    func build() -> String {
        let css = DashboardHTMLStyle.baseCSS + buildlogCSS
        let sidebar = renderSidebar()
        let header = renderHeader()
        let analysis = renderAnalysisSection()
        let overview = renderOverviewSection()
        let performance = renderPerformanceSection()
        let swift = renderSwiftHotspotsSection()
        let targets = renderTargetsSection()
        let issues = renderIssuesSection()

        return """
        <!doctype html>
        <html lang="en">
        <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>Build Report · \(sourceName.htmlEscaped)</title>
            <style>
            \(css)
            </style>
        </head>
        <body>
            <div class="dashboard-layout">
                \(sidebar)
                <main class="dashboard-main">
                    \(header)
                    <div class="section-stack">
                        \(analysis)
                        \(overview)
                        \(performance)
                        \(swift)
                        \(targets)
                        \(issues)
                    </div>
                </main>
            </div>
        </body>
        </html>
        """
    }

    private func renderSidebar() -> String {
        return """
        <aside class="dashboard-sidebar">
            <div class="nav-brand">
                <div class="nav-brand-icon buildlog">BL</div>
                <div>
                    <p class="nav-title">FRTMTools</p>
                    <p class="nav-subtitle">Build Log Report</p>
                </div>
            </div>
            <nav class="sidebar-nav">
                <ul>
                    <li><a href="#analysis">Analysis & Recommendations</a></li>
                    <li><a href="#overview">Build Overview</a></li>
                    <li><a href="#performance">Performance Hotspots</a></li>
                    <li><a href="#swift">Swift Slowdowns</a></li>
                    <li><a href="#targets">Target Performance</a></li>
                    <li><a href="#issues">Errors & Warnings</a></li>
                </ul>
            </nav>
            <footer class="sidebar-footer">
                <p>Generated by FRTMTools</p>
                <p>\(iso8601String(date: Date()))</p>
            </footer>
        </aside>
        """
    }

    private func renderHeader() -> String {
        let statusChip = statusBadge()
        return """
        <header class="dashboard-header">
            <div class="header-main">
                <div class="hero-text">
                    <p class="hero-eyebrow">Xcode Build Log Analysis</p>
                    <h1 class="hero-title">\(sourceName.htmlEscaped)</h1>
                    <p class="hero-subtitle">Source: \(sourcePath.htmlEscaped)</p>
                </div>
                <div class="header-meta">
                     \(statusChip)
                </div>
            </div>
        </header>
        """
    }
    
    private func renderAnalysisSection() -> String {
        let analysisPoints = generateAnalysisAndRecommendations()
        guard !analysisPoints.isEmpty else { return "" }
        let cards = analysisPoints.map { point in
            """
            <article class="analysis-card \(point.tone)">
                <div class="analysis-icon">\(point.icon)</div>
                <div class="analysis-content">
                    <h3 class="analysis-title">\(point.title.htmlEscaped)</h3>
                    <p class="analysis-finding"><strong>Finding:</strong> \(point.finding.htmlEscaped)</p>
                    <p class="analysis-recommendation"><strong>Recommendation:</strong> \(point.recommendation.htmlEscaped)</p>
                </div>
            </article>
            """
        }.joined(separator: "\n")
        
        return """
        <section id="analysis">
            <div class="section-header">
                <div>
                    <p class="section-eyebrow">Intelligence</p>
                    <h2>Analysis & Recommendations</h2>
                </div>
                <span class="section-subtitle">Actionable advice to improve your build performance and reliability.</span>
            </div>
            <div class="analysis-grid">
                \(cards)
            </div>
        </section>
        """
    }

    private func renderOverviewSection() -> String {
        let durationText = report.duration.map(formatDuration) ?? "n/a"
        let warningsText = NumberFormatter.localizedString(from: NSNumber(value: report.warningCount), number: .decimal)
        let errorsText = NumberFormatter.localizedString(from: NSNumber(value: report.errorCount), number: .decimal)
        let schemaText = report.schema ?? "n/a"
        let machineText = report.machineName ?? "n/a"
        let buildIdText = report.buildIdentifier ?? "n/a"

        return """
        <section id="overview">
            <div class="section-header">
                <div>
                    <p class="section-eyebrow">Summary</p>
                    <h2>Build Overview</h2>
                </div>
                <span class="section-subtitle">Key metrics and context for this build run.</span>
            </div>
            <div class="kpi-strip">
                \(kpiCard(title: "Total Duration", value: durationText, icon: "⏱️"))
                \(kpiCard(title: "Errors", value: errorsText, icon: "❌"))
                \(kpiCard(title: "Warnings", value: warningsText, icon: "⚠️"))
            </div>
            <div class="context-grid">
                \(contextCard(title: "Scheme", value: schemaText))
                \(contextCard(title: "Machine", value: machineText))
                \(contextCard(title: "Build ID", value: buildIdText))
            </div>
        </section>
        """
    }
    
    private func renderPerformanceSection() -> String {
        let cacheText = report.cacheRate.map { percentString($0) } ?? "n/a"
        let parallelizationText = report.parallelization.map { String(format: "%.1fx", $0) } ?? "n/a"
        let compilationShareText = compilationShareText()
        
        let bottleneckRows = report.bottlenecks.prefix(5).map { step in
            let durationValue = step.compilationDuration ?? step.duration
            let durationText = durationValue.map(formatDuration) ?? "n/a"
            return "<tr><td>\(step.displayName.htmlEscaped)</td><td>\(durationText)</td></tr>"
        }.joined(separator: "\n")

        let scriptRows = report.scripts.prefix(5).map { script in
            "<tr><td>\(script.name.htmlEscaped)</td><td>\(formatDuration(script.duration))</td></tr>"
        }.joined(separator: "\n")
        
        return """
        <section id="performance">
            <div class="section-header">
                <div>
                    <p class="section-eyebrow">Performance</p>
                    <h2>Performance Hotspots</h2>
                </div>
                <span class="section-subtitle">Identify the primary drivers of long build times.</span>
            </div>
            <div class="kpi-strip">
                \(kpiCard(title: "Cache Hit Rate", value: cacheText, icon: "🎯"))
                \(kpiCard(title: "Parallelization", value: parallelizationText, icon: "🚦"))
                \(kpiCard(title: "Compile Share", value: compilationShareText, icon: "⚙️"))
            </div>
            <div class="table-grid">
                <div class="table-container">
                    <h3>Slowest Build Steps</h3>
                    <div class="table-wrapper">
                        <table>
                            <thead><tr><th>Step</th><th>Duration</th></tr></thead>
                            <tbody>\(bottleneckRows)</tbody>
                        </table>
                    </div>
                </div>
                <div class="table-container">
                    <h3>Slowest Build Scripts</h3>
                    <div class="table-wrapper">
                        <table>
                            <thead><tr><th>Script</th><th>Duration</th></tr></thead>
                            <tbody>\(scriptRows)</tbody>
                        </table>
                    </div>
                </div>
            </div>
        </section>
        """
    }
    
    private func renderSwiftHotspotsSection() -> String {
        let topFunctions = report.swiftFunctions.prefix(5)
        let topTypeChecks = report.swiftTypeChecks.prefix(5)
        let topCompilations = report.swiftCompilations.prefix(5)
        guard !topFunctions.isEmpty || !topTypeChecks.isEmpty || !topCompilations.isEmpty else { return "" }

        let functionRows = topFunctions.map { "<tr><td>\($0.signature.htmlEscaped)</td><td>\(formatDuration($0.totalDurationMS / 1000.0))</td></tr>" }.joined(separator: "\n")
        let typeCheckRows = topTypeChecks.map { "<tr><td>\($0.signature.htmlEscaped)</td><td>\(formatDuration($0.totalDurationMS / 1000.0))</td></tr>" }.joined(separator: "\n")
        let compilationRows = topCompilations.map { "<tr><td>\($0.displayName.htmlEscaped)</td><td>\(formatDuration($0.duration ?? 0))</td></tr>" }.joined(separator: "\n")

        return """
        <section id="swift">
            <div class="section-header">
                <div>
                    <p class="section-eyebrow">Swift Compiler</p>
                    <h2>Swift Slowdowns</h2>
                </div>
                <span class="section-subtitle">Pinpoint slow functions, type checks, and file compilations.</span>
            </div>
            <div class="table-grid">
                <div class="table-container"><h3>Slowest Functions</h3><div class="table-wrapper"><table><thead><tr><th>Function</th><th>Time</th></tr></thead><tbody>\(functionRows)</tbody></table></div></div>
                <div class="table-container"><h3>Slowest Type Checks</h3><div class="table-wrapper"><table><thead><tr><th>Expression</th><th>Time</th></tr></thead><tbody>\(typeCheckRows)</tbody></table></div></div>
                <div class="table-container"><h3>Slowest File Compiles</h3><div class="table-wrapper"><table><thead><tr><th>File</th><th>Time</th></tr></thead><tbody>\(compilationRows)</tbody></table></div></div>
            </div>
        </section>
        """
    }

    private func renderTargetsSection() -> String {
        guard !report.targets.isEmpty else { return "" }
        let rows = report.targets.prefix(8).map { target in
            let durationText = target.duration.map(formatDuration) ?? "n/a"
            let compilationText = target.compilationDuration.map(formatDuration) ?? "n/a"
            let warnings = target.warningCount > 0 ? "\(target.warningCount)" : "-"
            let errors = target.errorCount > 0 ? "\(target.errorCount)" : "-"
            return "<tr><td>\(target.name.htmlEscaped)</td><td>\(durationText)</td><td>\(compilationText)</td><td>\(errors)</td><td>\(warnings)</td></tr>"
        }.joined(separator: "\n")

        return """
        <section id="targets">
            <div class="section-header">
                <div>
                    <p class="section-eyebrow">Structure</p>
                    <h2>Target Performance</h2>
                </div>
                <span class="section-subtitle">Analyze the build time contribution of each target.</span>
            </div>
            <div class="table-container full-width">
                <div class="table-wrapper">
                    <table>
                        <thead><tr><th>Target</th><th>Total Time</th><th>Compile Time</th><th>Errors</th><th>Warnings</th></tr></thead>
                        <tbody>\(rows)</tbody>
                    </table>
                </div>
            </div>
        </section>
        """
    }
    
    private func renderIssuesSection() -> String {
        let warningItems = report.warnings.prefix(5)
        let errorItems = report.errors.prefix(5)
        guard !warningItems.isEmpty || !errorItems.isEmpty else { return "" }

        let warningMarkup = renderIncidentCard(title: "Warnings", count: report.warningCount, items: Array(warningItems), tone: "warning")
        let errorMarkup = renderIncidentCard(title: "Errors", count: report.errorCount, items: Array(errorItems), tone: "negative")

        return """
        <section id="issues">
            <div class="section-header">
                <div>
                    <p class="section-eyebrow">Quality</p>
                    <h2>Errors & Warnings</h2>
                </div>
                <span class="section-subtitle">A summary of the most critical issues found during the build.</span>
            </div>
            <div class="incident-grid">
                \(errorMarkup)
                \(warningMarkup)
            </div>
        </section>
        """
    }

    private func renderIncidentCard(title: String, count: Int, items: [String], tone: String) -> String {
        guard !items.isEmpty else { return "" }
        let listItems = items.map { "<li>\($0.htmlEscaped)</li>" }.joined(separator: "\n")
        let countText = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
        return """
        <article class="incident-card \(tone)">
            <h3>\(title) (\(countText) total)</h3>
            <ul>\(listItems)</ul>
        </article>
        """
    }

    private func kpiCard(title: String, value: String, icon: String) -> String {
        return """
        <div class="kpi-card">
            <div class="kpi-icon">\(icon)</div>
            <div class="kpi-content">
                <div class="kpi-title">\(title.htmlEscaped)</div>
                <div class="kpi-value">\(value.htmlEscaped)</div>
            </div>
        </div>
        """
    }

    private func contextCard(title: String, value: String) -> String {
        return "<div class=\"context-card\"><strong>\(title.htmlEscaped):</strong> <span>\(value.htmlEscaped)</span></div>"
    }

    private func statusBadge() -> String {
        let status = report.status.lowercased()
        let tone: String
        let text: String
        if status.contains("success") {
            tone = "positive"
            text = "Build Succeeded"
        } else if status.contains("fail") || status.contains("error") {
            tone = "negative"
            text = "Build Failed"
        } else {
            tone = "warning"
            text = "Build Succeeded with Issues"
        }
        return "<span class=\"status-badge \(tone)\">\(text.htmlEscaped)</span>"
    }
    
    private func generateAnalysisAndRecommendations() -> [AnalysisPoint] {
        var points: [AnalysisPoint] = []
        
        if report.errorCount > 0 {
            points.append(AnalysisPoint(
                category: "Reliability",
                icon: "❌",
                title: "Build Failed",
                finding: "The build failed with \(report.errorCount) errors.",
                recommendation: "Fix all build errors to produce a successful build. The errors are listed in the 'Errors & Warnings' section below.",
                tone: "negative"
            ))
        }

        if let cacheRate = report.cacheRate, cacheRate < 0.5 {
            points.append(AnalysisPoint(
                category: "Performance",
                icon: "🎯",
                title: "Low Cache Hit Rate",
                finding: "The overall cache hit rate is only \(percentString(cacheRate)). A significant portion of the build is not leveraging cached results.",
                recommendation: "Investigate why incremental build caching is being invalidated. Check build script input/output files, file timestamps, and Xcode's build settings.",
                tone: "warning"
            ))
        }
        
        if let parallelization = report.parallelization, parallelization < 2.0 {
            points.append(AnalysisPoint(
                category: "Performance",
                icon: "🚦",
                title: "Low Parallelization",
                finding: "The build is executing with an average of only \(String(format: "%.1f", parallelization)) tasks in parallel.",
                recommendation: "A low parallelization level often indicates sequential dependencies between targets. Review your project's target dependency graph to identify and decouple targets that could be built concurrently.",
                tone: "warning"
            ))
        }
        
        if let slowestScript = report.scripts.first {
            let scriptShare = slowestScript.duration / (report.duration ?? 1.0)
            if scriptShare > 0.1 {
                points.append(AnalysisPoint(
                    category: "Performance",
                    icon: "📜",
                    title: "Slow Build Script",
                    finding: "The script '\(slowestScript.name)' is taking \(formatDuration(slowestScript.duration)), which accounts for \(percentString(scriptShare)) of the total build time.",
                    recommendation: "Optimize this script. Consider making it incremental, moving its logic into compiled Swift/Obj-C code, or using more efficient tools.",
                    tone: "warning"
                ))
            }
        }
        
        if let slowestFunc = report.swiftFunctions.first {
            points.append(AnalysisPoint(
                category: "Swift",
                icon: "🐢",
                title: "Slow Swift Function Compilation",
                finding: "The function `\(slowestFunc.signature)` is taking a long time for the compiler to process.",
                recommendation: "Simplify the function body, break it into smaller helper functions, or add explicit type annotations to reduce the work for the type checker.",
                tone: "default"
            ))
        }

        if let slowestTypeCheck = report.swiftTypeChecks.first {
            points.append(AnalysisPoint(
                category: "Swift",
                icon: "🤔",
                title: "Complex Type Inference",
                finding: "An expression involving `\(slowestTypeCheck.signature)` requires significant time for type checking.",
                recommendation: "Add explicit type annotations for this variable or expression to speed up the compiler.",
                tone: "default"
            ))
        }
        
        if report.warningCount > 50 {
            points.append(AnalysisPoint(
                category: "Quality",
                icon: "⚠️",
                title: "Excessive Warnings",
                finding: "The project generated \(report.warningCount) warnings.",
                recommendation: "While not breaking the build, a large number of warnings can hide critical issues and slow down the compiler. Aim to fix warnings incrementally.",
                tone: "warning"
            ))
        }

        return points
    }

    private func formatDuration(_ totalSeconds: TimeInterval) -> String {
        guard totalSeconds.isFinite, totalSeconds >= 0 else { return "n/a" }

        if totalSeconds < 0.001 { // Less than 1 millisecond
            return "<1ms"
        } else if totalSeconds < 1.0 { // Less than 1 second, show in ms
            return "\(Int(totalSeconds * 1000))ms"
        } else if totalSeconds < 60.0 { // Less than 1 minute, show with one decimal for seconds
            return String(format: "%.1fs", totalSeconds)
        }

        let secondsInt = Int(totalSeconds.rounded()) // Round to nearest second for higher units
        let days = secondsInt / 86400
        let hours = (secondsInt % 86400) / 3600
        let minutes = (secondsInt % 3600) / 60
        let seconds = secondsInt % 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if seconds > 0 || parts.isEmpty { // Always show seconds if nothing else has been added yet, or if seconds are > 0
            parts.append("\(seconds)s")
        }

        return parts.joined(separator: " ")
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func percentString(_ value: Double) -> String {
        let clamped = max(0, min(1, value))
        let percent = clamped * 100
        return String(format: "%.0f%%", percent)
    }

    private func compilationShare() -> Double? {
        guard let duration = report.duration, duration > 0 else { return nil }
        let share = report.compilationDurationTotal / duration
        return max(0, min(1, share))
    }

    private func compilationShareText() -> String {
        guard let share = compilationShare() else { return "n/a" }
        return percentString(share)
    }

    private func iso8601String(date: Date, format: ISO8601DateFormatter.Options = [.withInternetDateTime]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = format
        return formatter.string(from: date)
    }
    
    private struct AnalysisPoint {
        let category: String
        let icon: String
        let title: String
        let finding: String
        let recommendation: String
        let tone: String
    }

    private let buildlogCSS = """
    :root {
        --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        --radius: 12px;
        --color-accent: #007aff;
        --color-accent-g: linear-gradient(45deg, #007aff, #5856d6);
        --c-text: #111;
        --c-text-muted: #555;
        --c-bg: #f8f9fa;
        --c-surface: #fff;
        --c-border: #e9ecef;
        --c-positive: #28a745;
        --c-negative: #dc3545;
        --c-warning: #fd7e14;
        --shadow: 0 4px 6px rgba(0,0,0,0.04);
    }
    @media (prefers-color-scheme: dark) {
        :root {
            --c-text: #e0e0e0;
            --c-text-muted: #a0a0a0;
            --c-bg: #1e1e1e;
            --c-surface: #2d2d2d;
            --c-border: #3c3c3c;
            --c-positive: #34c759;
            --c-negative: #ff3b30;
            --c-warning: #ff9500;
            --shadow: 0 4px 6px rgba(0,0,0,0.2);
        }
    }

    body {
        margin: 0;
        font-family: var(--font-sans);
        -webkit-font-smoothing: antialiased;
        -moz-osx-font-smoothing: grayscale;
        color: var(--c-text);
        background-color: var(--c-bg);
    }

    .dashboard-layout { display: flex; background-color: var(--c-bg); color: var(--c-text); }
    .dashboard-sidebar {
        width: 280px;
        flex-shrink: 0;
        height: 100vh;
        position: sticky;
        top: 0;
        background: var(--c-surface);
        border-right: 1px solid var(--c-border);
        display: flex;
        flex-direction: column;
        padding: 1.5rem;
    }
    .nav-brand { display: flex; align-items: center; gap: 0.75rem; padding-bottom: 1.5rem; }
    .nav-brand-icon.buildlog {
        width: 42px; height: 42px;
        border-radius: var(--radius);
        background: var(--color-accent-g);
        color: white;
        display: grid;
        place-items: center;
        font-weight: 700;
        font-size: 1.1rem;
    }
    .nav-title { font-weight: 600; font-size: 1rem; margin:0; }
    .nav-subtitle { font-size: 0.85rem; color: var(--c-text-muted); margin:0; }
    .sidebar-nav { flex-grow: 1; }
    .sidebar-nav ul { list-style: none; padding: 0; margin: 0; }
    .sidebar-nav li a {
        display: block;
        padding: 0.75rem 1rem;
        border-radius: 8px;
        color: var(--c-text-muted);
        text-decoration: none;
        font-weight: 500;
        font-size: 0.9rem;
        transition: all 0.2s ease;
    }
    .sidebar-nav li a:hover { background-color: var(--c-bg); color: var(--c-text); }
    .sidebar-footer { font-size: 0.75rem; color: var(--c-text-muted); padding-top: 1rem; border-top: 1px solid var(--c-border); margin-top: 1rem;}
    .sidebar-footer p { margin: 0.25rem 0; }
    .dashboard-main { flex-grow: 1; padding: 2rem 3rem; }
    .dashboard-header {
        padding-bottom: 2rem;
        border-bottom: 1px solid var(--c-border);
        margin-bottom: 2rem;
    }
    .header-main { display: flex; justify-content: space-between; align-items: flex-start; }
    .hero-eyebrow { color: var(--c-text-muted); font-size: 0.9rem; margin: 0 0 0.5rem; }
    .hero-title { font-size: 2.5rem; font-weight: 700; margin: 0 0 0.5rem; }
    .hero-subtitle { font-size: 1.1rem; color: var(--c-text-muted); margin: 0; }
    .status-badge { font-size: 0.9rem; font-weight: 600; padding: 0.5rem 1rem; border-radius: 99px; }
    .status-badge.positive { background-color: #eaf6ec; color: var(--c-positive); }
    .status-badge.negative { background-color: #fdecea; color: var(--c-negative); }
    .status-badge.warning { background-color: #fff4e7; color: var(--c-warning); }
    @media (prefers-color-scheme: dark) {
        .status-badge.positive { background-color: #1e3a24; }
        .status-badge.negative { background-color: #4b1a1f; }
        .status-badge.warning { background-color: #4d330f; }
    }

    section { margin-bottom: 3rem; }
    .section-header { margin-bottom: 1.5rem; }
    .section-eyebrow { color: var(--color-accent); font-weight: 600; margin: 0 0 0.5rem; font-size: 0.9rem; }
    .section-header h2 { font-size: 1.75rem; margin: 0; }
    .section-subtitle { color: var(--c-text-muted); font-size: 1rem; }
    .analysis-grid { display: grid; grid-template-columns: 1fr; gap: 1rem; }
    .analysis-card {
        background: var(--c-surface);
        border: 1px solid var(--c-border);
        border-radius: var(--radius);
        padding: 1.5rem;
        display: flex;
        gap: 1.5rem;
        align-items: flex-start;
        box-shadow: var(--shadow);
    }
    .analysis-card.warning { border-left: 4px solid var(--c-warning); }
    .analysis-card.negative { border-left: 4px solid var(--c-negative); }
    .analysis-card.default { border-left: 4px solid var(--color-accent); }
    .analysis-icon { font-size: 1.5rem; }
    .analysis-content { flex-grow: 1; }
    .analysis-title { margin: 0 0 0.75rem; font-size: 1.1rem; }
    .analysis-finding, .analysis-recommendation { margin: 0.25rem 0; font-size: 0.95rem; color: var(--c-text-muted); line-height: 1.6; }
    .analysis-finding strong, .analysis-recommendation strong { color: var(--c-text); }
    .kpi-strip { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 1rem; }
    .kpi-card {
        background: var(--c-surface);
        border-radius: var(--radius);
        border: 1px solid var(--c-border);
        padding: 1.5rem;
        display: flex;
        align-items: center;
        gap: 1rem;
        box-shadow: var(--shadow);
    }
    .kpi-icon { font-size: 1.75rem; }
    .kpi-content { flex-grow: 1; }
    .kpi-title { font-size: 0.85rem; color: var(--c-text-muted); margin: 0; }
    .kpi-value { font-size: 1.5rem; font-weight: 700; margin: 0; }
    .context-grid { display: flex; flex-wrap: wrap; gap: 1.5rem; background: var(--c-surface); border: 1px solid var(--c-border); border-radius: var(--radius); padding: 1rem 1.5rem; }
    .context-card { font-size: 0.9rem; color: var(--c-text-muted); }
    .context-card strong { color: var(--c-text); }
    .table-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 2rem; }
    .table-container h3 { font-size: 1.1rem; margin-bottom: 1rem; }
    .table-container.full-width { grid-column: 1 / -1; }
    .table-wrapper {
        background: var(--c-surface);
        border: 1px solid var(--c-border);
        border-radius: var(--radius);
        overflow: hidden;
        box-shadow: var(--shadow);
    }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: 1rem; text-align: left; border-bottom: 1px solid var(--c-border); }
    thead { background-color: var(--c-bg); }
    th { font-size: 0.85rem; font-weight: 600; color: var(--c-text-muted); }
    tbody tr:last-child td { border-bottom: none; }
    td { font-size: 0.9rem; }
    .incident-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1rem; }
    .incident-card { background: var(--c-surface); border: 1px solid var(--c-border); border-radius: var(--radius); padding: 1.5rem; box-shadow: var(--shadow); }
    .incident-card.warning { border-top: 4px solid var(--c-warning); }
    .incident-card.negative { border-top: 4px solid var(--c-negative); }
    .incident-card h3 { margin: 0 0 1rem; font-size: 1.1rem; }
    .incident-card ul { list-style: none; padding: 0; margin: 0; font-family: "SF Mono", "Menlo", monospace; font-size: 0.85rem; }
    .incident-card li { padding: 0.5rem; border-radius: 6px; }
    .incident-card li:nth-child(odd) { background-color: var(--c-bg); }
    """
}
