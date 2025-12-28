import Foundation

struct BuildReport: Hashable {
    struct Summary: Hashable {
        let totalDuration: Double
        let criticalPathDuration: Double
        let parallelism: Double
        let cacheHitRate: Double
        let buildHealthScore: Double
    }

    struct OverviewSection: Identifiable, Hashable {
        let id: UUID
        let title: String
        let lines: [String]

        init(id: UUID = UUID(), title: String, lines: [String]) {
            self.id = id
            self.title = title
            self.lines = lines
        }
    }

    struct IssueSummary: Identifiable, Hashable {
        let id: UUID
        let title: String
        let explanation: String
        let suggestion: String
        let severity: BuildInsight.Severity
        let relatedTargets: [String]
        let estimatedImpactSeconds: Double?

        init(
            id: UUID = UUID(),
            title: String,
            explanation: String,
            suggestion: String,
            severity: BuildInsight.Severity,
            relatedTargets: [String],
            estimatedImpactSeconds: Double?
        ) {
            self.id = id
            self.title = title
            self.explanation = explanation
            self.suggestion = suggestion
            self.severity = severity
            self.relatedTargets = relatedTargets
            self.estimatedImpactSeconds = estimatedImpactSeconds
        }
    }

    struct TargetSummary: Identifiable, Hashable {
        let id: String
        let name: String
        let duration: Double
        let fanIn: Int
        let fanOut: Int
        let isBottleneck: Bool
        let dependencies: [String]
        let dependents: [String]
        let parallelism: Double
        let stepTimeline: [StepTimelineItem]
        let stepTypeBreakdown: [StepTypeBreakdown]
        let insights: [BuildInsight]
    }

    struct StepTimelineItem: Identifiable, Hashable {
        let id: String
        let title: String
        let typeLabel: String
        let startOffset: Double
        let endOffset: Double
        let duration: Double
        let fetchedFromCache: Bool
        let noteSummary: String?
    }

    struct StepTypeBreakdown: Identifiable, Hashable {
        let id: String
        let label: String
        let duration: Double
    }

    struct ChartPoint: Identifiable, Hashable {
        let id: String
        let label: String
        let value: Double
    }

    struct Charts: Hashable {
        let targetDurations: [ChartPoint]
        let targetParallelism: [ChartPoint]
        let stepTypeTotals: [ChartPoint]
    }

    let summary: Summary
    let overviewSections: [OverviewSection]
    let issueSummaries: [IssueSummary]
    let targets: [TargetSummary]
    let insights: [BuildInsight]
    let charts: Charts
    let aiFixes: String?
}

extension BuildReport {
    func withAIFixes(_ fixes: String?) -> BuildReport {
        BuildReport(
            summary: summary,
            overviewSections: overviewSections,
            issueSummaries: issueSummaries,
            targets: targets,
            insights: insights,
            charts: charts,
            aiFixes: fixes
        )
    }
}
