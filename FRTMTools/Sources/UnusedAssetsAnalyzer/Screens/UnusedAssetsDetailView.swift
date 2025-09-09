import SwiftUI
import Charts

struct UnusedAssetsDetailView: View {
    @StateObject private var viewModel = UnusedAssetsViewModel()

    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                List(selection: $viewModel.selectedAnalysisID) {
                    ForEach(viewModel.analyses) { analysis in
                        NavigationLink(value: analysis.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("📦 \(analysis.projectName)")
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                Text(analysis.projectPath)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding()
                        }
                        .contextMenu {
                            Button("Re-analyze") {
                                viewModel.analyzeProject(at: URL(fileURLWithPath: analysis.projectPath), overwriting: analysis.id)
                            }
                            Button("Delete", role: .destructive) {
                                viewModel.deleteAnalysis(analysis)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: viewModel.selectProjectFolder) {
                        Label("Analyze Project", systemImage: "folder.badge.plus")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            
        } detail: {
            if let result = viewModel.selectedAnalysis {
                AnalysisResultView(result: result, viewModel: viewModel)
            } else {
                // Empty state for when no analyses exist
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Unused Assets Analyzer")
                        .font(.title)
                    Text("Analyze a project to see the results here.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 300)
                    Button("Analyze Project Folder", action: viewModel.selectProjectFolder)
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            viewModel.loadAnalyses()
        }
        .loaderOverlay(
            isPresented: $viewModel.isLoading,
            content: {
                LoaderView(
                    style: .indeterminate,
                    title: "Analyzing project...",
                    subtitle: "Finding unused assets...",
                    showsCancel: false,
                    cancelAction: nil
                )
        })
        .errorAlert(error: $viewModel.error)
        .alert(
            "Analysis Exists",
            isPresented: .constant(viewModel.analysisToOverwrite != nil),
            presenting: viewModel.analysisToOverwrite
        ) { analysis in
            Button("Overwrite", action: viewModel.forceReanalyze)
            Button("Cancel", role: .cancel, action: viewModel.cancelOverwrite)
        } message: { analysis in
            Text("An analysis for \(analysis.projectName) already exists. Do you want to overwrite it?")
        }
    }
}

struct AnalysisResultView: View {
    let result: UnusedAssetResult
    @ObservedObject var viewModel: UnusedAssetsViewModel
    
    @State private var showAISummary: Bool = false
    @State private var expandedAssetTypes: Set<String> = []

    private var assetsByType: [AssetTypeGroup] {
        let grouped = Dictionary(grouping: result.unusedAssets, by: { $0.type })
        return grouped.map { type, assets in
            AssetTypeGroup(
                type: type,
                assets: assets,
                totalSize: assets.reduce(0) { $0 + $1.size }
            )
        }.sorted { $0.totalSize > $1.totalSize }
    }
    
    @ViewBuilder
    var topCardsView: some View {
        LazyVGrid(columns: .init(repeating: .init(.flexible()), count: 4), spacing: 20) {
            SummaryCard(
                title: "🗑️ Unused Assets",
                value: "\(result.unusedAssets.count)",
                subtitle: "Items found"
            )
            SummaryCard(
                title: "💾 Wasted Space",
                value: ByteCountFormatter.string(
                    fromByteCount: result.totalUnusedSize,
                    countStyle: .file
                ),
                subtitle: "Total size"
            )
            SummaryCard(
                title: "🔍 Assets Scanned",
                value: "\(result.totalAssetsScanned)",
                subtitle: "Total items"
            )
            SummaryCard(
                title: "⏱️ Scan Duration",
                value: "\(String(format: "%.2f", result.scanDuration))s",
                subtitle: "Time taken"
            )
        }
        .padding(.horizontal)
    }
    
    
    @ViewBuilder
    var cakeChartView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distribution by Type")
                .font(.title3).bold()
            
            Chart(assetsByType) { assetGroup in
                SectorMark(
                    angle: .value("Size", assetGroup.totalSize),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("Type", assetGroup.type.rawValue.uppercased()))
                .annotation(position: .overlay) {
                    let percentage = (Double(assetGroup.totalSize) / Double(result.totalUnusedSize)) * 100
                    if percentage > 5 {
                        Text("\(String(format: "%.0f", percentage))%")
                            .font(.caption)
                            .foregroundColor(.white)
                            .bold()
                    }
                }
            }
            .frame(height: 240)
            .chartLegend(position: .bottom, spacing: 12)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
    }
    
    
    @ViewBuilder
    var topUnusedChartView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Largest Unused Assets")
                .font(.title3).bold()
            
            Chart(topUnusedAssets(limit: 7)) { item in
                BarMark(
                    x: .value("Size", item.size),
                    y: .value("Asset", item.name.truncating(to: 25))
                )
                .foregroundStyle(by: .value("Type", item.type.rawValue.uppercased()))
            }
            .frame(height: 240)
            .chartLegend(.hidden)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
    }

    var body: some View {
        ScrollView {
            if result.unusedAssets.isEmpty {
                EmptyResultsView(result: result, viewModel: viewModel)
            } else {
                VStack(spacing: 24) {
                    topCardsView
                    
                    HStack(alignment: .top, spacing: 24) {
                        if !assetsByType.isEmpty {
                            cakeChartView
                            topUnusedChartView
                        }
                         
                    }
                    .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        Text("All Unused Assets")
                            .font(.title3).bold()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(assetsByType) { assetGroup in
                            AssetCollapsibleSection(
                                assetGroup: assetGroup,
                                isExpanded: expandedAssetTypes.contains(assetGroup.id)
                            ) {
                                withAnimation(.easeInOut) {
                                    if expandedAssetTypes.contains(assetGroup.id) {
                                        expandedAssetTypes.remove(assetGroup.id)
                                    } else {
                                        expandedAssetTypes.insert(assetGroup.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(result.projectName)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    viewModel.analyzeProject(at: URL(fileURLWithPath: result.projectPath), overwriting: result.id)
                }) {
                    Label("Re-analyze", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func topUnusedAssets(limit: Int) -> [AssetInfo] {
        return Array(result.unusedAssets.sorted(by: { $0.size > $1.size }).prefix(limit))
    }
    
    private struct EmptyResultsView: View {
        let result: UnusedAssetResult
        let viewModel: UnusedAssetsViewModel
        var body: some View {
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                Text("No Unused Assets Found!")
                    .font(.title)
                Text("Scanned \(result.totalAssetsScanned) assets in \(String(format: "%.2f", result.scanDuration))s and everything looks clean.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 350)
                Button("Re-analyze Project", action: {
                    viewModel.analyzeProject(at: URL(fileURLWithPath: result.projectPath), overwriting: result.id)
                })
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

struct AssetCollapsibleSection: View {
    let assetGroup: AssetTypeGroup
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack {
                    Text(assetGroup.type.rawValue.uppercased())
                        .font(.headline)
                    Spacer()
                    Text("\(assetGroup.assets.count) items - \(ByteCountFormatter.string(fromByteCount: assetGroup.totalSize, countStyle: .file))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(assetGroup.assets.sorted(by: { $0.size > $1.size })) { asset in
                        HStack {
                            Image(systemName: asset.type.iconName)
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            Text(asset.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file))
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(.horizontal)
                        Divider()
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
}


fileprivate extension View {
    func errorAlert(error: Binding<UnusedAssetsError?>) -> some View {
        let isPresented = Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        )
        
        return self.alert(
            "Analysis Error",
            isPresented: isPresented,
            presenting: error.wrappedValue
        ) { _ in
            Button("OK") { error.wrappedValue = nil }
        } message: { error in
            Text(error.errorDescription ?? "An unknown error occurred.")
        }
    }
}
