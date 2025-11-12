import SwiftUI
import Charts

struct DetailView<ViewModel: AppDetailViewModel>: View {
    @ObservedObject var viewModel: ViewModel

    @State private var expandedSections: Set<String> = []
    @State private var selectedCategoryName: String? = nil
    @State private var searchText = ""

    private let categoryColorScale: [String: Color] = [
        "Resources": .green,
        "Frameworks": .blue,
        "Binary": .red,
        "Assets": .purple,
        "Bundles": .orange,
        "Native Libraries": .teal,
        "Dex Files": .pink
    ]

    private var categoryColorDomain: [String] { Array(categoryColorScale.keys) }
    private var categoryColorRange: [Color] { categoryColorDomain.compactMap { categoryColorScale[$0] } }

    private var filteredCategories: [CategoryResult] {
        viewModel.filteredCategories(searchText: searchText)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // Grid overview
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    SummaryCard(
                        title: "📦 Uncompressed Size",
                        value: ByteCountFormatter.string(fromByteCount: viewModel.analysis.totalSize, countStyle: .file),
                        subtitle: viewModel.analysis.fileName
                    )
                    
                    if let sizeAnalyzer = viewModel.sizeAnalyzer {
                        InstalledSizeAnalysisView(
                            viewModel: sizeAnalyzer,
                            analysis: viewModel.analysis
                        )
                    }
                    
                    SummaryCard(
                        title: "📂 Categories",
                        value: "\(viewModel.categoriesCount)",
                        subtitle: "Main groups"
                    )
                    
                    SummaryCard(
                        title: "📐 Architectures",
                        value: "\(viewModel.archs.number)",
                        subtitle: viewModel.archTypesDescription
                    )
                }
                .padding(.horizontal)
                
                if let apkAnalysis = viewModel.analysis as? APKAnalysis {
                    androidSummarySection(for: apkAnalysis)
                        .padding(.horizontal)
                }
                
                if viewModel.analysis.totalSize > 0 {
                    ExpandableGraphView(
                        analysis: viewModel.analysis
                    )
                    .id(viewModel.analysis.id)
                }

                // Dependency Graph Section (on demand)
                if let dependencyGraph = viewModel.analysis.dependencyGraph, !dependencyGraph.nodes.isEmpty {
                    DependencyGraphOnDemandSection(graph: dependencyGraph)
                        .padding(.horizontal)
                }
                
                HStack(alignment: .top, spacing: 24) {
                    // Pie chart
                    if viewModel.hasCategories {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Distribution by Category")
                                .font(.title3).bold()
                            
                            Chart(viewModel.categories) { category in
                                SectorMark(
                                    angle: .value("Size", category.totalSize),
                                    innerRadius: .ratio(0.55),
                                    outerRadius: selectedCategoryName == category.id ?
                                        .ratio(1) :
                                            .ratio(0.9),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(by: .value("Category", category.name))
                                .annotation(position: .overlay) { 
                                    Text("\(String(format: "%.0f", (Double(category.totalSize) / Double(viewModel.analysis.totalSize)) * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .bold()
                                }
                            }
                            .chartForegroundStyleScale(
                                domain: categoryColorDomain,
                                range: categoryColorRange
                            )
                            .frame(height: 240)
                            .chartLegend(position: .bottom, spacing: 12)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                    }
                    
                    // Bar chart for selected category
                    if let selectedCategoryName = selectedCategoryName {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top Files in \(selectedCategoryName)")
                                .font(.title3).bold()
                            
                            Chart(viewModel.topFiles(for: selectedCategoryName, limit: 5)) { item in
                                BarMark(
                                    x: .value("Size", item.size),
                                    y: .value("File", item.name)
                                )
                                .foregroundStyle(categoryColorScale[selectedCategoryName] ?? .accentColor)
                            }
                            .frame(height: 240)
                            .chartLegend(.hidden)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal)
                
                if viewModel.buildsForApp.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Build Size by Version")
                            .font(.title3).bold()
                        
                        Chart(viewModel.buildsForApp, id: \.id) { build in
                            let sizeMB = Double(build.totalSize) / 1_048_576.0
                            BarMark(
                                x: .value("Version", build.version ?? "Unknown"),
                                y: .value("Size (MB)", sizeMB)
                            )
                            .foregroundStyle(.blue)
                        }
                        .chartXScale(domain: viewModel.buildsForApp.map { $0.version ?? "Unknown" })
                        .frame(height: 260)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                    .padding(.horizontal)
                }
                
                // Collapsible sections
                VStack(spacing: 12) {
                    ForEach(filteredCategories) { category in
                        CollapsibleSection(
                            category: category,
                            action: {},
                            expandedSections: $expandedSections
                        )
                    }
                }
                .padding(.horizontal)
                
                TipsSection(tips: TipGenerator.generateTips(for: viewModel.analysis), baseURL: viewModel.tipsBaseURL)
                    .id(viewModel.analysis.id)
                    .padding(.top)
            }
            .padding(.vertical, 16)
        }
        .searchable(text: $searchText, prompt: "Search files...")
        .navigationTitle(viewModel.analysis.fileName)
        .onChange(of: expandedSections) {
            updateSelectedCategory()
        }
    }
    
    @State private var showAISummary: Bool = false
    
    private func updateSelectedCategory() {
        withAnimation {
            if let expandedID = expandedSections.first {
                selectedCategoryName = viewModel.categoryName(for: expandedID)
            } else {
                selectedCategoryName = nil
            }
        }
    }

    @ViewBuilder
    private func androidSummarySection(for analysis: APKAnalysis) -> some View {
        let stats = androidStats(for: analysis)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
            if let minSDK = analysis.minSDK, let targetSDK = analysis.targetSDK {
                SummaryCard(
                    title: "🎯 SDK Targets",
                    value: "\(analysis.minSDK ?? "—") ▸ \(analysis.targetSDK ?? "—")",
                    subtitle: "Min ▸ Target"
                )
            }
            
            SummaryCard(
                title: "📚 Dex vs Native",
                value: "\(stats.dexCount) dex / \(stats.nativeLibCount) so",
                subtitle: stats.abiSubtitle
            )
            
            SummaryCard(
                title: "🔐 Permissions",
                value: "\(analysis.permissions.count)",
                subtitle: "\(stats.dangerousPermissions) dangerous"
            )
        }
    }

    private func androidStats(for analysis: APKAnalysis) -> (dexCount: Int, nativeLibCount: Int, largestDexSize: Int64, dangerousPermissions: Int, abiSubtitle: String) {
        let files = analysis.rootFile.flattened(includeDirectories: false)
        let dexFiles = files.filter { $0.name.lowercased().hasSuffix(".dex") }
        let nativeLibs = files.filter { $0.name.lowercased().hasSuffix(".so") }
        let largestDex = dexFiles.map(\.size).max() ?? 0
        let dangerousPermissions = analysis.permissions.filter { perm in
            AndroidPermissionCatalog.dangerousPermissions.contains(perm)
        }.count
        let abiSubtitle: String
        let largestDexLabel = ByteCountFormatter.string(fromByteCount: largestDex, countStyle: .file)
        if analysis.supportedABIs.isEmpty {
            abiSubtitle = "Largest dex: \(largestDexLabel)"
        } else {
            abiSubtitle = "ABIs: \(analysis.supportedABIs.joined(separator: ", ")) · Dex max \(largestDexLabel)"
        }
        return (dexFiles.count, nativeLibs.count, largestDex, dangerousPermissions, abiSubtitle)
    }
}
