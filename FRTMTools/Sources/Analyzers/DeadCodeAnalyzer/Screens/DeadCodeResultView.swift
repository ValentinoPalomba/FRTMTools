import SwiftUI
import AppKit
import PeripheryKit
import SourceGraph
import Charts

struct DeadCodeResultView: View {
    @Bindable var viewModel: DeadCodeViewModel
    @State private var showingFilterSheet = false
    @State private var expandedCodeTypes: Set<String> = []
    var body: some View {
        Group {
            if let analysis = viewModel.selectedAnalysis {
                if analysis.results.isEmpty {
                    // Empty state for a completed scan with no results
                    VStack {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.largeTitle)
                            .imageScale(.large)
                            .foregroundStyle(.green)
                        Text("No dead code found in \(analysis.projectName).")
                            .font(.largeTitle)
                    }
                } else {
                    // Main results view
                    ScrollView {
                        VStack(spacing: 24) {
                            topCardsView(for: analysis)
                            
                            HStack(alignment: .top, spacing: 24) {
                                DeadCodeChartView(results: viewModel.filteredResults)
                                topIssuesChartView
                            }
                            .padding(.horizontal)

                            DeadCodeDependencyTreeView(viewModel: viewModel)
                                .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                Text("All Issues")
                                    .font(.title3).bold()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                ForEach(viewModel.resultsByKind) { group in
                                    DeadCodeCollapsibleSection(
                                        group: group,
                                        isExpanded: expandedCodeTypes.contains(group.id),
                                        action: {
                                            withAnimation(.easeInOut) {
                                                if expandedCodeTypes.contains(group.id) {
                                                    expandedCodeTypes.remove(group.id)
                                                } else {
                                                    expandedCodeTypes.insert(group.id)
                                                }
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 80)
                        }
                        .padding(.vertical, 16)
                    }
                }
            } else {
                // Placeholder for when no analysis is selected
                VStack {
                    Image(systemName: "list.bullet.indent")
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                    Text("Select an Analysis")
                        .font(.largeTitle)
                    Text("Choose an analysis from the sidebar to see the results.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(viewModel.selectedAnalysis?.projectName ?? "Dead Code Results")
        .toolbar {
            ToolbarItem {
                Button {
                    showingFilterSheet = true
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                .disabled(viewModel.selectedAnalysis == nil || viewModel.selectedAnalysis?.results.isEmpty == true)
            }
            
            ToolbarItem {
                Button(action: { viewModel.exportToCSV() }) {
                    Label("Export as CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.selectedAnalysis == nil || viewModel.selectedAnalysis?.results.isEmpty == true)
            }
        }
        .inspector(isPresented: $showingFilterSheet) {
            DeadCodeFilterView(
                selectedKinds: $viewModel.selectedKinds,
                selectedAccessibilities: $viewModel.selectedAccessibilities,
                minimumClusterSize: $viewModel.minimumClusterSize,
                includesIsolatedClusters: $viewModel.includesIsolatedClusters,
                showsOnlyFullyRemovableClusters: $viewModel.showsOnlyFullyRemovableClusters,
                showsOnlyMultiFileClusters: $viewModel.showsOnlyMultiFileClusters
            )
            .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .deadCodeFeedbackSheet(error: $viewModel.error)
    }

    @ViewBuilder
    private func topCardsView(for analysis: DeadCodeAnalysis) -> some View {
        LazyVGrid(columns: .init(repeating: .init(.flexible()), count: 4), spacing: 20) {
            SummaryCard(
                title: "🗑️ Total Issues",
                value: "\(viewModel.filteredResults.count)",
                subtitle: "Items found"
            )
            SummaryCard(
                title: "⚖️ Issue Types",
                value: "\(viewModel.resultsByKind.count)",
                subtitle: "Total types"
            )
            SummaryCard(
                title: "⏱️ Scan Duration",
                value: format(duration: analysis.scanTimeDuration),
                subtitle: "Time of scan"
            )
            SummaryCard(
                title: "🕸️ Dead Clusters",
                value: "\(viewModel.dependencyClusters.count)",
                subtitle: "\(viewModel.safeFileRemovalCount) whole-file candidates"
            )
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var topIssuesChartView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Issues")
                .font(.title3).bold()
            
            Chart(viewModel.resultsByKind.prefix(7)) { item in
                BarMark(
                    x: .value("Count", item.results.count),
                    y: .value("Kind", item.kind.truncating(to: 25))
                )
                .foregroundStyle(by: .value("Type", item.kind.uppercased()))
            }
            .frame(height: 250)
            .chartLegend(.hidden)
        }
        .padding()
        .dsSurface(.surface, cornerRadius: 16, border: true, shadow: true)
    }
}

struct DeadCodeCollapsibleSection: View {
    let group: DeadCodeGroup
    let isExpanded: Bool
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(group.kind.uppercased())
                    .font(.headline)
                
                Spacer()
                
                Button(action: action) {
                    HStack {
                        Text("\(group.results.count) items")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                }
                .buttonStyle(.plain)
            }
            .padding()
            .contentShape(.rect)
            
            if isExpanded {
                Divider()
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(group.results) { result in
                        Button {
                            openInXcode(location: result.location)
                        } label: {
                            HStack(spacing: 12) {
                                Text(result.icon)
                                    .font(.title)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.name ?? "Unknown")
                                        .font(.headline)
                                        .bold()
                                    
                                    Text(result.annotationDescription)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    
                                    HStack(spacing: 4) {
                                        Image(systemName: "location.fill")
                                        Text(result.location)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .dsSurface(.surface, cornerRadius: 12, border: true, shadow: true)
    }
    
    

    func openInXcode(location: String) {
        let components = location.split(separator: ":")
        guard components.count >= 2 else { return }

        let path = String(components[0])
        guard let line = Int(components[1]) else { return }

        let task = Process()
        task.launchPath = "/usr/bin/xed"
        task.arguments = ["-l", "\(line)", path]
        try? task.run()
    }

}



fileprivate extension String {
    func truncating(to length: Int) -> String {
        if self.count > length {
            return String(self.prefix(length)) + "..."
        }
        return self
    }
}

private struct DeadCodeErrorPresentation: Identifiable {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var id: String { "\(title):\(message)" }

    var summary: String {
        let firstSection = message.components(separatedBy: "\n\n").first ?? message
        guard firstSection.count > 360 else { return firstSection }
        return String(firstSection.prefix(360)) + "…"
    }

    var technicalDetails: String? {
        let sections = message.components(separatedBy: "\n\n")
        if sections.count > 1 {
            return sections.dropFirst().joined(separator: "\n\n")
        }
        return message.count > 360 ? message : nil
    }

    init(error: Error) {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            message = description
        } else {
            message = error.localizedDescription
        }

        if let removalError = error as? DeadCodeRemovalError {
            switch removalError {
            case .buildFailed:
                title = "Build Failed — Sources Restored"
                systemImage = "arrow.uturn.backward.circle.fill"
                tint = .orange
            case .rollbackFailed:
                title = "Sources Need Manual Recovery"
                systemImage = "exclamationmark.octagon.fill"
                tint = .red
            default:
                title = "Removal Was Not Applied"
                systemImage = "xmark.circle.fill"
                tint = .orange
            }
        } else if error is DeadCodeSurgicalRemovalError {
            title = "Safe Removal Needs Review"
            systemImage = "exclamationmark.triangle.fill"
            tint = .orange
        } else {
            title = "Dead Code Scanner Error"
            systemImage = "exclamationmark.circle.fill"
            tint = .red
        }
    }
}

private struct DeadCodeErrorSheet: View {
    let presentation: DeadCodeErrorPresentation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: presentation.systemImage)
                        .font(.title)
                        .foregroundStyle(presentation.tint)
                        .frame(width: 38)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(presentation.title)
                            .font(.title3.weight(.semibold))
                        Text(presentation.summary)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let details = presentation.technicalDetails {
                    GroupBox {
                        ScrollView([.horizontal, .vertical]) {
                            Text(details)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 280)
                    } label: {
                        Label("Technical Details", systemImage: "doc.text.magnifyingglass")
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(width: 680, height: 460)
            .navigationTitle("Operation Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy Details", systemImage: "doc.on.doc") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(presentation.message, forType: .string)
                    }
                }
            }
        }
    }
}

private extension View {
    func deadCodeFeedbackSheet(error: Binding<Error?>) -> some View {
        let presentation = Binding<DeadCodeErrorPresentation?>(
            get: {
                error.wrappedValue.map(DeadCodeErrorPresentation.init)
            },
            set: { newValue in
                if newValue == nil {
                    error.wrappedValue = nil
                }
            }
        )

        return sheet(item: presentation) { item in
            DeadCodeErrorSheet(presentation: item)
        }
    }
}
