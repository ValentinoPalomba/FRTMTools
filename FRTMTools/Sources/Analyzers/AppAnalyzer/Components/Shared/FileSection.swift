
import SwiftUI

// MARK: - FileDiff + FileSection

struct FileSection: View {
    let title: String
    let files: [FileDiff]
    @Binding var expandedSections: Set<String>
    @Environment(\.theme) private var theme
    
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
                        .foregroundStyle(.secondary)
                    Image(systemName: expandedSections.contains(title) ? "chevron.down" : "chevron.right")
                        .foregroundStyle(theme.palette.accent)
                        .imageScale(.small)
                }
                .padding()
                .dsSurface(.surface, cornerRadius: 12, border: true, shadow: false)
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
    @Environment(\.theme) private var theme
    
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
                .background(theme.palette.border.opacity(theme.colorScheme == .dark ? 0.35 : 0.18))
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
                                .foregroundStyle(.blue)
                            Text("→")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(ByteCountFormatter.string(fromByteCount: file.size2, countStyle: .file))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(theme.palette.background)
                    }
                }
            }
        }
    }
}
