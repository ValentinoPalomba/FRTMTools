import SwiftUI
import UniformTypeIdentifiers

struct CollapsibleSection: View {
    let category: CategoryResult
    let action: () -> Void
    @Binding var expandedSections: Set<String>
    
    @State private var showExporter: Bool = false
    @State private var exportURL: URL?
    @State private var showCategoryInfo: Bool = false

    private func emoji(for category: String) -> String {
        let lowercasedCategory = category.lowercased()

        switch lowercasedCategory {
        case "frameworks": return "📦"
        case "binary", "binaries": return "⚙️"
        case "assets": return "🎨"
        case "resources": return "📁"
        default: return "📄"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    action()
                    toggle()
                }) {
                    HStack {
                        Text("\(emoji(for: category.name)) \(category.name)")
                            .font(.headline)
                        Spacer()
                        Text(category.sizeText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Image(systemName: expandedSections.contains(category.id) ? "chevron.up" : "chevron.down")
                    }
                }
                .buttonStyle(.plain)
                
                if let info = AndroidCategoryInfo.info(for: category.name) {
                    Button {
                        showCategoryInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showCategoryInfo) {
                        AndroidCategoryInfoPopover(info: info)
                            .frame(width: 360)
                    }
                }
                
                Button {
                    if let url = category.items.exportAsCSV(fileName: category.name) {
                        exportURL = url
                        showExporter = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .contentShape(Rectangle())
            
            if expandedSections.contains(category.id) {
                LazyVStack(spacing: 1) {
                    ForEach(category.items.sorted(by: { $0.size > $1.size })) { item in
                        FileTreeView(file: item)
                            .padding(.leading, 10)
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 12, bottom: 12, trailing: 12))
                .background(Color(NSColor.controlBackgroundColor))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cornerRadius(12)
        .fileExporter(
            isPresented: $showExporter,
            document: CSVDocument(url: exportURL),
            contentType: .commaSeparatedText,
            defaultFilename: "\(category.name)_files.csv"
        ) { result in
            if case .failure(let error) = result {
                print("Error exporting CSV: \(error)")
            }
        }
    }
    
    private func toggle() {
        
        if expandedSections.contains(category.id) {
            expandedSections.remove(category.id)
        } else {
            expandedSections.removeAll()
            expandedSections.insert(category.id)
        }
    }
}

extension Array where Element == FileInfo {
    func exportAsCSV(fileName: String) -> URL? {
        var csvText = "File Name,Size\n"
        
        for file in self {
            let sizeString = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
            csvText += "\(file.name),\(sizeString)\n"
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(fileName)_export.csv")
        
        do {
            try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Error saving CSV: \(error)")
        }
        return nil
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var url: URL?

    init(url: URL?) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url = url else {
            throw CocoaError(.fileWriteUnknown)
        }
        let data = try Data(contentsOf: url)
        return .init(regularFileWithContents: data)
    }
}
