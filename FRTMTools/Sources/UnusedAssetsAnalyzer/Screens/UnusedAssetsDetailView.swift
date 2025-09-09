import SwiftUI
import Charts

// Make AssetInfo Identifiable for ForEach
extension AssetInfo: Identifiable {
    public var id: String { path }
}

struct UnusedAssetsDetailView: View {
    @StateObject private var viewModel = UnusedAssetsViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Analyzing project...")
                        .foregroundColor(.secondary)
                }
            } else if let result = viewModel.result {
                // Show empty state if no unused assets are found
                if result.unusedAssets.isEmpty {
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
                        Button("Analyze Another Project", action: viewModel.selectProjectFolder)
                            .controlSize(.large)
                    }
                } else {
                    AnalysisResultView(result: result)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Unused Assets Analyzer")
                        .font(.title)
                    Text("Select a project folder to start analyzing for unused assets.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 300)
                    Button("Select Project Folder", action: viewModel.selectProjectFolder)
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Unused Assets Analyzer")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: viewModel.selectProjectFolder) {
                    Label("Analyze New Project", systemImage: "folder.badge.plus")
                }
            }
        }
        .errorAlert(error: $viewModel.error)
    }
}

private struct AnalysisResultView: View {
    let result: UnusedAssetResult
    
    @State private var showAISummary: Bool = false
    @State private var expandedAssetTypes: Set<String> = []

    // This is the corrected grouping logic
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

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // Corrected Summary Cards
                LazyVGrid(columns: .init(repeating: .init(.flexible()), count: 4), spacing: 20) {
                    SummaryCard(
                        title: "🗑️ Unused Assets",
                        value: "\(result.unusedAssets.count)",
                        subtitle: "Items found"
                    )
                    SummaryCard(
                        title: "💾 Wasted Space",
                        value: ByteCountFormatter.string(fromByteCount: result.totalUnusedSize, countStyle: .file),
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
                
                HStack(alignment: .top, spacing: 24) {
                    if !assetsByType.isEmpty {
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
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top 10 Largest Unused Assets")
                            .font(.title3).bold()
                        
                        Chart(topUnusedAssets(limit: 10)) { item in
                            BarMark(
                                x: .value("Size", item.size),
                                y: .value("Asset", item.name.truncating(to: 25))
                            )
                            .foregroundStyle(by: .value("Type", item.type.rawValue.uppercased()))
                        }
                        .chartYAxis { AxisMarks(preset: .aligned) }
                        .frame(height: 240)
                        .chartLegend(.hidden)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
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
        .navigationTitle("Unused Assets Analysis")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showAISummary = true }) {
                    Label("AI Summary", systemImage: "sparkles")
                }
            }
        }
    }

    private func topUnusedAssets(limit: Int) -> [AssetInfo] {
        return Array(result.unusedAssets.sorted(by: { $0.size > $1.size }).prefix(limit))
    }
    
    // Corrected prompt generation
    private func generateAnalysisSummaryPrompt(result: UnusedAssetResult) -> String {
        var prompt = ""
        
        prompt += "Scan Duration: \(String(format: "%.2f", result.scanDuration)) seconds\n"
        prompt += "Total Assets Scanned: \(result.totalAssetsScanned)\n"
        prompt += "Total Wasted Space: \(ByteCountFormatter.string(fromByteCount: result.totalUnusedSize, countStyle: .file))\n"
        prompt += "Total Unused Assets: \(result.unusedAssets.count)\n\n"
        
        prompt += "Breakdown by Type:\n"
        for assetGroup in assetsByType {
            let percentage = (Double(assetGroup.totalSize) / Double(result.totalUnusedSize)) * 100
            prompt += "- \(assetGroup.type.rawValue.uppercased()): \(assetGroup.assets.count) items, \(ByteCountFormatter.string(fromByteCount: assetGroup.totalSize, countStyle: .file)) (\(String(format: "%.2f", percentage)))%\n"
        }
        
        let topAssets = topUnusedAssets(limit: 10)
        if !topAssets.isEmpty {
            prompt += "\nTop 10 largest unused assets:\n"
            for asset in topAssets {
                prompt += "- \(asset.name): \(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file))\n"
            }
        }
        
        return prompt
    }
}

// Corrected Collapsible Section
private struct AssetCollapsibleSection: View {
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
                            Text(asset.path) // Using path for more detail
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file))
                                .foregroundColor(.secondary)
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

// New helper struct for grouping
private struct AssetTypeGroup: Identifiable {
    var id: String { type.rawValue }
    let type: AssetType
    let assets: [AssetInfo]
    let totalSize: Int64
}

// Corrected AssetType extension
extension AssetType {
    var iconName: String {
        switch self {
        case .png, .jpg, .jpeg, .gif, .heic, .webp, .svg: return "photo"
        case .pdf: return "doc.text.fill"
        }
    }
}

// String truncation helper (already defined, but good to have here)
extension String {
    func truncating(to length: Int, trailing: String = "...") -> String {
        if self.count > length {
            return String(self.prefix(length)) + trailing
        } else {
            return self
        }
    }
}

// Corrected Error Alert
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
            Button("OK") {
                error.wrappedValue = nil
            }
        } message: { error in
            // Use the model's errorDescription
            Text(error.errorDescription ?? "An unknown error occurred.")
        }
    }
}