import Foundation

protocol AIFixGenerator {
    var isAvailable: Bool { get }
    func generateFixes(from report: BuildReport) async -> String?
}

struct NoopAIFixGenerator: AIFixGenerator {
    let isAvailable = false

    func generateFixes(from report: BuildReport) async -> String? {
        nil
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, *)
final class AppleFoundationModelsFixGenerator: AIFixGenerator {
    let isAvailable = true

    func generateFixes(from report: BuildReport) async -> String? {
        let prompt = buildPrompt(from: report)

        do {
            let model = SystemLanguageModel()
            let session = FoundationModels.LanguageModelSession(model: model)
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            return nil
        }
    }

    private func buildPrompt(from report: BuildReport) -> String {
        var lines: [String] = []
        lines.append("You are an expert iOS build performance engineer providing a summary for a fellow developer. Your tone should be concise, direct, and helpful.")
        lines.append("Generate a build report that follows this exact structure:")
        lines.append("1. A single summary paragraph. It must start with 'Your build took <total duration>.' Mention the main bottleneck target, its duration, and how many targets it blocks.")
        lines.append("2. After the paragraph, add the line 'Consider:'.")
        lines.append("3. A list of 3-5 actionable recommendations as Markdown bullet points. Each bullet point should start with a short, bolded title followed by a colon.")
        lines.append("Example recommendation: '* **Split Framework:** The `MyFramework` target is too large...'.")
        lines.append("---")
        lines.append("LINKING RULE: When you mention a build target by name, format it as a Markdown link: `[<target_name>](frtmtools://target/<target_name>)`. URL-encode the target name if needed.")
        lines.append("Example: 'The bottleneck is [MyFramework](frtmtools://target/MyFramework)' or '* **Optimize:** The [App-iOS](frtmtools://target/App-iOS) target...'.")
        lines.append("---")
        lines.append("Strictly follow all formatting rules. Base your report *only* on the data provided below. Do not add any extra headers, comments, or any other text.")
        lines.append("If a project name is available in the data, use it in the summary. Otherwise, just say 'Your build'.")
        lines.append("----")
        lines.append("DATA:")

        lines.append("Available targets for linking: \(report.targets.map { $0.name }.joined(separator: ", "))")
        lines.append("----")

        lines.append("Build summary: total \(formatSeconds(report.summary.totalDuration)), critical path \(formatSeconds(report.summary.criticalPathDuration)), parallelism \(String(format: "%.2fx", report.summary.parallelism)), cache hit rate \(String(format: "%.0f%%", report.summary.cacheHitRate * 100)), build health score \(String(format: "%.0f", report.summary.buildHealthScore)).")

        if let bottleneck = report.targets.first(where: { $0.isBottleneck }) {
            lines.append("Main bottleneck target: \(bottleneck.name) with duration \(formatSeconds(bottleneck.duration)), fan-out \(bottleneck.fanOut).")
        }

        let topTargets = report.targets.prefix(5)
        if !topTargets.isEmpty {
            lines.append("Top targets by duration:")
            for target in topTargets {
                lines.append("- \(target.name): duration \(formatSeconds(target.duration)), fan-out \(target.fanOut), parallelism \(String(format: "%.2fx", target.parallelism)), insights: \(target.insights.count), steps: \(target.stepTimeline.count)")
            }
        }

        if let criticalPath = report.overviewSections.first(where: { $0.title == "Critical Path" })?.lines {
            lines.append("Critical path chain: \(criticalPath.joined(separator: " -> "))")
        }

        if !report.issueSummaries.isEmpty {
            lines.append("Detected issues:")
            for issue in report.issueSummaries.prefix(5) {
                lines.append("- \(issue.title) (\(issue.severity.rawValue)): \(issue.explanation) | Fix: \(issue.suggestion) | Targets: \(issue.relatedTargets.joined(separator: ", "))")
            }
        }

        if let stepTypes = report.overviewSections.first(where: { $0.title == "Serial Work / Step Types" })?.lines {
            lines.append("Top serial step types:")
            for line in stepTypes.prefix(3) {
                lines.append("- \(line)")
            }
        }

        if !report.charts.stepTypeTotals.isEmpty {
            let breakdown = report.charts.stepTypeTotals.prefix(5).map { "\($0.label): \(formatSeconds($0.value))" }.joined(separator: ", ")
            lines.append("Overall step type breakdown: \(breakdown)")
        }

        if let diagnostics = report.overviewSections.first(where: { $0.title == "Warnings / Notes" })?.lines.first {
            lines.append("Diagnostics summary: \(diagnostics)")
        }

        var notableNotes: [String] = []
        for target in report.targets {
            for step in target.stepTimeline {
                if let note = step.noteSummary {
                    notableNotes.append("\(target.name) -> \(step.title): \(note)")
                }
            }
        }

        if !notableNotes.isEmpty {
            lines.append("Notable Step Notes:")
            for note in notableNotes.prefix(10) {
                lines.append("- \(note)")
            }
        }

        lines.append("----")
        lines.append("Now, generate the report based on the instructions and data above.")
        let prompt = lines.joined(separator: "\n")
        return trimPrompt(prompt, maxCharacters: 10000)
    }

    private func formatSeconds(_ seconds: Double) -> String {
        String(format: "%.2fs", seconds)
    }

    private func trimPrompt(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let trimmed = text.prefix(maxCharacters - 20)
        return trimmed + "\n[Truncated]\n"
    }
}
#endif
