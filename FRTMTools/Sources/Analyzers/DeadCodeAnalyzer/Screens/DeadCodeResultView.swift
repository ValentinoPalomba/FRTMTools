import SwiftUI
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
        .sheet(isPresented: $showingFilterSheet) {
            DeadCodeFilterView(
                selectedKinds: $viewModel.selectedKinds,
                selectedAccessibilities: $viewModel.selectedAccessibilities
            )
        }
        .errorAlert(error: $viewModel.error)
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
