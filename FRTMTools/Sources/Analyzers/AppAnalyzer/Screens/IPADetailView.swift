import SwiftUI
import Charts

struct DetailView: View {
    let analysis: IPAAnalysis
    var ipaViewModel: IPAViewModel
    
    init(
        analysis: IPAAnalysis,
        ipaViewModel: IPAViewModel
    ) {
        self.analysis = analysis
        self.ipaViewModel = ipaViewModel
    }
    @State private var expandedSections: Set<String> = []
    @State private var selectedCategoryName: String? = nil
    
    @State private var searchText = ""

    private let categoryColorScale: [String: Color] = [
        "Resources": .green,
        "Frameworks": .blue,
        "Binary": .red,
        "Assets": .purple,
        "Bundles": .orange
    ]

    private var categoryColorDomain: [String] { Array(categoryColorScale.keys) }
    private var categoryColorRange: [Color] { categoryColorDomain.compactMap { categoryColorScale[$0] } }

    private var categories: [CategoryResult] {
        ipaViewModel.categories(for: analysis)
    }
    
    private var archs: ArchsResult {
        ipaViewModel.archs(for: analysis)
    }
    
    private var buildsForApp: [IPAAnalysis] {
        let key = analysis.executableName ?? analysis.fileName
        let builds = ipaViewModel.groupedAnalyses[key] ?? []
        return builds.sorted {
            let vA = $0.version ?? "0"
            let vB = $1.version ?? "0"
            return vA.compare(vB, options: .numeric) == .orderedAscending
        }
    }

    private var filteredCategories: [CategoryResult] {
        if searchText.isEmpty {
            return ipaViewModel.categories
        }
        
        return ipaViewModel.categories.compactMap { category in
            let filteredItems = category.items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            if filteredItems.isEmpty {
                return nil
            }
            return CategoryResult(type: category.type, totalSize: filteredItems.reduce(0) { $0 + $1.size }, items: filteredItems)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // Grid overview
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    SummaryCard(
                        title: "📦 Uncompressed Size",
                        value: ByteCountFormatter.string(fromByteCount: analysis.totalSize, countStyle: .file),
                        subtitle: analysis.fileName
                    )
                    
                    InstalledSizeAnalysisView(
                        viewModel: ipaViewModel,
                        analysis: analysis
                    )
                    
                    SummaryCard(
                        title: "📂 Categories",
                        value: "\(ipaViewModel.categories.count)",
                        subtitle: "Main groups"
                    )
                    
                    SummaryCard(
                        title: "📐 Architectures",
                        value: "\(ipaViewModel.archs.number)",
                        subtitle: ipaViewModel.archs.types.joined(separator: ", ")
                    )
                }
                .padding(.horizontal)
                
                if analysis.totalSize > 0 {
                    ExpandableGraphView(
                        analysis: analysis
                    )
                    .id(analysis.id)
                }

                // Dependency Graph Section (on demand)
                if let dependencyGraph = analysis.dependencyGraph, !dependencyGraph.nodes.isEmpty {
                    DependencyGraphOnDemandSection(graph: dependencyGraph)
                        .padding(.horizontal)
                }
                
                HStack(alignment: .top, spacing: 24) {
                    // Pie chart
                    if !ipaViewModel.categories.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Distribution by Category")
                                .font(.title3).bold()
                            
                            Chart(ipaViewModel.categories) { category in
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
                                    Text("\(String(format: "%.0f", (Double(category.totalSize) / Double(analysis.totalSize)) * 100))%")
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
                            
                            Chart(topFiles(for: selectedCategoryName, limit: 5)) { item in
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
                
                if buildsForApp.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Build Size by Version")
                            .font(.title3).bold()
                        
                        Chart(buildsForApp, id: \.id) { build in
                            let sizeMB = Double(build.totalSize) / 1_048_576.0
                            BarMark(
                                x: .value("Version", build.version ?? "Unknown"),
                                y: .value("Size (MB)", sizeMB)
                            )
                            .foregroundStyle(.blue)
                        }
                        .chartXScale(domain: buildsForApp.map { $0.version ?? "Unknown" })
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
                
                TipsSection(tips: TipGenerator.generateTips(for: analysis), baseURL: ipaViewModel.tipsBaseURL)
                    .id(analysis.id)
                    .padding(.top)
            }
            .padding(.vertical, 16)
        }
        .searchable(text: $searchText, prompt: "Search files...")
        .navigationTitle(analysis.fileName)
        .onChange(of: expandedSections) {
            updateSelectedCategory()
        }
    }
    
    @State private var showAISummary: Bool = false
    
    private func updateSelectedCategory() {
        withAnimation {
            if let expandedID = expandedSections.first {
                selectedCategoryName = ipaViewModel.categories.first { $0.id == expandedID }?.name
            } else {
                selectedCategoryName = nil
            }
        }
    }

    private func topFiles(for categoryName: String, limit: Int) -> [FileInfo] {
        guard let category = ipaViewModel.categories.first(where: { $0.name == categoryName }) else { return [] }
        return Array(category.items.sorted(by: { $0.size > $1.size }).prefix(limit))
    }
    
}

struct DependencyGraphOnDemandSection: View {
    let graph: DependencyGraph

    @State private var isGraphVisible = false
    @State private var isPreparingGraph = false
    @State private var renderToken = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            if isGraphVisible {
                graphView
            } else {
                placeholder
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05))
        )
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dependency Graph")
                    .font(.title3)
                    .bold()
                Text("Genera il grafo solo quando serve così la schermata resta fluida.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGraphVisible {
                HStack(spacing: 12) {
                    Button(action: reloadLayout) {
                        Label("Rigenera", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)

                    Button(action: hideGraph) {
                        Label("Chiudi", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(Color(NSColor.quaternaryLabelColor))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "bolt.horizontal.circle")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.accentColor)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Grafo su richiesta")
                        .font(.headline)
                    Text("Il rendering è pesante. Premi il bottone qui sotto quando vuoi vedere le dipendenze.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            if isPreparingGraph {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Sto preparando il grafo...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            } else {
                Button(action: prepareGraph) {
                    Label("Genera grafo", systemImage: "play.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Text("Potrai richiuderlo o rigenerarlo in qualsiasi momento.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        )
    }

    private var graphView: some View {
        DependencyGraphView(graph: graph)
            .id(renderToken)
            .frame(height: 600)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08))
            )
    }

    private func prepareGraph() {
        guard !isPreparingGraph else { return }
        isPreparingGraph = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            renderToken = UUID()
            isGraphVisible = true
            isPreparingGraph = false
        }
    }

    private func hideGraph() {
        isGraphVisible = false
    }

    private func reloadLayout() {
        renderToken = UUID()
    }
}

