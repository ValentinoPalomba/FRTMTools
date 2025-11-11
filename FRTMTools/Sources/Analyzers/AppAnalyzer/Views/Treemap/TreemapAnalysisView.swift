import SwiftUI
import AppKit

struct TreemapAnalysisView: View {
    let root: FileInfo
    let baseURL: URL?
    @State private var navigationStack: [FileInfo] = []
    
    init(root: FileInfo, baseURL: URL? = nil) {
        self.root = root
        self.baseURL = baseURL
        self._navigationStack = State(initialValue: [])
    }
    
    private var currentRoot: FileInfo {
        navigationStack.last ?? root
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if !navigationStack.isEmpty {
                HStack {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if !navigationStack.isEmpty {
                                navigationStack.removeLast()
                            }
                        }
                    }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .padding(.horizontal)
                    .buttonStyle(.bordered)
                    
                    Text(currentRoot.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                }
                .padding(4)
            }
            
            GeometryReader { geometry in
                TreemapContainerView(
                    file: currentRoot,
                    rect: geometry.frame(in: .local),
                    level: 0,
                    maxDepth: 1,
                    baseURL: baseURL
                ) { tappedFile in
                    withAnimation(.easeInOut) {
                        navigationStack.append(tappedFile)
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
            }
        }
    }
}

private struct TreemapContainerView: View {
    let file: FileInfo
    let rect: CGRect
    let level: Int
    let maxDepth: Int
    let baseURL: URL?
    var onTap: ((FileInfo) -> Void)?
    
    static var smallChildrenName = "[Other Files]"
    
    private func effectiveMaxDepth(for file: FileInfo, baseMaxDepth: Int) -> Int {
        switch file.name {
            case "Frameworks", "Resources":
                return 2
            default:
                return baseMaxDepth
        }
    }
    
    private var children: [FileInfo] {
        guard let subItems = file.subItems, !subItems.isEmpty else { return [] }
        
        if file.name == TreemapContainerView.smallChildrenName {
            // Caso speciale: non ricreo altri "[Other Files]"
            return subItems
        } else {
            let threshold = max(4096, file.size / 1000)
            let (largeChildren, smallChildren) = partition(subItems: subItems, threshold: threshold)
            return buildChildren(largeChildren: largeChildren, smallChildren: smallChildren)
        }
    }
    
    var body: some View {
        let allowedMaxDepth = effectiveMaxDepth(for: file, baseMaxDepth: maxDepth)
        
        if !children.isEmpty, level < allowedMaxDepth {
            let values = children.map { Double($0.size) }
            let treemap = YMTreeMap(withValues: values)
            let childRects = treemap.tessellate(inRect: rect)
            
            ForEach(Array(children.enumerated()), id: \.offset) { (index, child) in
                if index < childRects.count {
                    let childRect = childRects[index]
                    TreemapContainerView(
                        file: child,
                        rect: childRect,
                        level: level + 1,
                        maxDepth: maxDepth,
                        baseURL: baseURL,
                        onTap: onTap
                    )
                }
            }
        } else {
            TreemapCell(
                file: file,
                rect: rect,
                isNavigable: canNavigate(file),
                baseURL: baseURL,
                onTap: onTap
            )
        }
    }
    
    private func canNavigate(_ file: FileInfo) -> Bool {
        if file.name == TreemapContainerView.smallChildrenName { return true }
        if let subItems = file.subItems, !subItems.isEmpty {
            return true
        }
        return false
    }
    
    private func partition(subItems: [FileInfo], threshold: Int64) -> ([FileInfo], [FileInfo]) {
        let effectiveThreshold = max(threshold, 8192)
        
        var large: [FileInfo] = []
        var small: [FileInfo] = []
        
        for child in subItems {
            if child.size >= effectiveThreshold {
                large.append(child)
            } else {
                small.append(child)
            }
        }
        
        if !large.isEmpty {
            let maxCells = 50
            let sortedLarge = large.sorted(by: { $0.size > $1.size })
            let topLarge = Array(sortedLarge.prefix(maxCells))
            let remainingLarge = Array(sortedLarge.dropFirst(maxCells))
            
            // Combina i rimanenti con i piccoli
            let allSmall = small + remainingLarge
            return (topLarge, allSmall)
        }
        
        if !subItems.isEmpty {
            let sortedItems = subItems.sorted { $0.size > $1.size }
            let topItems = Array(sortedItems.prefix(min(10, sortedItems.count)))
            let remainingItems = Array(sortedItems.dropFirst(min(10, sortedItems.count)))
            return (topItems, remainingItems)
        }
        
        return ([], [])
    }
    
    private func buildChildren(largeChildren: [FileInfo], smallChildren: [FileInfo]) -> [FileInfo] {
        var children = largeChildren
        
        if !smallChildren.isEmpty {
            let totalSize = smallChildren.reduce(0) { $0 + $1.size }
            // Crea un FileInfo con subItems per renderlo navigabile
            let otherFiles = FileInfo(
                name: TreemapContainerView.smallChildrenName,
                type: .directory,
                size: totalSize,
                subItems: smallChildren
            )
            children.append(otherFiles)
        }
        
        return children
    }
}

private struct TreemapCell: View {
    let file: FileInfo
    let rect: CGRect
    let isNavigable: Bool
    let baseURL: URL?
    var onTap: ((FileInfo) -> Void)?
    @State private var isHovering: Bool = false
    @State private var hoverTask: Task<Void, Never>? = nil
    
    private func resolvedURL() -> URL? {
        // Do not resolve synthetic grouping nodes
        if file.name == TreemapContainerView.smallChildrenName { return nil }
        if let path = file.path, !path.isEmpty {
            if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
            if let baseURL = baseURL { return baseURL.appendingPathComponent(path) }
        } else if let baseURL = baseURL {
            return baseURL
        }
        return nil
    }
    
    private func revealInFinder() {
        guard let initialURL = resolvedURL() else { return }
        let fm = FileManager.default

        // If the exact file/folder exists, reveal it; otherwise, walk up to the nearest existing parent.
        var candidate = initialURL
        var lastPath = candidate.path
        while !fm.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            // Stop if we can't go higher
            if parent.path == lastPath { break }
            lastPath = parent.path
            candidate = parent
        }

        // Only proceed if the candidate exists on disk
        guard fm.fileExists(atPath: candidate.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([candidate])
    }
    
    private var color: Color {
        switch file.type {
            case .app, .binary: return .treemapAppBinary
            case .framework: return .treemapFramework
            case .bundle: return .treemapBundle
            case .assets: return .treemapAssets
            case .lproj: return .treemapLproj
            case .plist: return .treemapPlist
            default: return .treemapDefault
        }
    }
    
    var body: some View {
        if rect.width <= 0 || rect.height <= 0 {
            EmptyView()
        } else {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(color.opacity(file.name == TreemapContainerView.smallChildrenName ? 0.15 : 0.1))
                
                Rectangle()
                    .stroke(
                        color.opacity(file.name == TreemapContainerView.smallChildrenName ? 0.8 : 0.6),
                        lineWidth: file.name == TreemapContainerView.smallChildrenName ? 1.5 : 1)
                
                if rect.width > 60 && rect.height > 25 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(.system(size: 11, weight: file.name == "[Other Files]" ? .semibold : .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(5)
                }
                
                // Indicatore visuale per elementi navigabili
                if isNavigable && rect.width > 30 && rect.height > 30 {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: file.name == TreemapContainerView.smallChildrenName ? "folder.fill" : "chevron.right.circle.fill")
                                .foregroundColor(.white.opacity(0.6))
                                .font(.system(size: 12))
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Reveal in Finder", systemImage: "folder") {
                    revealInFinder()
                }
            }
            .modifier(HoverModifier(
                file: file,
                isEnabled: true,
                showOnlyImage: false
            ))
            .onTapGesture {
                if isNavigable {
                    onTap?(file)
                }
            }
            .position(x: rect.origin.x + rect.width/2, y: rect.origin.y + rect.height/2)
        }
    }
}

import SwiftUI

struct HoverModifier: ViewModifier {
    let file: FileInfo
    let isEnabled: Bool
    let showOnlyImage: Bool
    let delay: UInt64 = 300_000_000 // 0.3 secondi

    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>? = nil

    func body(content: Content) -> some View {
        content
            .onHover(perform: handleHover)
            .popover(isPresented: $isHovering) {
                if showOnlyImage {
                    HoverImageContent(file: file)
                } else {
                    HoverFullContent(file: file)
                }
            }
    }

    // MARK: - Private Hover Logic
    private func handleHover(_ hovering: Bool) {
        guard isEnabled else { return }

        hoverTask?.cancel()
        if hovering {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: delay)
                if !Task.isCancelled {
                    await MainActor.run {
                        isHovering = true
                    }
                }
            }
        } else {
            hoverTask = Task { @MainActor in
                isHovering = false
            }
        }
    }
}

// MARK: - Subviews
private struct HoverFullContent: View {
    let file: FileInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let imageData = file.internalImageData, let image = imageData.toNSImage() {
                HStack {
                    Spacer()
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                        .shadow(radius: 2)
                    Spacer()
                }
            }

            Text(file.name)
                .font(.headline)

            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                .font(.caption)
                .foregroundColor(.secondary)

            if let subItems = file.subItems, !subItems.isEmpty {
                Text("\(subItems.count) files")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 180)
    }
}

private struct HoverImageContent: View {
    let file: FileInfo

    var body: some View {
        if let imageData = file.internalImageData, let image = imageData.toNSImage() {
            VStack {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .shadow(radius: 2)
            }
            .padding(8)
        }
    }
}
