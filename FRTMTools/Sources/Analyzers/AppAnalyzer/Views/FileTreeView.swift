
import SwiftUI

struct FileTreeView: View {
    let file: FileInfo

    var body: some View {
        if let items = file.subItems, !items.isEmpty {
            DisclosureGroup {
                LazyVStack(spacing: 5) {
                    ForEach(items) { item in
                        FileTreeView(file: item)
                            .padding(.horizontal, 10)
                    }
                }
            } label: {
                FileRow(file: file)
            }
        } else {
            FileRow(file: file)
        }
    }
}

struct FileRow: View {
    let file: FileInfo

    var body: some View {
        HStack {
            Image(systemName: icon(for: file.type))
                .frame(width: 20)
            Text(file.name)
                .modifier(
                    HoverImageModifier(file: file, isEnabled: (file.internalImageData != nil) ? true : false)
                )
            Spacer()
            Text(format(bytes: file.size))
                .font(.system(.body, design: .monospaced))
        }
        
        .padding(.vertical, 4)
    }
    
    private func icon(for type: FileType) -> String {
        switch type {
        case .file: return "doc"
        case .directory: return "folder"
        case .app: return "app.fill"
        case .framework: return "shippingbox.fill"
        case .bundle: return "archivebox.fill"
        case .assets: return "photo.on.rectangle.angled"
        case .binary: return "terminal.fill"
        case .plist: return "doc.text"
        case .lproj: return "text.book.closed.fill"
        }
    }
    
    private func format(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
