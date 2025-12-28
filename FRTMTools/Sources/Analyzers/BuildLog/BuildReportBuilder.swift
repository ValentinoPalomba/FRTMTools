import Foundation

final class BuildReportBuilder {
    func buildReport(from graph: BuildGraph, insights: [BuildInsight]) -> BuildReport {
        let analysis = BuildAnalysis(graph: graph)
        let summary = BuildReport.Summary(
            totalDuration: graph.wallClockDuration,
            criticalPathDuration: analysis.criticalPath.duration,
            parallelism: analysis.parallelism,
            cacheHitRate: analysis.cacheHitRate,
            buildHealthScore: buildHealthScore(from: analysis)
        )
        let overviewSections = buildOverviewSections(from: graph, analysis: analysis)

        let targetSummaries = graph.targets.map { target in
            let stepTimeline = buildTimeline(for: target)
            let typeBreakdown = buildStepTypeBreakdown(for: target)
            let parallelism = analysis.perTargetParallelism[target.name] ?? 0
            let isBottleneck = analysis.criticalPath.targets.contains(target.name) &&
                target.totalDuration >= (analysis.criticalPath.duration * 0.2)
            let targetInsights = insights.filter { $0.relatedTargets.contains(target.name) }

            return BuildReport.TargetSummary(
                id: target.name,
                name: target.name,
                duration: target.totalDuration,
                fanIn: target.dependencies.count,
                fanOut: target.dependents.count,
                isBottleneck: isBottleneck,
                dependencies: target.dependencies.sorted(),
                dependents: target.dependents.sorted(),
                parallelism: parallelism,
                stepTimeline: stepTimeline,
                stepTypeBreakdown: typeBreakdown,
                insights: targetInsights
            )
        }
        .sorted { $0.duration > $1.duration }

        let targetDurationPoints = targetSummaries.map {
            BuildReport.ChartPoint(id: $0.id, label: $0.name, value: $0.duration)
        }

        let targetParallelismPoints = targetSummaries.map {
            BuildReport.ChartPoint(id: $0.id, label: $0.name, value: $0.parallelism)
        }

        let stepTypeTotals = analysis.stepTypeTotals
            .map { BuildReport.ChartPoint(id: $0.key, label: $0.key, value: $0.value) }
            .sorted { $0.value > $1.value }

        let charts = BuildReport.Charts(
            targetDurations: targetDurationPoints,
            targetParallelism: targetParallelismPoints,
            stepTypeTotals: stepTypeTotals
        )

        return BuildReport(
            summary: summary,
            overviewSections: overviewSections,
            issueSummaries: buildIssueSummaries(from: insights),
            targets: targetSummaries,
            insights: insights,
            charts: charts,
            aiFixes: nil
        )
    }

    private func buildHealthScore(from analysis: BuildAnalysis) -> Double {
        var score = 100.0

        let parallelismPenalty = max(0, 1.5 - analysis.parallelism) * 20.0
        let cachePenalty = max(0, 0.7 - analysis.cacheHitRate) * 50.0
        let criticalPathRatio = analysis.graph.wallClockDuration > 0
            ? analysis.criticalPath.duration / analysis.graph.wallClockDuration
            : 0
        let criticalPenalty = max(0, criticalPathRatio - 0.7) * 60.0

        score -= parallelismPenalty
        score -= cachePenalty
        score -= criticalPenalty

        return min(100, max(0, score))
    }

    private func buildTimeline(for target: TargetNode) -> [BuildReport.StepTimelineItem] {
        guard let targetStart = target.startTimestamp else { return [] }
        return target.steps.compactMap { step in
            guard let stepStart = step.startTimestamp, let stepEnd = step.endTimestamp else { return nil }
            let startOffset = max(0, stepStart - targetStart)
            let endOffset = max(startOffset, stepEnd - targetStart)
            let label = BuildAnalysis.stepTypeLabel(for: step)
            return BuildReport.StepTimelineItem(
                id: step.id,
                title: step.title ?? label,
                typeLabel: label,
                startOffset: startOffset,
                endOffset: endOffset,
                duration: max(0, step.effectiveDuration),
                fetchedFromCache: step.fetchedFromCache,
                noteSummary: summarizeNotes(step.notes)
            )
        }
    }

    private func buildStepTypeBreakdown(for target: TargetNode) -> [BuildReport.StepTypeBreakdown] {
        var totals: [String: Double] = [:]
        for step in target.steps {
            let label = normalizedBreakdownLabel(for: step)
            totals[label, default: 0] += max(0, step.effectiveDuration)
        }

        return totals.map {
            BuildReport.StepTypeBreakdown(id: $0.key, label: $0.key, duration: $0.value)
        }
        .sorted { $0.duration > $1.duration }
    }

    private func summarizeNotes(_ notes: [String]) -> String? {
        let cleaned = notes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        let unique = Array(NSOrderedSet(array: cleaned)) as? [String] ?? cleaned
        return unique.prefix(2).joined(separator: " | ")
    }

    private func normalizedBreakdownLabel(for step: BuildStepNode) -> String {
        if let detail = step.detailType, detail != .none, detail != .other {
            return detail.rawValue
        }
        return step.type.rawValue
    }

    private func buildOverviewSections(from graph: BuildGraph, analysis: BuildAnalysis) -> [BuildReport.OverviewSection] {
        var sections: [BuildReport.OverviewSection] = []

        let summaryLine = "Build took \(formatSeconds(graph.wallClockDuration)). Critical path \(formatSeconds(analysis.criticalPath.duration)). Parallelism \(String(format: "%.2fx", analysis.parallelism)). Cache hit rate \(String(format: "%.0f%%", analysis.cacheHitRate * 100))."
        sections.append(
            BuildReport.OverviewSection(
                title: "Build Summary",
                lines: [summaryLine]
            )
        )

        let targetLines = graph.targets
            .sorted { $0.totalDuration > $1.totalDuration }
            .map { target in
                let parallelism = analysis.perTargetParallelism[target.name] ?? 0
                return "\(target.name): \(formatSeconds(target.totalDuration)), fan-out \(target.dependents.count), parallelism \(String(format: "%.2fx", parallelism))"
            }

        if !targetLines.isEmpty {
            sections.append(
                BuildReport.OverviewSection(
                    title: "Primary Bottlenecks",
                    lines: targetLines
                )
            )
        }

        let stepTypeLines = analysis.stepTypeTotals
            .sorted { $0.value > $1.value }
            .map { "\(formatStepLabel($0.key)): \(formatSeconds($0.value))" }

        if !stepTypeLines.isEmpty {
            sections.append(
                BuildReport.OverviewSection(
                    title: "Serial Work / Step Types",
                    lines: stepTypeLines
                )
            )
        }

        let criticalPathLine: String
        if analysis.criticalPath.targets.isEmpty {
            criticalPathLine = "No critical path data available."
        } else {
            let path = analysis.criticalPath.targets.joined(separator: " → ")
            criticalPathLine = "Critical path: \(path). Minimum build time \(formatSeconds(analysis.criticalPath.duration))."
        }
        sections.append(
            BuildReport.OverviewSection(
                title: "Critical Path",
                lines: [criticalPathLine]
            )
        )

        let totalWarnings = graph.allSteps.map { $0.warningCount }.reduce(0, +)
        let totalErrors = graph.allSteps.map { $0.errorCount }.reduce(0, +)
        let totalNotes = graph.allSteps.map { $0.notes.count }.reduce(0, +)

        let diagnosticLine = "Warnings \(totalWarnings), errors \(totalErrors), notes \(totalNotes)."
        sections.append(
            BuildReport.OverviewSection(
                title: "Warnings / Notes",
                lines: [diagnosticLine]
            )
        )

        return sections
    }

    private func buildIssueSummaries(from insights: [BuildInsight]) -> [BuildReport.IssueSummary] {
        insights.map { insight in
            BuildReport.IssueSummary(
                title: insight.title,
                explanation: insight.explanation,
                suggestion: insight.suggestion,
                severity: insight.severity,
                relatedTargets: insight.relatedTargets,
                estimatedImpactSeconds: insight.estimatedImpactSeconds
            )
        }
    }

    private func formatStepLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "swift", with: "Swift")
            .replacingOccurrences(of: "cCompilation", with: "C Compilation")
            .replacingOccurrences(of: "XIBCompilation", with: "XIB Compilation")
    }

    private func formatSeconds(_ seconds: Double) -> String {
        String(format: "%.2fs", seconds)
    }
}
