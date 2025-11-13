import SwiftUI
import Charts

struct FileInfoSequence: Sequence, IteratorProtocol {
    private var stack: [FileInfo]

    init(root: FileInfo) {
        self.stack = [root]
    }

    mutating func next() -> FileInfo? {
        while !stack.isEmpty {
            let current = stack.removeLast()
            if let children = current.subItems {
                stack.append(contentsOf: children)
            } else {
                return current
            }
        }
        return nil
    }
}


struct ComparisonDetail<Analysis: AppAnalysis>: View {
    let first: Analysis
    let second: Analysis
    
    @State private var isLoading = true
    @State private var comparisonResult: ComparisonResult?
    @State private var reportLanguage: ReportLanguage = .english

    @State private var expandedSections: Set<String> = ["Modificati", "Aggiunti", "Rimossi"]
    @State private var searchText: String = ""
    
    var body: some View {
        ZStack {
            if isLoading {
                LoaderView(title: "Comparing files...", subtitle: "This may take a moment.")
            } else if let result = comparisonResult {
                ScrollView {
                    VStack(spacing: 24) {
                        
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
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(Color(NSColor.controlBackgroundColor))
                                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                                    )
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
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
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
    }
    
    private func processComparison() async {
        let result = await Task.detached { () -> ComparisonResult in
            // Load files in parallel
            async let firstFiles = Array(FileInfoSequence(root: first.rootFile))
            async let secondFiles = Array(FileInfoSequence(root: second.rootFile))
            
            let (files1, files2) = await (firstFiles, secondFiles)
            
            // --- Categories ---
            let firstCats = CategoryGenerator.generateCategories(
                from: first.rootFile
            )
            let secondCats = CategoryGenerator.generateCategories(from: second.rootFile)
            let allCatNames = Set(firstCats.map { $0.name } + secondCats.map { $0.name })
            
            let categories = allCatNames.map { name -> ComparisonCategory in
                let size1 = firstCats.first { $0.name == name }?.totalSize ?? 0
                let size2 = secondCats.first { $0.name == name }?.totalSize ?? 0
                return ComparisonCategory(name: name, size1: size1, size2: size2)
            }.sorted { $0.name < $1.name }

            // --- File Diffs ---
            let files1Set = Dictionary(files1.map { ($0.name, $0.size) }, uniquingKeysWith: { (first, _) in first })
            let files2Set = Dictionary(files2.map { ($0.name, $0.size) }, uniquingKeysWith: { (first, _) in first })
            let allFileNames = Set(files1Set.keys).union(files2Set.keys)

            var modifiedFiles: [FileDiff] = []
            var addedFiles: [FileDiff] = []
            var removedFiles: [FileDiff] = []

            for name in allFileNames {
                let size1 = files1Set[name]
                let size2 = files2Set[name]

                if let s1 = size1, let s2 = size2 {
                    if s1 != s2 {
                        modifiedFiles.append(FileDiff(name: name, size1: s1, size2: s2))
                    }
                } else if size1 == nil, let s2 = size2 {
                    addedFiles.append(FileDiff(name: name, size1: 0, size2: s2))
                } else if let s1 = size1, size2 == nil {
                    removedFiles.append(FileDiff(name: name, size1: s1, size2: 0))
                }
            }
            
            return ComparisonResult(
                categories: categories,
                modifiedFiles: modifiedFiles.sorted { $0.name < $1.name },
                addedFiles: addedFiles.sorted { $0.name < $1.name },
                removedFiles: removedFiles.sorted { $0.name < $1.name }
            )
        }.value
        
        await MainActor.run {
            self.comparisonResult = result
            self.isLoading = false
        }
    }
}

struct ComparisonResult {
    let categories: [ComparisonCategory]
    let modifiedFiles: [FileDiff]
    let addedFiles: [FileDiff]
    let removedFiles: [FileDiff]
}

struct ComparisonCategory: Identifiable {
    let id = UUID()
    let name: String
    let size1: Int64
    let size2: Int64
}
