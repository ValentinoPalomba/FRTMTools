import SwiftUI
import Charts

struct ComparisonDetail<Analysis: AppAnalysis>: View {
    let first: Analysis
    let second: Analysis
    
    @State private var isLoading = true
    @State private var comparisonResult: ComparisonResult?
    @State private var reportLanguage: ReportLanguage = .english
    @State private var showAIChat = false

    @State private var expandedSections: Set<String> = ["Modificati", "Aggiunti", "Rimossi"]
    @State private var searchText: String = ""
    
    var body: some View {
        ZStack {
            if isLoading {
                LoaderView(title: "Comparing files...", subtitle: "This may take a moment.")
            } else if let result = comparisonResult {
                ScrollView {
                    VStack(spacing: 24) {
                        comparisonHeader(result: result)
                        
                        // MARK: - Overview Categorie
                        VStack(alignment: .leading, spacing: 16) {
                            Text("📊 Category Overview")
                                .font(.title2).bold()
                                .padding(.horizontal)
                            
                            LazyVStack(spacing: 12) {
                                ForEach(result.categories) { category in
                                    let size1 = category.size1
                                    let size2 = category.size2
                                    let diff = size2 - size1
                                    
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(category.name)
                                                .font(.headline)
                                            Text("Before vs After")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(ByteCountFormatter.string(fromByteCount: size1, countStyle: .file))
                                                    .foregroundColor(.blue)
                                                Text("→")
                                                    .foregroundColor(.secondary)
                                                Text(ByteCountFormatter.string(fromByteCount: size2, countStyle: .file))
                                                    .foregroundColor(.orange)
                                            }
                                            if diff != 0 {
                                                Text("\(diff > 0 ? "➕" : "➖") \(ByteCountFormatter.string(fromByteCount: abs(diff), countStyle: .file))")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(diff > 0 ? .red : .green)
                                            }
                                        }
                                    }
                                    .padding()
                                    .dsSurface(.surface, cornerRadius: 14, border: true, shadow: true)
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // MARK: - Grafico categorie comparativo
                        VStack(alignment: .leading, spacing: 12) {
                            Text("📈 Category Comparison")
                                .font(.title3).bold()
                                .padding()
                            
                            VStack(spacing: 12) {
                                // 🔹 Legenda
                                HStack(spacing: 20) {
                                    HStack {
                                        Circle().fill(Color.blue).frame(width: 12, height: 12)
                                        Text(first.fileName)
                                            .font(.subheadline)
                                            .foregroundColor(.blue)
                                    }
                                    HStack {
                                        Circle().fill(Color.orange).frame(width: 12, height: 12)
                                        Text(second.fileName)
                                            .font(.subheadline)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            .padding()
                            
                            Chart {
                                ForEach(result.categories) { category in
                                    BarMark(
                                        x: .value("Size", category.size1),
                                        y: .value("Category", category.name)
                                    )
                                    .foregroundStyle(.blue)
                                    
                                    BarMark(
                                        x: .value("Size", category.size2),
                                        y: .value("Category", category.name)
                                    )
                                    .foregroundStyle(.orange)
                                }
                            }
                            .frame(height: 260)
                            .padding()
                        }
                        .dsSurface(.surface, cornerRadius: 16, border: true, shadow: true)
                        .padding(.horizontal)
                        
                        // MARK: - Diff Dettagliato con ricerca
                        VStack(alignment: .leading, spacing: 16) {
                            Text("🔍 File Differences")
                                .font(.title3).bold()
                                .padding(.horizontal)
                            
                            // Barra di ricerca
                            TextField("Search files...", text: $searchText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                FileSection(
                                    title: "📝 Modified",
                                    files: result.modifiedFiles.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) },
                                    expandedSections: $expandedSections
                                )
                                FileSection(
                                    title: "🆕 Added",
                                    files: result.addedFiles.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) },
                                    expandedSections: $expandedSections
                                )
                                FileSection(
                                    title: "❌ Removed",
                                    files: result.removedFiles.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) },
                                    expandedSections: $expandedSections
                                )
                            }
                            .padding(.horizontal)
                        }

                        // MARK: - Textual Report
                        if let firstIPAAnalysis = first as? IPAAnalysis, let secondIPAAnalysis = second as? IPAAnalysis {
                            ComparisonReportView(
                                viewModel:
                                    ComparisonReportViewModel(first: firstIPAAnalysis, second: secondIPAAnalysis, result: result),
                                language: $reportLanguage
                            )
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle("Comparison 🆚")
        .task {
            await processComparison()
        }
        .sheet(isPresented: $showAIChat) {
            if let result = comparisonResult {
                let firstDetails = analysisContext(for: first)
                let secondDetails = analysisContext(for: second)
                let context = ComparisonContextBuilder()
                    .buildContext(
                        first: first,
                        second: second,
                        result: result,
                        firstAnalysisContext: firstDetails.context,
                        secondAnalysisContext: secondDetails.context,
                        firstCategories: firstDetails.categories,
                        secondCategories: secondDetails.categories
                    )
                AIChatView(context: context)
                    .frame(minWidth: 640, minHeight: 560)
            } else {
                Text("Comparison still running…")
                    .padding()
            }
        }
    }
    
    @ViewBuilder
    private func comparisonHeader(result: ComparisonResult) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Comparison Overview")
                    .font(.title2).bold()
                Text("\(first.fileName) → \(second.fileName)")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Text("Modified \(result.modifiedFiles.count) · Added \(result.addedFiles.count) · Removed \(result.removedFiles.count)")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            Spacer()
            Button {
                showAIChat = true
            } label: {
                Label("AI Insights", systemImage: "sparkles")
            }
            .help("Ask questions about this comparison")
        }
        .padding(.horizontal)
    }
    
    private func analysisContext(for analysis: Analysis) -> (context: AnalysisContext, categories: [CategoryResult]) {
        let categories = CategoryGenerator.generateCategories(from: analysis.rootFile)
        let archs = ArchsAnalyzer.generateCategories(from: analysis.rootFile)
        let tips = TipGenerator.generateTips(for: analysis)
        let context = AnalysisContextBuilder()
            .buildContext(
                for: analysis,
                categories: categories,
                tips: tips,
                archs: archs
            )
        return (context, categories)
    }
    
    private func processComparison() async {
        let result = await Task.detached {
            ComparisonAnalyzer.compare(first: first, second: second)
        }.value
        
        await MainActor.run {
            self.comparisonResult = result
            self.isLoading = false
        }
    }
}
