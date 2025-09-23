
import SwiftUI

// MARK: - FileDiff + FileSection

struct FileSection: View {
    let title: String
    let files: [FileDiff]
    @Binding var expandedSections: Set<String>
    
    private var filesByExtension: [String: [FileDiff]] {
        Dictionary(grouping: files) { (file) -> String in
            if let ext = file.name.split(separator: ".").last {
                return ".\(String(ext))"
            } else {
                return "Other"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text("\(files.count)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Image(systemName: expandedSections.contains(title) ? "chevron.down" : "chevron.right")
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            }
            .buttonStyle(.plain)
            
            if expandedSections.contains(title) {
                VStack(spacing: 1) {
                    ForEach(filesByExtension.keys.sorted(), id: \.self) { extensionName in
                        FileExtensionGroupView(
                            extensionName: extensionName,
                            files: filesByExtension[extensionName]!
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: expandedSections)
    }
    
    private func toggle() {
        if expandedSections.contains(title) {
            expandedSections.remove(title)
        } else {
            expandedSections.insert(title)
        }
    }
}

struct FileExtensionGroupView: View {
    let extensionName: String
    let files: [FileDiff]
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Text("\(extensionName) (\(files.count))")
                        .font(.subheadline)
                        .padding(.leading)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .imageScale(.small)
                }
                .padding(8)
                .background(Color.black.opacity(0.1))
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(files) { file in
                        HStack {
                            Text(file.name)
                                .lineLimit(1)
                                .font(.subheadline)
                                .padding(.leading, 32)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: file.size1, countStyle: .file))
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text("→")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(ByteCountFormatter.string(fromByteCount: file.size2, countStyle: .file))
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(Color(NSColor.windowBackgroundColor))
                    }
                }
            }
        }
    }
}
