import SwiftUI
import AppKit

struct TipsSection: View {
    let tips: [Tip]
    let baseURL: URL?
    let imagePreviewLookup: [String: Data]
    @State private var expandedTips: Set<UUID> = []

    init(tips: [Tip], baseURL: URL?, imagePreviewLookup: [String: Data] = [:]) {
        self.tips = tips
        self.baseURL = baseURL
        self.imagePreviewLookup = imagePreviewLookup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("💡 Tips & Suggestions")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            ForEach(tips) { tip in
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        Text(emoji(for: tip.category))
                            .font(.title3)
                        VStack(alignment: .leading) {
                            Text(tip.category.rawValue)
                                .font(.headline)
                            Text(tip.text)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if !tip.subTips.isEmpty {
                            Button(action: {
                                toggle(tip: tip)
                            }) {
                                Image(systemName: expandedTips.contains(tip.id) ? "chevron.up" : "chevron.down")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .textSelection(.enabled)
                    
                    if expandedTips.contains(tip.id) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(tip.subTips) { subTip in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(emoji(for: subTip.category))
                                        .font(.body)
                                    VStack(alignment: .leading, spacing: 4) {
                                        let lines = subTip.text.split(whereSeparator: \.isNewline)
                                        ForEach(Array(lines.enumerated()), id: \.offset) { _, rawLine in
                                            let line = String(rawLine)
                                            let previewFile = isPathCandidate(line) ? previewFile(for: line) : nil
                                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                                if let previewFile {
                                                    Text(line)
                                                        .font(.body)
                                                        .foregroundColor(.secondary)
                                                        .modifier(HoverModifier(file: previewFile, isEnabled: true, showOnlyImage: true))
                                                } else {
                                                    Text(line)
                                                        .font(.body)
                                                        .foregroundColor(.secondary)
                                                }
                                                if isPathCandidate(line) {
                                                    Button(action: { reveal(path: line) }) {
                                                        Image(systemName: "folder")
                                                    }
                                                    .buttonStyle(.plain)
                                                    .font(.system(size: 12))
                                                    .help("Reveal in Finder")
                                                }
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.leading, 28)
                            }
                        }
                        .padding(.bottom)
                        .padding(.horizontal)
                        .textSelection(.enabled)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
                .padding(.horizontal)
            }
        }
    }
    
    private func toggle(tip: Tip) {
        if expandedTips.contains(tip.id) {
            expandedTips.remove(tip.id)
        } else {
            expandedTips.insert(tip.id)
        }
    }
    
    private func emoji(for category: TipCategory) -> String {
        switch category {
        case .optimization: return "🚀"
        case .warning: return "⚠️"
        case .info: return "ℹ️"
        case .size: return "📦"
        case .performance: return "⚡️"
        case .security: return "🔒"
        case .compatibility: return "✅"
        }
    }
    
    private func isPathCandidate(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        guard !s.isEmpty else { return false }
        // Heuristics: treat lines containing a slash as paths, but ignore summary lines
        if s.localizedCaseInsensitiveContains("potential saving") { return false }
        if s.hasPrefix("\u{2022}") { return false } // bullet
        return s.contains("/") || s.hasPrefix("/")
    }
    
    private func absoluteURL(for rawPath: String) -> URL? {
        guard let normalized = normalizedPath(from: rawPath) else { return nil }
        if normalized.hasPrefix("/") {
            return URL(fileURLWithPath: normalized)
        } else if let baseURL {
            return baseURL.appendingPathComponent(normalized)
        }
        return nil
    }
    
    private func normalizedPath(from rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private func reveal(path rawPath: String) {
        guard let initialURL = absoluteURL(for: rawPath) else { return }
        let fm = FileManager.default
        var candidate = initialURL
        var last = candidate.path
        while !fm.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            if parent.path == last { break }
            last = parent.path
            candidate = parent
        }
        guard fm.fileExists(atPath: candidate.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([candidate])
    }

    private func previewFile(for rawLine: String) -> FileInfo? {
        guard let data = imagePreviewData(for: rawLine) else { return nil }
        let normalized = normalizedPath(from: rawLine)
        var preview = FileInfo(
            path: normalized,
            fullPath: nil,
            name: normalized ?? rawLine.trimmingCharacters(in: .whitespacesAndNewlines),
            type: .assets,
            size: Int64(data.count),
            subItems: nil
        )
        preview.internalImageData = data
        return preview
    }

    private func imagePreviewData(for rawLine: String) -> Data? {
        guard !imagePreviewLookup.isEmpty else { return nil }
        var checkedKeys = Set<String>()

        func attemptLookup(_ key: String?) -> Data? {
            guard let key, !key.isEmpty, !checkedKeys.contains(key) else { return nil }
            checkedKeys.insert(key)
            return imagePreviewLookup[key]
        }

        let normalized = normalizedPath(from: rawLine)
        if let data = attemptLookup(normalized) {
            return data
        }
        if let normalized {
            let lastComponent = (normalized as NSString).lastPathComponent
            if let data = attemptLookup(lastComponent) {
                return data
            }
        }
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        if let data = attemptLookup(trimmed) {
            return data
        }
        let trimmedComponent = (trimmed as NSString).lastPathComponent
        if let data = attemptLookup(trimmedComponent) {
            return data
        }
        return nil
    }
}
