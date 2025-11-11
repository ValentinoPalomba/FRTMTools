import SwiftUI


struct MainView: View {
    @State private var selectedTool: Tool? = .ipaAnalyzer
    
    @StateObject private var ipaViewModel = IPAViewModel()
    @StateObject private var unusedAssetsViewModel = UnusedAssetsViewModel()
    @StateObject private var securityScannerViewModel = SecurityScannerViewModel()
    @StateObject private var deadCodeViewModel = DeadCodeViewModel()
    
    enum Tool: String, Hashable, Identifiable, CaseIterable {
        case ipaAnalyzer = "IPA Analyzer"
        case unusedAssets = "Unused Assets Analyzer"
        case securityScanner = "Security Scanner"
        //case deadCodeScanner = "Dead Code Scanner"
        
        var id: String { rawValue }
        
        var systemImage: String {
            switch self {
            case .ipaAnalyzer: return "app.badge"
            case .unusedAssets: return "trash"
            case .securityScanner: return "shield.lefthalf.filled"
            //case .deadCodeScanner: return "text.magnifyingglass"
            }
        }
        
        var color: Color {
            switch self {
            case .ipaAnalyzer: return .blue
            case .unusedAssets: return .purple
            case .securityScanner: return .red
           // case .deadCodeScanner: return .orange
            }
        }
    }

    @State private var hoveredTool: Tool? = nil

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTool) {
                ForEach(Tool.allCases) { tool in
                    HStack(alignment: .lastTextBaseline) {
                        SidebarIconView(
                            imageName: tool.systemImage,
                            color: tool.color,
                            isSelected: selectedTool == tool,
                            isHovering: hoveredTool == tool
                        )
                        Text(tool.rawValue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onHover { hovering in
                        hoveredTool = hovering ? tool : nil
                    }
                    .tag(tool)
                }
            }
            .listStyle(.sidebar)
        } content: {
            switch selectedTool {
            case .ipaAnalyzer:
                IPAAnalyzerContentView(viewModel: ipaViewModel)
            case .unusedAssets:
                UnusedAssetsContentView(viewModel: unusedAssetsViewModel)
            case .securityScanner:
                SecurityScannerContentView(viewModel: securityScannerViewModel)
//            case .deadCodeScanner:
//                DeadCodeContentView(viewModel: deadCodeViewModel)
            case .none:
                Text("Select an item to see details.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } detail: {
            switch selectedTool {
            case .ipaAnalyzer:
                IPAAnalyzerDetailView(viewModel: ipaViewModel)
            case .unusedAssets:
                UnusedAssetsResultView(viewModel: unusedAssetsViewModel)
            case .securityScanner:
                    SecurityScannerResultView(viewModel: securityScannerViewModel)
//            case .deadCodeScanner:
//                    DeadCodeResultView(viewModel: deadCodeViewModel)
            case .none:
                Text("Select an item to see details.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .loaderOverlay(
            isPresented: $ipaViewModel.isLoading,
            content: {
                LoaderView(
                    style: .indeterminate,
                    title: "Analyzing IPA",
                    subtitle: "This can take a few minutes…",
                    showsCancel: false,
                    cancelAction: nil
                )
        })
        .loaderOverlay(
            isPresented: $unusedAssetsViewModel.isLoading,
            content: {
                LoaderView(
                    style: .indeterminate,
                    title: "Analyzing project...",
                    subtitle: "Finding unused assets...",
                    showsCancel: false,
                    cancelAction: nil
                )
        })
        .loaderOverlay(
            isPresented: $deadCodeViewModel.isLoading,
            content: {
                LoaderView(
                    style: .indeterminate,
                    title: "Analyzing project...",
                    subtitle: "Finding dead code...",
                    showsCancel: false,
                    cancelAction: nil
                )
        })
        .loaderOverlay(
            isPresented: $securityScannerViewModel.isLoading,
            content: {
                LoaderView(
                    style: .indeterminate,
                    title: "Scanning project...",
                    subtitle: "Searching for secrets...",
                    showsCancel: false,
                    cancelAction: nil
                )
        })
    }
}
