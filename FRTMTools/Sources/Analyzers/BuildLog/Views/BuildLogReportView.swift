import SwiftUI
import Charts

struct BuildLogReportView: View {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case targets = "Targets"

        var id: String { rawValue }
    }

    let report: BuildReport
    @State private var section: Section = .overview
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.12), Color.black.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    ReportHeaderView(report: report, section: $section)

                    ScrollView {
                        VStack(spacing: 18) {
                            switch section {
                            case .overview:
                                BuildOverviewView(report: report)
                            case .targets:
                                BuildTargetsView(report: report)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationDestination(for: BuildReport.TargetSummary.self) { target in
                BuildTargetDetailView(target: target)
                    .navigationTitle(target.name)
            }
            .onOpenURL(perform: handleURL)
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "frtmtools", url.host == "target", url.pathComponents.count > 1 else {
            return
        }

        let targetName = url.lastPathComponent.removingPercentEncoding ?? ""
        if let target = report.targets.first(where: { $0.name == targetName }) {
            // Using a path ensures we can navigate from any tab.
            // We clear the path first to ensure a clean navigation stack.
            navigationPath = NavigationPath()
            navigationPath.append(target)
        }
    }
}

private struct ReportHeaderView: View {
    let report: BuildReport
    @Binding var section: BuildLogReportView.Section

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Build Radar")
                            .font(.title2.weight(.bold))
                        Text("Una dashboard sintetica per intercettare subito i colli di bottiglia.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("Section", selection: $section) {
                        ForEach(BuildLogReportView.Section.allCases) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }

                HStack(spacing: 12) {
                    MetricChip(
                        icon: "square.stack.3d.up",
                        title: "Targets",
                        value: "\(report.targets.count)",
                        tint: .accentColor
                    )
                    MetricChip(
                        icon: "lightbulb.fill",
                        title: "Insights",
                        value: "\(report.insights.count)",
                        tint: .purple
                    )
                    MetricChip(
                        icon: "speedometer",
                        title: "Health score",
                        value: String(format: "%.0f", report.summary.buildHealthScore),
                        tint: .green
                    )
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

private struct HeroHeaderCard: View {
    let summary: BuildReport.Summary
    let bottleneckName: String?

    private var cacheProgress: Double {
        min(max(summary.cacheHitRate, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Diagnostic dashboard")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                    Text("Focalizzata sui rallentamenti, non sui dettagli ridondanti.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                Spacer()
                if let bottleneckName {
                    TagView(text: bottleneckName, icon: "flame.fill", tint: .yellow)
                }
            }

            HStack(spacing: 10) {
                MetricChip(
                    icon: "timer",
                    title: "Totale",
                    value: formatSeconds(summary.totalDuration),
                    tint: .white.opacity(0.9),
                    dark: true
                )
                MetricChip(
                    icon: "bolt.fill",
                    title: "Critical path",
                    value: formatSeconds(summary.criticalPathDuration),
                    tint: .yellow,
                    dark: true
                )
                MetricChip(
                    icon: "aqi.medium",
                    title: "Parallelism",
                    value: String(format: "%.2fx", summary.parallelism),
                    tint: .white.opacity(0.9),
                    dark: true
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Cache hit rate", systemImage: "arrow.clockwise.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text(String(format: "%.0f%%", summary.cacheHitRate * 100))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                ProgressView(value: cacheProgress)
                    .tint(.white)
                    .progressViewStyle(.linear)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.7), Color.blue.opacity(0.6), Color.black.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15))
        )
        .cornerRadius(18)
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 8)
    }
}

private struct BottleneckSpotlightCard: View {
    let target: BuildReport.TargetSummary?
    let slowestStepType: BuildReport.ChartPoint?
    let totalDuration: Double

    private var durationShare: Double {
        guard let target, totalDuration > 0 else { return 0 }
        return target.duration / totalDuration
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Bottleneck spotlight", systemImage: "scope")
                        .font(.headline)
                    Spacer()
                    if let target {
                        TagView(text: target.name, icon: "target")
                    }
                }

                if let target {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            InlineStat(icon: "timer", label: formatSeconds(target.duration))
                            InlineStat(icon: "arrow.up.forward", label: "Fan-out \(target.fanOut)")
                            InlineStat(icon: "person.3", label: "\(target.dependents.count) dependents")
                        }
                        ProgressView(value: durationShare)
                            .progressViewStyle(.linear)
                            .tint(.orange)
                        Text("Quota sul tempo totale: \(String(format: "%.0f%%", durationShare * 100))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Nessun bottleneck marcato: ottimo! Continua a monitorare i target più lunghi.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Step più costoso")
                            .font(.subheadline.weight(.semibold))
                        if let slowestStepType {
                            Text("\(slowestStepType.label) • \(formatSeconds(slowestStepType.value))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Nessun dato di step disponibile.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    TagView(text: "Focus: riduci serializzazione", icon: "bolt.horizontal.circle", tint: .orange)
                }
            }
        }
    }
}

private struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), Color.accentColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
    }
}

private struct TagView: View {
    let text: String
    var icon: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14))
        .foregroundColor(tint)
        .clipShape(Capsule())
    }
}

private struct MetricChip: View {
    let icon: String
    let title: String
    let value: String
    var tint: Color = .accentColor
    var dark: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                Text(value)
                    .font(.headline.weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(dark ? Color.black.opacity(0.25) : tint.opacity(0.12))
        )
        .foregroundColor(dark ? .white : .primary)
    }
}


private struct GlobalInsightsView: View {
    let insights: [BuildInsight]

    var body: some View {
        if !insights.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(insights) { insight in
                        insightCard(insight)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                    Text("Global Build Insights (\(insights.count))")
                }
                .font(.title3.weight(.semibold))
            }
        }
    }

    private func insightCard(_ insight: BuildInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                severityIndicator(insight.severity)
                Text(insight.title)
                    .font(.subheadline.weight(.semibold))
            }
            Text(insight.explanation)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Suggestion: \(insight.suggestion)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.12), Color(NSColor.controlBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
    }
}

private struct BuildOverviewView: View {
    let report: BuildReport
    private let rowHeight: CGFloat = 22
    @State private var hoveredTarget: BuildReport.ChartPoint?
    @State private var hoveredStepType: BuildReport.ChartPoint?
    @State private var highlightedTargetLabel: String?
    @State private var highlightedStepTypeLabel: String?

    private var bottleneckTarget: BuildReport.TargetSummary? {
        if let marked = report.targets.first(where: { $0.isBottleneck }) {
            return marked
        }
        return report.targets.max(by: { $0.duration < $1.duration })
    }

    private var slowestStepType: BuildReport.ChartPoint? {
        report.charts.stepTypeTotals.max(by: { $0.value < $1.value })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroHeaderCard(
                summary: report.summary,
                bottleneckName: bottleneckTarget?.name
            )

            BottleneckSpotlightCard(
                target: bottleneckTarget,
                slowestStepType: slowestStepType,
                totalDuration: report.summary.totalDuration
            )

            GlassCard {
                DiagnosticReportView(
                    issueSummaries: report.issueSummaries,
                    aiFixes: report.aiFixes
                )
            }

            GlassCard {
                EvidenceSectionView(
                    report: report,
                    rowHeight: rowHeight,
                    hoveredTarget: $hoveredTarget,
                    hoveredStepType: $hoveredStepType,
                    highlightedTargetLabel: $highlightedTargetLabel,
                    highlightedStepTypeLabel: $highlightedStepTypeLabel
                )
            }

            if let insights = insightsSummary {
                GlassCard {
                    GlobalInsightsView(insights: insights)
                }
            }

            GlassCard {
                DetailsSectionView(overviewSections: report.overviewSections)
            }
        }
    }

    private var insightsSummary: [BuildInsight]? {
        let items = report.insights.filter { $0.relatedTargets.isEmpty }
        return items.isEmpty ? nil : items
    }
}

private struct BuildTargetsView: View {
    let report: BuildReport
    @State private var searchText = ""

    private var filteredTargets: [BuildReport.TargetSummary] {
        if searchText.isEmpty {
            return report.targets
        } else {
            return report.targets.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var maxDuration: Double {
        report.targets.map(\.duration).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target bottlenecks")
                        .font(.headline)
                    Text("Ordina mentalmente per durata e fan-out: scopri dove si blocca la pipeline.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                TagView(text: "\(filteredTargets.count) visibili")
            }

            GlassCard {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filtra i target per nome", text: $searchText)
                        .textFieldStyle(.plain)
                        .textCase(.none)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            LazyVStack(spacing: 10) {
                ForEach(filteredTargets) { target in
                    NavigationLink(value: target) {
                        TargetRow(target: target, maxDuration: maxDuration)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 320, alignment: .top)
        }
    }
}

private struct TargetRow: View {
    let target: BuildReport.TargetSummary
    let maxDuration: Double

    private var durationRatio: Double {
        guard maxDuration > 0 else { return 0 }
        return target.duration / maxDuration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.name)
                        .font(.headline)
                    HStack(spacing: 10) {
                        InlineStat(icon: "timer", label: formatSeconds(target.duration))
                        InlineStat(icon: "arrow.up.forward", label: "Fan-out \(target.fanOut)")
                        InlineStat(icon: "arrow.down.forward", label: "Fan-in \(target.fanIn)")
                        InlineStat(icon: "rectangle.split.3x1.fill", label: String(format: "%.2fx", target.parallelism))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    if target.isBottleneck {
                        TagView(text: "Bottleneck", icon: "flame.fill", tint: .orange)
                    }
                    if !target.insights.isEmpty {
                        TagView(text: "\(target.insights.count) insight\(target.insights.count == 1 ? "" : "s")", icon: "lightbulb.fill", tint: .accentColor)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: durationRatio)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                Text("Quota rispetto al target più lento")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !target.insights.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(target.insights.prefix(2)) { insight in
                        HStack(spacing: 8) {
                            severityIndicator(insight.severity)
                            Text(insight.title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if target.insights.count > 2 {
                        Text("+\(target.insights.count - 2) altre note")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    Color(NSColor.controlBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
    }
}

private struct InlineStat: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption)
        }
        .foregroundColor(.secondary)
    }
}

private struct BuildTargetDetailView: View {
    private let rowHeight: CGFloat = 22
    let target: BuildReport.TargetSummary
    @State private var highlightedStepID: String?

    var body: some View {
        ScrollView {
            GlassCard {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text(target.name)
                            .font(.title2.weight(.semibold))
                        Text("Duration: \(formatSeconds(target.duration)) | Parallelism: \(String(format: "%.2fx", target.parallelism))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)

                    // Dependencies & Dependents
                    DisclosureGroup {
                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Dependencies (\(target.dependencies.count))")
                                    .font(.headline)
                                Text(target.dependencies.isEmpty ? "None" : target.dependencies.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Dependents (\(target.dependents.count))")
                                    .font(.headline)
                                Text(target.dependents.isEmpty ? "None" : target.dependents.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text("Dependencies & Dependents").font(.title3.weight(.semibold))
                    }

                    // Step Timeline
                    DisclosureGroup(isExpanded: .constant(true)) {
                        VStack(alignment: .leading, spacing: 12) {
                            let timelineHeight = max(220, CGFloat(target.stepTimeline.count) * rowHeight)
                            if target.stepTimeline.isEmpty {
                                Text("No step timeline data.")
                                    .foregroundColor(.secondary)
                            } else {
                                Chart(target.stepTimeline) { step in
                                    BarMark(
                                        xStart: .value("Start", step.startOffset),
                                        xEnd: .value("End", step.endOffset),
                                        y: .value("Step", step.title)
                                    )
                                    .foregroundStyle(colorForStepType(step.typeLabel, isCached: step.fetchedFromCache, isHighlighted: step.id == highlightedStepID))
                                }
                                .frame(height: timelineHeight)
                                .chartXAxisLabel("Seconds")
                                .chartOverlay { proxy in
                                    GeometryReader { geo in
                                        Rectangle()
                                            .fill(Color.clear)
                                            .contentShape(Rectangle())
                                            .gesture(
                                                DragGesture(minimumDistance: 0)
                                                    .onChanged { value in
                                                        let plotFrame = geo[proxy.plotAreaFrame]
                                                        let y = value.location.y - plotFrame.origin.y
                                                        if let label: String = proxy.value(atY: y),
                                                           let step = target.stepTimeline.first(where: { $0.title == label }) {
                                                            highlightedStepID = step.id
                                                        }
                                                    }
                                                    .onEnded { _ in
                                                        highlightedStepID = nil
                                                    }
                                            )
                                    }
                                }
                            }

                            let notableNotes = target.stepTimeline.compactMap { item -> String? in
                                guard let note = item.noteSummary else { return nil }
                                return "\(item.title): \(note)"
                            }

                            if !notableNotes.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Notes")
                                        .font(.headline)
                                    ForEach(notableNotes, id: \.self) { note in
                                        Text(note)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Step Timeline").font(.title3.weight(.semibold))
                    }

                    // Step Type Breakdown
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            let breakdownHeight = max(200, CGFloat(target.stepTypeBreakdown.count) * rowHeight)
                            if target.stepTypeBreakdown.isEmpty {
                                Text("No step type breakdown available.")
                                    .foregroundColor(.secondary)
                            } else {
                                Chart(target.stepTypeBreakdown) { item in
                                    BarMark(
                                        x: .value("Duration", item.duration),
                                        y: .value("Type", item.label)
                                    )
                                    .foregroundStyle(Color.primary.opacity(0.7))
                                }
                                .frame(height: breakdownHeight)
                                .chartXAxisLabel("Seconds")
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Step Type Breakdown").font(.title3.weight(.semibold))
                    }

                    // Target Insights
                    if !target.insights.isEmpty {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(target.insights) { insight in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            severityIndicator(insight.severity)
                                            Text(insight.title)
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        Text(insight.explanation)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("Suggestion: \(insight.suggestion)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(10)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("Target Insights (\(target.insights.count))").font(.title3.weight(.semibold))
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func colorForStepType(_ typeLabel: String, isCached: Bool, isHighlighted: Bool) -> Color {
        var baseColor: Color
        switch typeLabel {
        case "CompileSwift", "CompileC", "CompileAssetCatalog":
            baseColor = .blue
        case "Link", "LinkStoryboards", "LinkMetal":
            baseColor = .green
        case "Run Script", "PhaseScriptExecution":
            baseColor = .purple
        case "GenerateDSYM":
            baseColor = .orange
        case "ProcessProductPackaging":
            baseColor = .red
        case "Copy", "Cp", "ProcessInfoPlistFile":
            baseColor = .gray
        default:
            baseColor = .teal // Use teal for unknown/other types
        }

        if isHighlighted {
            return .accentColor // Highlight always overrides
        } else if isCached {
            return baseColor.opacity(0.6) // Cached is muted
        } else {
            return baseColor // Normal
        }
    }
}



private struct BuildMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.1), Color(NSColor.controlBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
    }
}

private struct ChartHoverCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

private struct OverviewSectionView: View {
    let section: BuildReport.OverviewSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.headline)
            ForEach(section.lines, id: \.self) { line in
                Text("• \(line)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiagnosticReportView: View {
    let issueSummaries: [BuildReport.IssueSummary]
    let aiFixes: String?
    @State private var showGlossary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Diagnostic Report")
                    .font(.title3.weight(.semibold))
                Button {
                    showGlossary.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showGlossary) {
                    GlossaryView()
                        .frame(width: 320)
                        .padding()
                }
            }

            if issueSummaries.isEmpty {
                Text("No major issues detected. Build performance looks healthy.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(issueSummaries) { issue in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            severityIndicator(issue.severity)
                            Text(issue.title)
                                .font(.headline)
                            Spacer()
                            TagView(text: issue.severity == .critical ? "Critical" : issue.severity == .warning ? "Warning" : "Info", tint: severityColor(issue.severity))
                        }
                        Text(issue.explanation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Suggested fix: \(issue.suggestion)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !issue.relatedTargets.isEmpty {
                            Text("Targets: \(issue.relatedTargets.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let impact = issue.estimatedImpactSeconds {
                            Text("Estimated impact: \(formatSeconds(impact))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [
                                severityColor(issue.severity).opacity(0.08),
                                Color(NSColor.controlBackgroundColor)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(severityColor(issue.severity))
                            .frame(width: 4)
                    }
                }
            }

            if let aiFixes {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("AI-Generated Report")
                            .font(.headline)
                    }
                    Text(.init(aiFixes))
                        .textSelection(.enabled)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.12), Color(NSColor.controlBackgroundColor)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(12)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func severityColor(_ severity: BuildInsight.Severity) -> Color {
        switch severity {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
}

private struct EvidenceSectionView: View {
    let report: BuildReport
    let rowHeight: CGFloat
    @Binding var hoveredTarget: BuildReport.ChartPoint?
    @Binding var hoveredStepType: BuildReport.ChartPoint?
    @Binding var highlightedTargetLabel: String?
    @Binding var highlightedStepTypeLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Evidence", systemImage: "chart.bar.fill")
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                BuildMetricTile(title: "Total Build Time", value: formatSeconds(report.summary.totalDuration))
                BuildMetricTile(title: "Critical Path", value: formatSeconds(report.summary.criticalPathDuration))
                BuildMetricTile(title: "Parallelism", value: String(format: "%.2fx", report.summary.parallelism))
                BuildMetricTile(title: "Cache Hit Rate", value: String(format: "%.0f%%", report.summary.cacheHitRate * 100))
                BuildMetricTile(title: "Build Health", value: String(format: "%.0f", report.summary.buildHealthScore))
            }

            ChartBlockView(
                title: "Target Durations",
                data: report.charts.targetDurations,
                highlightedLabel: $highlightedTargetLabel,
                hoveredPoint: $hoveredTarget,
                rowHeight: rowHeight
            )

            ChartBlockView(
                title: "Step Type Totals",
                data: report.charts.stepTypeTotals,
                highlightedLabel: $highlightedStepTypeLabel,
                hoveredPoint: $hoveredStepType,
                rowHeight: rowHeight
            )
        }
    }
}

private struct DetailsSectionView: View {
    let overviewSections: [BuildReport.OverviewSection]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(overviewSections) { section in
                    OverviewSectionView(section: section)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Details (\(overviewSections.count))")
                .font(.title3.weight(.semibold))
        }
    }
}

private struct ChartBlockView: View {
    let title: String
    let data: [BuildReport.ChartPoint]
    @Binding var highlightedLabel: String?
    @Binding var hoveredPoint: BuildReport.ChartPoint?
    let rowHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            let chartHeight = max(200, CGFloat(data.count) * rowHeight)
            if data.isEmpty {
                Text("No data available.")
                    .foregroundColor(.secondary)
            } else {
                ZStack(alignment: .topLeading) {
                    Chart(data) { point in
                        BarMark(
                            x: .value("Duration", point.value),
                            y: .value("Label", point.label)
                        )
                        .foregroundStyle(point.label == highlightedLabel ? Color.accentColor : Color.primary.opacity(0.7))
                    }
                    .frame(height: chartHeight)
                    .chartXAxisLabel("Seconds")
                    .chartYAxis {
                        AxisMarks(values: .automatic) { value in
                            AxisValueLabel {
                                if let label = value.as(String.self) {
                                    Text(label)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(width: 200, alignment: .leading)
                                }
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let plotFrame = geo[proxy.plotAreaFrame]
                                            let y = value.location.y - plotFrame.origin.y
                                            if let label: String = proxy.value(atY: y),
                                               let point = data.first(where: { $0.label == label }) {
                                                hoveredPoint = point
                                                highlightedLabel = point.label
                                            }
                                        }
                                        .onEnded { _ in
                                            hoveredPoint = nil
                                            highlightedLabel = nil
                                        }
                                )
                        }
                    }

                    if let hoveredPoint {
                        ChartHoverCard(
                            title: hoveredPoint.label,
                            value: formatSeconds(hoveredPoint.value)
                        )
                        .padding(.leading, 8)
                        .padding(.top, 8)
                    }
                }
            }
        }
    }
}

private struct GlossaryView: View {
    private let items: [(term: String, definition: String)] = [
        ("Critical path", "Longest chain of dependent targets; sets the minimum possible build time."),
        ("Fan-out", "Number of downstream targets that depend on a target."),
        ("Parallelism", "Total work time divided by wall-clock time; higher means more work in parallel."),
        ("Cache hit rate", "Percentage of build steps reused from cache."),
        ("Bottleneck", "A target or step that blocks many dependents or dominates time.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Glossary")
                .font(.headline)
            ForEach(items, id: \.term) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.term)
                        .font(.subheadline.weight(.semibold))
                    Text(item.definition)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

private func formatSeconds(_ seconds: Double) -> String {
    String(format: "%.2fs", seconds)
}

@ViewBuilder
private func severityIndicator(_ severity: BuildInsight.Severity) -> some View {
    let color: Color
    switch severity {
    case .info:
        color = .secondary
    case .warning:
        color = .orange
    case .critical:
        color = .red
    }
    return Circle()
        .fill(color)
        .frame(width: 8, height: 8)
}
