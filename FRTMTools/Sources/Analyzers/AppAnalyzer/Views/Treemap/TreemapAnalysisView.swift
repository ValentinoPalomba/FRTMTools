import SwiftUI

struct TreemapAnalysisView: View {
    let root: FileInfo
    @State private var navigationStack: [FileInfo] = []
    
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
                    maxDepth: 2
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
    var onTap: ((FileInfo) -> Void)?
    
    var body: some View {
        if let subItems = file.subItems, !subItems.isEmpty, level < maxDepth {
            let threshold = max(4096, file.size / 1000)
            let (largeChildren, smallChildrenSize) = partition(subItems: subItems, threshold: threshold)
            
            let children = buildChildren(largeChildren: largeChildren, smallChildrenSize: smallChildrenSize)
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
                        onTap: onTap
                    )
                }
            }
        } else {
            TreemapCell(
                file: file,
                rect: rect,
                isNavigable: canNavigate(file),
                onTap: onTap
            )
        }
    }
    
    private func canNavigate(_ file: FileInfo) -> Bool {
        if file.name == "[Other Files]" { return false }
        // Controlla se ha subItems con almeno un elemento
        if let subItems = file.subItems, !subItems.isEmpty {
            return true
        }
        return false
    }
    
    private func partition(subItems: [FileInfo], threshold: Int64) -> ([FileInfo], Int64) {
        var large: [FileInfo] = []
        var small: Int64 = 0

        // First pass without sorting to find large items
        for child in subItems {
            if child.size >= threshold {
                large.append(child)
            } else {
                small += child.size
            }
        }

        // If large items are found, we sort them and we are done.
        if !large.isEmpty {
            // Sort only the large items to maintain descending order for the treemap algorithm
            return (large.sorted(by: { $0.size > $1.size }), small)
        }

        // If no large items, we must find the top 10. Now we have to sort.
        if !subItems.isEmpty {
            let sortedItems = subItems.sorted { $0.size > $1.size }
            let topItems = Array(sortedItems.prefix(min(10, sortedItems.count)))
            // The original logic returns 0 for the small size.
            return (topItems, 0)
        }

        // If subItems is empty.
        return ([], 0)
    }
    
    private func buildChildren(largeChildren: [FileInfo], smallChildrenSize: Int64) -> [FileInfo] {
        var children = largeChildren
        if smallChildrenSize > 0 {
            children.append(FileInfo(name: "[Other Files]", type: .directory, size: smallChildrenSize))
        }
        return children
    }
}

private struct TreemapCell: View {
    let file: FileInfo
    let rect: CGRect
    let isNavigable: Bool
    var onTap: ((FileInfo) -> Void)?
    @State private var isHovering: Bool = false
    @State private var hoverTask: Task<Void, Never>? = nil
    
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
                    .fill(color.opacity(file.name == "[Other Files]" ? 0.1 : 0.1))
                
                Rectangle()
                    .stroke(color.opacity(0.6), lineWidth: 1)
                
                if rect.width > 60 && rect.height > 25 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(.system(size: 11, weight: .bold))
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
                            Image(systemName: "chevron.right.circle.fill")
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
            .onHover { hovering in
                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
                        if !Task.isCancelled {
                            isHovering = true
                        }
                    }
                } else {
                    hoverTask?.cancel()
                    isHovering = false
                }
            }
            .popover(
                isPresented: $isHovering,
                content: {
                    VStack {
                        Text(file.name)
                        Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                        .font(.caption)
                        
                        if let subItems = file.subItems, !subItems.isEmpty {
                            Text("\(subItems.count) files")
                                .font(.caption2)
                        }
                    }
                    .padding()
                })
            .onTapGesture {
                // Tutti gli elementi sono tappabili, ma solo quelli navigabili cambiano vista
                if isNavigable {
                    onTap?(file)
                }
            }
            .position(x: rect.origin.x + rect.width/2, y: rect.origin.y + rect.height/2)
        }
    }
}
