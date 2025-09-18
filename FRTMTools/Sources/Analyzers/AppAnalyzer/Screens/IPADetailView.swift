import SwiftUI
import Charts

struct DetailView: View {
    let analysis: IPAAnalysis
    
    @State private var expandedSections: Set<String> = []
    @State private var selectedCategoryName: String? = nil
    @ObservedObject var ipaViewModel: IPAViewModel
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
        return CategoryGenerator.generateCategories(from: analysis.rootFile)
    }

    private var filteredCategories: [CategoryResult] {
        if searchText.isEmpty {
            return categories
        }
        
        return categories.compactMap { category in
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
                        value: "\(categories.count)",
                        subtitle: "Main groups"
                    )
                }
                .padding(.horizontal)
                
                HStack(alignment: .top, spacing: 24) {
                    // Pie chart
                    if !categories.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Distribution by Category")
                                .font(.title3).bold()
                            
                            Chart(categories) { category in
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
                
                // Tips Section
                TipsSection(tips: TipGenerator.generateTips(for: analysis))
                    .padding(.top)
            }
            .padding(.vertical, 16)
        }
        .searchable(text: $searchText, prompt: "Search files...")
        .navigationTitle(analysis.fileName)
//        .toolbar {
//            ToolbarItem(placement: .automatic) {
//                Button(action: {
//                    showAISummary = true
//                }) {
//                    Label("AI Summary", systemImage: "sparkles")
//                }
//            }
//        }
//        .sheet(isPresented: $showAISummary) {
//            AIMagicView(input: generateAnalysisSummaryPrompt(analysis: analysis), systemPrompt: ConstantsPrompt.ipaAnalysisPrompt)
//        }
        .onChange(of: expandedSections) {
            updateSelectedCategory()
        }
    }
    
    @State private var showAISummary: Bool = false
    
    private func updateSelectedCategory() {
        withAnimation {
            if let expandedID = expandedSections.first {
                selectedCategoryName = categories.first { $0.id == expandedID }?.name
            } else {
                selectedCategoryName = nil
            }
        }
    }

    private func topFiles(for categoryName: String, limit: Int) -> [FileInfo] {
        guard let category = categories.first(where: { $0.name == categoryName }) else { return [] }
        return Array(category.items.sorted(by: { $0.size > $1.size }).prefix(limit))
    }
    
    private func generateAnalysisSummaryPrompt(analysis: IPAAnalysis) -> String {
        var prompt = ""
        
        prompt += "File Name: \(analysis.fileName)\n"
        prompt += "Total Size: \(ByteCountFormatter.string(fromByteCount: analysis.totalSize, countStyle: .file))\n"
        
        let allFiles = categories.flatMap { $0.items }
        prompt += "Total Files: \(allFiles.count)\n"
        if !allFiles.isEmpty {
            let avgSize = allFiles.map { $0.size }.reduce(0, +) / Int64(allFiles.count)
            prompt += "Average File Size: \(ByteCountFormatter.string(fromByteCount: avgSize, countStyle: .file))\n\n"
        }
        
        // Categorie
        prompt += "Categories:\n"
        for category in categories {
            let percentage = Double(category.totalSize) / Double(analysis.totalSize) * 100
            prompt += "- \(category.name): \(ByteCountFormatter.string(fromByteCount: category.totalSize, countStyle: .file)) (\(String(format: "%.2f", percentage)))%\n"
            
            if !category.items.isEmpty {
                prompt += "  Top 3 files in \(category.name):\n"
                for item in category.items.sorted(by: { $0.size > $1.size }).prefix(3) {
                    prompt += "  - \(item.name): \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))\n"
                }
            }
        }
        
        // Top 10 globali
        let topGlobal = allFiles.filter { $0.subItems == nil }.sorted(by: { $0.size > $1.size }).prefix(10)
        if !topGlobal.isEmpty {
            prompt += "\nTop 10 largest files overall:\n"
            for item in topGlobal {
                prompt += "- \(item.name): \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))\n"
            }
        }
        
        return prompt
    }
}
