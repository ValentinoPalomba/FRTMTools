
import SwiftUI
import Charts

struct ComparisonDetail: View {
    let first: IPAAnalysis
    let second: IPAAnalysis
    
    @State private var expandedSections: Set<String> = ["Modificati", "Aggiunti", "Rimossi"]
    @State private var searchText: String = ""
    
    private var firstFiles: [FileInfo] { flatten(file: first.rootFile) }
    private var secondFiles: [FileInfo] { flatten(file: second.rootFile) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // MARK: - Overview Categorie
                VStack(alignment: .leading, spacing: 16) {
                    Text("📊 Category Overview")
                        .font(.title2).bold()
                        .padding(.horizontal)
                    
                    LazyVStack(spacing: 12) {
                        ForEach(getAllCategories()) { category in
                            let size1 = getSizeForAnalysis(first, category: category.name)
                            let size2 = getSizeForAnalysis(second, category: category.name)
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
                        ForEach(getAllCategories()) { category in
                            BarMark(
                                x: .value("Size", getSizeForAnalysis(first, category: category.name)),
                                y: .value("Category", category.name)
                            )
                            .foregroundStyle(.blue)
                            
                            BarMark(
                                x: .value("Size", getSizeForAnalysis(second, category: category.name)),
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
                            files: modifiedFiles().filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) },
                            expandedSections: $expandedSections
                        )
                        FileSection(
                            title: "🆕 Added",
                            files: addedFiles().filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) },
                            expandedSections: $expandedSections
                        )
                        FileSection(
                            title: "❌ Removed",
                            files: removedFiles().filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) },
                            expandedSections: $expandedSections
                        )
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("Comparison 🆚")
//        .toolbar {
//            ToolbarItem(placement: .automatic) {
//                Button(action: {
//                    showAISummary = true
//                }) {
//                    Label("AI Compare", systemImage: "sparkles")
//                }
//            }
//        }
//        .sheet(isPresented: $showAISummary) {
//            AIMagicView(input: generateComparisonSummaryPrompt(first: first, second: second), systemPrompt: ConstantsPrompt.ipaComparisonPrompt)
//        }
    }
    
    @State private var showAISummary: Bool = false
    
    // MARK: - Helpers
    private func flatten(file: FileInfo) -> [FileInfo] {
        var files: [FileInfo] = []
        if let subItems = file.subItems {
            // Don't add the directory itself, only its contents
            for subItem in subItems {
                files.append(contentsOf: flatten(file: subItem))
            }
        } else {
            files.append(file)
        }
        return files
    }

    private func getAllCategories() -> [CategoryInfo] {
        let firstCats = CategoryGenerator.generateCategories(from: first.rootFile).map { CategoryInfo(name: $0.name, size: $0.totalSize) }
        let secondCats = CategoryGenerator.generateCategories(from: second.rootFile).map { CategoryInfo(name: $0.name, size: $0.totalSize) }
        let allNames = Set(firstCats.map { $0.name } + secondCats.map { $0.name })
        return allNames.map { name in
            let size = firstCats.first { $0.name == name }?.size ?? secondCats.first { $0.name == name }?.size ?? 0
            return CategoryInfo(name: name, size: size)
        }.sorted { $0.name < $1.name }
    }
    
    private func getSizeForAnalysis(_ analysis: IPAAnalysis, category: String) -> Int64 {
        return CategoryGenerator.generateCategories(from: analysis.rootFile).first { $0.name == category }?.totalSize ?? 0
    }
    
    private func getSizeForFile(_ files: [FileInfo], fileName: String) -> Int64 {
        return files.first { $0.name == fileName }?.size ?? 0
    }
    
    private func modifiedFiles() -> [FileDiff] {
        let allFileNames = Set(firstFiles.map { $0.name } + secondFiles.map { $0.name })
        return allFileNames.compactMap { name in
            let size1 = getSizeForFile(firstFiles, fileName: name)
            let size2 = getSizeForFile(secondFiles, fileName: name)
            if size1 > 0 && size2 > 0 && size1 != size2 {
                return FileDiff(name: name, size1: size1, size2: size2)
            }
            return nil
        }
    }
    
    private func addedFiles() -> [FileDiff] {
        let files1Names = Set(firstFiles.map { $0.name })
        return secondFiles.compactMap { file in
            if !files1Names.contains(file.name) {
                return FileDiff(name: file.name, size1: 0, size2: file.size)
            }
            return nil
        }
    }
    
    private func removedFiles() -> [FileDiff] {
        let files2Names = Set(secondFiles.map { $0.name })
        return firstFiles.compactMap { file in
            if !files2Names.contains(file.name) {
                return FileDiff(name: file.name, size1: file.size, size2: 0)
            }
            return nil
        }
    }
    
    private func generateComparisonSummaryPrompt(first: IPAAnalysis, second: IPAAnalysis) -> String {
        var prompt = ""
        
        prompt += "Comparing IPA files:\n"
        prompt += "- First IPA: \(first.fileName) (Total Size: \(ByteCountFormatter.string(fromByteCount: first.totalSize, countStyle: .file)))\n"
        prompt += "- Second IPA: \(second.fileName) (Total Size: \(ByteCountFormatter.string(fromByteCount: second.totalSize, countStyle: .file)))\n\n"
        
        let totalDiff = second.totalSize - first.totalSize
        prompt += "Overall Size Change: \(totalDiff > 0 ? "Increased by" : "Decreased by") \(ByteCountFormatter.string(fromByteCount: abs(totalDiff), countStyle: .file))\n\n"
        
        prompt += "Category-wise Differences:\n"
        for category in getAllCategories() {
            let size1 = getSizeForAnalysis(first, category: category.name)
            let size2 = getSizeForAnalysis(second, category: category.name)
            let diff = size2 - size1
            if diff != 0 {
                prompt += "- \(category.name): \(ByteCountFormatter.string(fromByteCount: size1, countStyle: .file)) -> \(ByteCountFormatter.string(fromByteCount: size2, countStyle: .file)) (\(diff > 0 ? "➕" : "➖") \(ByteCountFormatter.string(fromByteCount: abs(diff), countStyle: .file)))\n"
            }
        }
        prompt += "\n"
        
        let added = addedFiles()
        if !added.isEmpty {
            prompt += "Newly Added Files/Frameworks:\n"
            for file in added {
                prompt += "- \(file.name) (\(ByteCountFormatter.string(fromByteCount: file.size2, countStyle: .file)))\n"
            }
            prompt += "\n"
        }
        
        let removed = removedFiles()
        if !removed.isEmpty {
            prompt += "Removed Files/Frameworks:\n"
            for file in removed {
                prompt += "- \(file.name) (\(ByteCountFormatter.string(fromByteCount: file.size1, countStyle: .file)))\n"
            }
            prompt += "\n"
        }
        
        let modified = modifiedFiles()
        if !modified.isEmpty {
            prompt += "Modified Files (Size Change):\n"
            for file in modified {
                let diff = file.size2 - file.size1
                prompt += "- \(file.name): \(ByteCountFormatter.string(fromByteCount: file.size1, countStyle: .file)) -> \(ByteCountFormatter.string(fromByteCount: file.size2, countStyle: .file)) (\(diff > 0 ? "➕" : "➖") \(ByteCountFormatter.string(fromByteCount: abs(diff), countStyle: .file)))\n"
            }
            prompt += "\n"
        }
        
        prompt += "Please provide a summary of the main differences, list any significant added frameworks, and offer optimization advice based on this comparison."
        
        return prompt
    }
}

struct CategoryInfo: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
}
