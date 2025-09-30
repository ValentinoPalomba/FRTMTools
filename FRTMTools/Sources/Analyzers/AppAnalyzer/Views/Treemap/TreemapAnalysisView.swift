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
                    maxDepth: 1
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
            .modifier(HoverModifier(
                file: file,
                isEnabled: true
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

struct HoverModifier: ViewModifier {
    let file: FileInfo
    let isEnabled: Bool
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>? = nil
    
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onHover { hovering in
                    if hovering {
                        hoverTask = Task {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            if !Task.isCancelled {
                                isHovering = true
                            }
                        }
                    } else {
                        hoverTask?.cancel()
                        isHovering = false
                    }
                }
                .popover(isPresented: $isHovering) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.name)
                            .font(.headline)
                        Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                            .font(.caption)
                        
                        if let subItems = file.subItems, !subItems.isEmpty {
                            Text("\(subItems.count) files")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
        } else {
            content
        }
    }
}
