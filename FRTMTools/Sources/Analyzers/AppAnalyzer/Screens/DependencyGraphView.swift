import SwiftUI
import Grape

struct DependencyGraphView: View {
    let graph: DependencyGraph

    @State var selectedNode: String?
    @State var hoveredNode: String?
    @State var searchText = ""
    @State var showExternalLibraries = true
    @State var enabledNodeTypes: Set<DependencyNodeType> = Set(DependencyNodeType.allCases)
    @State var graphStates = ForceDirectedGraphState()
    @State var showFilters = false
    @State var showLegend = true
    @State var showControls = false
    @State var isExporting = false

    // Computed properties
    private var filteredNodes: Set<DependencyNode> {
        graph.nodes.filter { node in
            // Filter by enabled types
            guard enabledNodeTypes.contains(node.type) else { return false }

            // Filter external libraries
            if !showExternalLibraries && node.type == .dynamicLibrary {
                return false
            }

            // Filter by search text
            if !searchText.isEmpty {
                return node.name.localizedCaseInsensitiveContains(searchText)
            }

            return true
        }
    }

    private var filteredEdges: Set<DependencyEdge> {
        let nodeIds = Set(filteredNodes.map { $0.id })
        return graph.edges.filter { edge in
            nodeIds.contains(edge.fromId) && nodeIds.contains(edge.toId)
        }
    }

    private var selectedNodeData: DependencyNode? {
        guard let selectedNode = selectedNode else { return nil }
        return graph.nodes.first { $0.id == selectedNode }
    }

    private var selectedNodeIncomingEdges: [DependencyEdge] {
        guard let selectedNode = selectedNode else { return [] }
        return graph.edges.filter { $0.toId == selectedNode }
    }

    private var selectedNodeOutgoingEdges: [DependencyEdge] {
        guard let selectedNode = selectedNode else { return [] }
        return graph.edges.filter { $0.fromId == selectedNode }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Top toolbar - only show when controls are visible
                if showControls {
                    HStack {
                        // Search
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search nodes...", text: $searchText)
                                .textFieldStyle(.plain)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                        .frame(maxWidth: 300)
                        
                        Spacer()
                        
                        // Stats
                        HStack(spacing: 16) {
                            StatBadge(
                                icon: "circle.fill",
                                color: .blue,
                                label: "Frameworks",
                                value: "\(filteredNodes.filter { $0.type == .framework }.count)"
                            )
                            StatBadge(
                                icon: "circle.fill",
                                color: .green,
                                label: "Extensions",
                                value: "\(filteredNodes.filter { $0.type == .appExtension }.count)"
                            )
                            StatBadge(
                                icon: "circle.fill",
                                color: .cyan,
                                label: "Libraries",
                                value: "\(filteredNodes.filter { $0.type == .dynamicLibrary }.count)"
                            )
                        }
                        
                        Spacer()
                        
                        // Controls
                        HStack(spacing: 12) {
                            Button(action: { showFilters.toggle() }) {
                                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { showLegend.toggle() }) {
                                Label("Legend", systemImage: "info.circle")
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: exportAsImage) {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: resetGraph) {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showControls = false
                                }
                            }) {
                                Label("Hide Controls", systemImage: "xmark.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                }
                HStack(spacing: 0) {
                    // Graph view
                    ZStack {
                        // Show controls button overlay (only when controls are hidden)
                        if !showControls {
                            VStack {
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            showControls = true
                                        }
                                    }) {
                                        Image(systemName: "slider.horizontal.3")
                                            .font(.system(size: 16))
                                            .padding(8)
                                            .background(
                                                Circle()
                                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.9))
                                                    .shadow(radius: 4)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help("Show controls")
                                    .padding()
                                }
                                Spacer()
                            }
                            .zIndex(100)
                        }
                        
                        ForceDirectedGraph(states: graphStates) {
                            // Nodes
                            Series(Array(filteredNodes)) { node in
                                NodeMark(id: node.id)
                                    .symbol(.circle)
                                    .symbolSize(radius: nodeSizeForNode(node))
                                    .foregroundStyle(colorForNodeType(node.type))
                                    .stroke(
                                        selectedNode == node.id ? .white : .gray
                                            .opacity(0.5)
                                    )
                                    .annotation {
                                        Text(node.name)
                                            .font(.caption)
                                    }
                                
                                
                            }
                            
                            // Edges
                            Series(Array(filteredEdges)) { edge in
                                LinkMark(from: edge.fromId, to: edge.toId)
                                    .stroke(
                                        edgeColorForType(edge.type), StrokeStyle(
                                            lineWidth: edge.type == .embeds ? 2 : 1,
                                            dash: edge.type == .links ? [5, 3] : []
                                        )
                                    )
                            }
                        } force: {
                            .manyBody(strength: -300)
                            .link(
                                originalLength: .constant(120.0),
                                stiffness: .weightedByDegree({ _, _ in 1.5 })
                            )
                            .center()
                            .collide(radius: .constant(40))
                        }
                        .graphOverlay { proxy in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .withGraphDragGesture(
                                    proxy,
                                    of: String.self,
                                    action: describe
                                )
                                .withGraphTapGesture(
                                    proxy,
                                    of: String.self,
                                    action: { nodeId in
                                        selectedNode = nodeId
                                    }
                                )
                                .withGraphMagnifyGesture(proxy)
                                .onContinuousHover { phase in
                                    switch phase {
                                        case .active(let location):
                                            if let nodeId = proxy.node(at: location) as? String {
                                                hoveredNode = nodeId
                                            } else {
                                                hoveredNode = nil
                                            }
                                        case .ended:
                                            hoveredNode = nil
                                    }
                                }
                        }
                        .id(filteredNodes.count)
                        
                        // Legend overlay
                        if showLegend {
                            VStack {
                                Spacer()
                                HStack {
                                    LegendView()
                                    Spacer()
                                }
                            }
                            .padding()
                        }
                    }
                    
                    // Filters panel - only show when controls are visible
                    if showControls && showFilters {
                        FiltersPanelView(
                            enabledNodeTypes: $enabledNodeTypes,
                            showExternalLibraries: $showExternalLibraries
                        )
                        .frame(width: 250)
                        .background(Color(NSColor.controlBackgroundColor))
                        .transition(.move(edge: .trailing))
                    }
                    
                    // Info panel - only show when controls are visible
                    if showControls, let nodeData = selectedNodeData {
                        NodeInfoPanel(
                            node: nodeData,
                            incomingEdges: selectedNodeIncomingEdges,
                            outgoingEdges: selectedNodeOutgoingEdges,
                            allNodes: graph.nodes,
                            onClose: { selectedNode = nil }
                        )
                        .frame(width: 300)
                        .background(Color(NSColor.controlBackgroundColor))
                        .transition(.move(edge: .trailing))
                    }
                }
            }
        }
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(.circular)

                        Text("Preparing export...")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Waiting for graph to stabilize")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .shadow(radius: 20)
                    )
                }
            }
        }
    }


    func describe(_ state: GraphDragState<String>?) {
        switch state {
        case .node(let id):
            if selectedNode != id {
                selectedNode = id
            }
        case .background:
            selectedNode = nil
        case nil:
            break
        }
    }

    private func resetGraph() {
        graphStates = ForceDirectedGraphState()
        selectedNode = nil
        searchText = ""
        enabledNodeTypes = Set(DependencyNodeType.allCases)
        showExternalLibraries = true
    }

    @MainActor
    private func exportAsImage() {
        // Show loading indicator
        isExporting = true

        let exportView = GraphExportView(
            filteredNodes: filteredNodes,
            filteredEdges: filteredEdges,
            graphStates: graphStates,
            nodeSizeForNode: nodeSizeForNode,
            colorForNodeType: colorForNodeType,
            edgeColorForType: edgeColorForType
        )
        
        

        // Wait for graph to stabilize (increased to 4 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            // Render to image
            let renderer = ImageRenderer(content: exportView)
            renderer.scale = 2.0 // Retina quality

            if let nsImage = renderer.nsImage {
                // Hide loading indicator
                isExporting = false

                // Show save panel
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.png]
                savePanel.nameFieldStringValue = "dependency-graph.png"
                savePanel.begin { response in
                    if response == .OK, let url = savePanel.url {
                        if let tiffData = nsImage.tiffRepresentation,
                           let bitmapImage = NSBitmapImageRep(data: tiffData),
                           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                            try? pngData.write(to: url)
                        }
                    }
                }
            } else {
                // Hide loading indicator if render failed
                isExporting = false
            }
        }
    }

    private func nodeSizeForNode(_ node: DependencyNode) -> CGFloat {
        let baseSize: CGFloat = 10
        if node.type == .mainApp {
            return baseSize * 2.5
        }
        if let size = node.size, size > 0 {
            let sizeMultiplier = log(Double(size) + 1) / 25.0
            return baseSize + CGFloat(sizeMultiplier) * 10
        }
        return baseSize
    }

    private func colorForNodeType(_ type: DependencyNodeType) -> Color {
        switch type {
        case .mainApp: return .purple
        case .framework: return .blue
        case .dynamicLibrary: return .cyan
        case .bundle: return .orange
        case .plugin: return .pink
        case .appExtension: return .green
        }
    }

    private func edgeColorForType(_ type: DependencyEdgeType) -> Color {
        switch type {
        case .links: return .gray.opacity(0.4)
        case .embeds: return .purple.opacity(0.6)
        case .loads: return .green.opacity(0.6)
        }
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .bold()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
    }
}

struct FiltersPanelView: View {
    @Binding var enabledNodeTypes: Set<DependencyNodeType>
    @Binding var showExternalLibraries: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filters")
                .font(.headline)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 12) {
                Text("Node Types")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(DependencyNodeType.allCases.filter { $0 != .mainApp }, id: \.self) { type in
                    Toggle(isOn: Binding(
                        get: { enabledNodeTypes.contains(type) },
                        set: { isEnabled in
                            if isEnabled {
                                enabledNodeTypes.insert(type)
                            } else {
                                enabledNodeTypes.remove(type)
                            }
                        }
                    )) {
                        HStack {
                            Circle()
                                .fill(colorForNodeType(type))
                                .frame(width: 12, height: 12)
                            Text(type.rawValue)
                                .font(.callout)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Options")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Toggle("Show External Libraries", isOn: $showExternalLibraries)
                    .toggleStyle(.checkbox)
                    .font(.callout)
            }

            Spacer()
        }
        .padding()
    }

    private func colorForNodeType(_ type: DependencyNodeType) -> Color {
        switch type {
        case .mainApp: return .purple
        case .framework: return .blue
        case .dynamicLibrary: return .cyan
        case .bundle: return .orange
        case .plugin: return .pink
        case .appExtension: return .green
        }
    }
}

struct LegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Legend")
                .font(.caption)
                .bold()

            VStack(alignment: .leading, spacing: 4) {
                LegendGraphItem(color: .purple, label: "Main App", icon: "circle.fill")
                LegendGraphItem(color: .blue, label: "Framework", icon: "circle.fill")
                LegendGraphItem(color: .green, label: "Extension", icon: "circle.fill")
                LegendGraphItem(color: .cyan, label: "Library", icon: "circle.fill")
            }

            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                LegendGraphItem(color: .purple.opacity(0.6), label: "Embeds", icon: "line.diagonal", isEdge: true)
                LegendGraphItem(color: .gray.opacity(0.4), label: "Links", icon: "line.diagonal.dash", isEdge: true)
            }
        }
        .font(.caption2)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.95))
                .shadow(radius: 4)
        )
    }
}

struct LegendGraphItem: View {
    let color: Color
    let label: String
    let icon: String
    var isEdge: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if isEdge {
                Rectangle()
                    .fill(color)
                    .frame(width: 16, height: 2)
            } else {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 8))
            }
            Text(label)
                .foregroundColor(.primary)
        }
    }
}

struct NodeInfoPanel: View {
    let node: DependencyNode
    let incomingEdges: [DependencyEdge]
    let outgoingEdges: [DependencyEdge]
    let allNodes: Set<DependencyNode>
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Node Details")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Node info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(colorForNodeType(node.type))
                                .frame(width: 16, height: 16)
                            Text(node.type.rawValue)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Text(node.name)
                            .font(.title3)
                            .bold()

                        if let size = node.size {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .font(.callout)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Path")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(node.path)
                                .font(.caption)
                                .textSelection(.enabled)
                                .foregroundColor(.primary)
                                .lineLimit(nil)
                        }
                    }

                    Divider()

                    // Dependencies
                    if !outgoingEdges.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dependencies (\(outgoingEdges.count))")
                                .font(.subheadline)
                                .bold()

                            ForEach(outgoingEdges) { edge in
                                if let targetNode = allNodes.first(where: { $0.id == edge.toId }) {
                                    DependencyRow(node: targetNode, edgeType: edge.type)
                                }
                            }
                        }
                    }

                    if !incomingEdges.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Used By (\(incomingEdges.count))")
                                .font(.subheadline)
                                .bold()

                            ForEach(incomingEdges) { edge in
                                if let sourceNode = allNodes.first(where: { $0.id == edge.fromId }) {
                                    DependencyRow(node: sourceNode, edgeType: edge.type)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func colorForNodeType(_ type: DependencyNodeType) -> Color {
        switch type {
        case .mainApp: return .purple
        case .framework: return .blue
        case .dynamicLibrary: return .cyan
        case .bundle: return .orange
        case .plugin: return .pink
        case .appExtension: return .green
        }
    }
}

struct DependencyRow: View {
    let node: DependencyNode
    let edgeType: DependencyEdgeType

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(colorForNodeType(node.type))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.callout)
                Text(edgeType.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
    }

    private func colorForNodeType(_ type: DependencyNodeType) -> Color {
        switch type {
        case .mainApp: return .purple
        case .framework: return .blue
        case .dynamicLibrary: return .cyan
        case .bundle: return .orange
        case .plugin: return .pink
        case .appExtension: return .green
        }
    }
}

extension DependencyNodeType: CaseIterable {
    public static var allCases: [DependencyNodeType] {
        [.mainApp, .framework, .dynamicLibrary, .bundle, .plugin, .appExtension]
    }
}

// MARK: - Export View

struct GraphExportView: View {
    let filteredNodes: Set<DependencyNode>
    let filteredEdges: Set<DependencyEdge>
    let graphStates: ForceDirectedGraphState
    let nodeSizeForNode: (DependencyNode) -> CGFloat
    let colorForNodeType: (DependencyNodeType) -> Color
    let edgeColorForType: (DependencyEdgeType) -> Color

    var body: some View {
        VStack(spacing: 0) {
            graphContent
            legendContent
        }
        .frame(width: 1920, height: 1080)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var graphContent: some View {
        ForceDirectedGraph(states: graphStates) {
            Series(Array(filteredNodes)) { node in
                NodeMark(id: node.id)
                    .symbol(.circle)
                    .symbolSize(radius: nodeSizeForNode(node))
                    .foregroundStyle(colorForNodeType(node.type))
                    .annotation({
                        Text(node.name)
                            .font(.caption)
                            
                    })
            }
            
            Series(Array(filteredEdges)) { edge in
                let lineWidth: CGFloat = edge.type == .embeds ? 2 : 1
                let dashPattern: [CGFloat] = edge.type == .links ? [5, 3] : []

                LinkMark(from: edge.fromId, to: edge.toId)
                    .stroke(
                        edgeColorForType(edge.type),
                        StrokeStyle(lineWidth: lineWidth, dash: dashPattern)
                    )
            }
        } force: {
            .manyBody(strength: -80)
            .link(
                originalLength: .constant(120.0),
                stiffness: .weightedByDegree({ _, _ in 1.5 })
            )
            .center()
            .collide(radius: .constant(40))
        }
    }

    private var legendContent: some View {
        HStack {
            LegendView()
            Spacer()
        }
        .padding()
    }
}
