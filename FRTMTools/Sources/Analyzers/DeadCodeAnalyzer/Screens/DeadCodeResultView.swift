import SwiftUI
import PeripheryKit
import SourceGraph
import Charts

struct DeadCodeResultView: View {
    @ObservedObject var viewModel: DeadCodeViewModel
    @State private var showingFilterSheet = false
    @State private var expandedCodeTypes: Set<String> = []

    var body: some View {
        Group {
            if let analysis = viewModel.selectedAnalysis {
                if analysis.results.isEmpty {
                    // Empty state for a completed scan with no results
                    VStack {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
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
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select an Analysis")
                        .font(.largeTitle)
                    Text("Choose an analysis from the sidebar to see the results.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(viewModel.selectedAnalysis?.projectName ?? "Dead Code Results")
        .toolbar {
            ToolbarItem {
                Button(action: { showingFilterSheet = true }) {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
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
                title: "⏱️ Scan Date",
                value: analysis.scanTimeDuration.formatted(),
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
            .frame(height: 240)
            .chartLegend(.hidden)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
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
                            .foregroundColor(.secondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .contentShape(Rectangle())
            
            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(group.results) { result in
                        HStack(spacing: 12) {
                            Text(result.icon)
                                .font(.title)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.name ?? "Unknown")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Text(result.annotationDescription)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "location.fill")
                                    Text(result.location)
                                }
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal)
                        .onTapGesture {
                            openInXcode(location: result.location)
                        }
                    }
                }
                .padding(.bottom, 10)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
    
    
    func openInXcode(location: String) {
        let components = location.split(separator: ":")
        guard components.count >= 2 else { return }
        let path = String(components[0])
        
        guard let line = Int(components[1]) else { return }
        
        guard var urlComponents = URLComponents(string: "xcode://open") else { return }
        urlComponents.queryItems = [
            URLQueryItem(name: "file", value: path),
            URLQueryItem(name: "line", value: String(line))
        ]
        
        if let url = urlComponents.url {
            NSWorkspace.shared.open(url)
        }
        
    }
}

struct DeadCodeGroup: Identifiable {
    let id: String
    let kind: String
    let results: [SerializableDeadCodeResult]
    
    init(kind: String, results: [SerializableDeadCodeResult]) {
        self.id = kind
        self.kind = kind
        self.results = results
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
