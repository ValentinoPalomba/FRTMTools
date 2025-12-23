import SwiftUI

struct ThirdPartyLibrariesListView: View {
    let libraries: [ThirdPartyLibraryInsight]
    
    private var sortedLibraries: [ThirdPartyLibraryInsight] {
        libraries.sorted { lhs, rhs in
            if lhs.estimatedSize == rhs.estimatedSize {
                return lhs.name < rhs.name
            }
            return lhs.estimatedSize > rhs.estimatedSize
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Third-party SDKs")
                .font(.title2.bold())
                .padding(.bottom, 8)
            
            if libraries.isEmpty {
                ContentUnavailableView("No SDKs Detected", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(sortedLibraries) { lib in
                            sdkRow(lib)
                            Divider()
                        }
                        Text("\(libraries.count) SDKs total • Estimated footprint \(formatSize(totalSize))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 520)
    }
    
    private var totalSize: Int64 {
        libraries.reduce(0) { $0 + max(0, $1.estimatedSize) }
    }
    
    @ViewBuilder
    private func sdkRow(_ lib: ThirdPartyLibraryInsight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lib.name)
                .font(.headline)
            HStack(spacing: 12) {
                Text("Version: \(lib.version ?? "Unknown")")
                Text("Size: \(formatSize(lib.estimatedSize))")
                if lib.hasManifestComponent {
                    Label("Manifest component", systemImage: "checkmark.shield")
                        .labelStyle(.iconOnly)
                        .foregroundColor(.green)
                        .help("Declared in AndroidManifest")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            if !lib.packageMatches.isEmpty {
                Text("Packages: \(lib.packageMatches.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formatSize(_ size: Int64) -> String {
        guard size > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
