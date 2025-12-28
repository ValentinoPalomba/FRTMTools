import Foundation

final class BuildInsightEngine {
    func generateInsights(from graph: BuildGraph) -> [BuildInsight] {
        let analysis = BuildAnalysis(graph: graph)
        var insights: [BuildInsight] = []

        insights.append(contentsOf: highFanOutSlowTargets(graph: graph, analysis: analysis))
        if let stepTypeInsight = dominantStepTypeInsight(analysis: analysis) {
            insights.append(stepTypeInsight)
        }
        if let criticalPathInsight = criticalPathDominanceInsight(graph: graph, analysis: analysis) {
            insights.append(criticalPathInsight)
        }
        if let lowParallelismInsight = lowParallelismInsight(analysis: analysis) {
            insights.append(lowParallelismInsight)
        }
        if let lowCacheInsight = lowCacheHitRateInsight(analysis: analysis) {
            insights.append(lowCacheInsight)
        }
        if let swiftHotspotInsight = swiftTypeCheckHotspotInsight(analysis: analysis) {
            insights.append(swiftHotspotInsight)
        }

        return insights.sorted { lhs, rhs in
            severityRank(lhs.severity) > severityRank(rhs.severity)
        }
    }

    private func severityRank(_ severity: BuildInsight.Severity) -> Int {
        switch severity {
        case .critical: return 3
        case .warning: return 2
        case .info: return 1
        }
    }

    private func highFanOutSlowTargets(graph: BuildGraph, analysis: BuildAnalysis) -> [BuildInsight] {
        let threshold = max(1.0, graph.wallClockDuration * 0.15)
        let candidates = graph.targets.filter {
            $0.dependents.count >= 3 && $0.totalDuration >= threshold
        }

        return candidates.prefix(3).map { target in
            BuildInsight(
                severity: .warning,
                title: "High fan-out target: \(target.name)",
                explanation: "\(target.name) fans out to \(target.dependents.count) targets and takes \(formatSeconds(target.totalDuration)). This can serialize downstream work.",
                suggestion: "Consider splitting \(target.name) or reducing its dependencies to unlock more parallelism.",
                confidence: 0.62,
                relatedTargets: [target.name],
                estimatedImpactSeconds: target.totalDuration * 0.2
            )
        }
    }

    private func criticalPathDominanceInsight(graph: BuildGraph, analysis: BuildAnalysis) -> BuildInsight? {
        guard graph.wallClockDuration > 0 else { return nil }
        let ratio = analysis.criticalPath.duration / graph.wallClockDuration
        guard ratio >= 0.7 else { return nil }

        let impact = max(0, graph.wallClockDuration - analysis.criticalPath.duration)
        return BuildInsight(
            severity: ratio > 0.85 ? .critical : .warning,
            title: "Critical path dominates the build",
            explanation: "The critical path accounts for \(Int(ratio * 100))% of total build time. Parallel work has limited impact while this path is long.",
            suggestion: "Shorten steps on the critical path or split the heaviest target to reduce the minimum build time.",
            confidence: 0.74,
            relatedTargets: analysis.criticalPath.targets,
            estimatedImpactSeconds: impact
        )
    }

    private func lowParallelismInsight(analysis: BuildAnalysis) -> BuildInsight? {
        guard analysis.graph.wallClockDuration > 0 else { return nil }
        guard analysis.parallelism > 0, analysis.parallelism < 1.5 else { return nil }

        return BuildInsight(
            severity: .warning,
            title: "Low parallelism",
            explanation: "Overall parallelism is \(String(format: "%.2f", analysis.parallelism))x. The build is mostly serialized.",
            suggestion: "Break large targets into smaller modules or enable more parallel tasks to increase throughput.",
            confidence: 0.68,
            relatedTargets: []
        )
    }

    private func lowCacheHitRateInsight(analysis: BuildAnalysis) -> BuildInsight? {
        guard !analysis.graph.allSteps.isEmpty, analysis.cacheHitRate < 0.6 else { return nil }

        let killers = analysis.cacheKillers.prefix(3).map { "\($0.title) (\(formatSeconds($0.duration)))" }
        let killersSummary = killers.isEmpty ? "" : " Top offenders: \(killers.joined(separator: ", "))."

        return BuildInsight(
            severity: analysis.cacheHitRate < 0.4 ? .critical : .warning,
            title: "Low cache hit rate",
            explanation: "Only \(Int(analysis.cacheHitRate * 100))% of steps were cached. \(formatSeconds(analysis.nonCachedDuration)) spent in non-cached work.\(killersSummary)",
            suggestion: "Verify build settings and cache configuration. Review steps that are frequently rebuilt.",
            confidence: 0.6,
            relatedTargets: []
        )
    }

    private func swiftTypeCheckHotspotInsight(analysis: BuildAnalysis) -> BuildInsight? {
        guard let hotspot = analysis.swiftTypeCheckHotspots.first else { return nil }
        guard hotspot.durationSeconds >= 0.5 else { return nil }

        let fileName = URL(fileURLWithPath: hotspot.file).lastPathComponent
        let explanation = "Type checking in \(fileName):\(hotspot.line) took \(formatSeconds(hotspot.durationSeconds)) across \(hotspot.occurrences) occurrences."

        return BuildInsight(
            severity: .warning,
            title: "Swift type-check hotspot",
            explanation: explanation,
            suggestion: "Simplify the highlighted expression or split it into smaller functions to reduce compile time.",
            confidence: 0.7,
            relatedTargets: []
        )
    }

    private func dominantStepTypeInsight(analysis: BuildAnalysis) -> BuildInsight? {
        let total = analysis.totalStepDuration
        guard total > 0 else { return nil }

        let sorted = analysis.stepTypeTotals.sorted { $0.value > $1.value }
        guard let top = sorted.first else { return nil }
        let ratio = top.value / total
        guard ratio >= 0.25 else { return nil }

        let label = top.key
        let suggestion = stepTypeFixSuggestion(for: label)
        let explanation = "\(label) accounts for \(Int(ratio * 100))% of total build work (\(formatSeconds(top.value)))."

        return BuildInsight(
            severity: ratio > 0.4 ? .critical : .warning,
            title: "Dominant step type: \(label)",
            explanation: explanation,
            suggestion: suggestion,
            confidence: 0.66,
            relatedTargets: [],
            estimatedImpactSeconds: top.value * 0.2
        )
    }

    private func stepTypeFixSuggestion(for label: String) -> String {
        switch label {
        case XCLogParserDetailStepType.compileAssetsCatalog.rawValue:
            return "Split asset catalogs per feature/module to allow parallel compilation and reduce monolithic catalog work."
        case XCLogParserDetailStepType.swiftCompilation.rawValue,
             XCLogParserDetailStepType.swiftAggregatedCompilation.rawValue:
            return "Reduce Swift compile cost by breaking large targets, enabling incremental builds, and trimming dependencies."
        case XCLogParserDetailStepType.linker.rawValue:
            return "Linking is heavy; reduce linked frameworks, trim transitive deps, or split large targets."
        case XCLogParserDetailStepType.scriptExecution.rawValue:
            return "Review build scripts; move non-essential scripts to run only on CI or cache outputs."
        case XCLogParserDetailStepType.cCompilation.rawValue:
            return "Reduce C/Obj-C compile units or enable PCH/modules to cut compile time."
        case XCLogParserDetailStepType.compileStoryboard.rawValue,
             XCLogParserDetailStepType.linkStoryboards.rawValue,
             XCLogParserDetailStepType.XIBCompilation.rawValue:
            return "Split storyboards/XIBs and avoid large monolithic files to improve parallelism."
        default:
            return "Break work into smaller units and reduce dependencies to improve parallelism."
        }
    }

    private func formatSeconds(_ seconds: Double) -> String {
        String(format: "%.2fs", seconds)
    }
}
