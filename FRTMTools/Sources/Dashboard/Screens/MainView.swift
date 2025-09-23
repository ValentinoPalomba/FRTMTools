import SwiftUI


struct MainView: View {
    @State private var selectedTool: Tool? = .ipaAnalyzer
    
    @StateObject private var ipaViewModel = IPAViewModel()
    @StateObject private var unusedAssetsViewModel = UnusedAssetsViewModel()
    @StateObject private var securityScannerViewModel = SecurityScannerViewModel()
    @StateObject private var deadCodeViewModel = DeadCodeViewModel()
    
    enum Tool: String, Hashable, Identifiable {
        case ipaAnalyzer = "IPA Analyzer"
        case unusedAssets = "Unused Assets Analyzer"
        case securityScanner = "Security Scanner"
        case deadCodeSanner = "Dead Code Sanner"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTool) {
                Label("IPA Analyzer", systemImage: "app.badge")
                    .tag(Tool.ipaAnalyzer)
                Label("Unused Assets Analyzer", systemImage: "trash")
                    .tag(Tool.unusedAssets)
                Label("Security Scanner", systemImage: "shield.lefthalf.filled")
                    .tag(Tool.securityScanner)
                Label("Dead Code Scanner", systemImage: "text.magnifyingglass")
                    .tag(Tool.deadCodeSanner)
            }
            .listStyle(.sidebar)
            .navigationTitle("FRTM Tools")
        } content: {
            switch selectedTool {
            case .ipaAnalyzer:
                IPAAnalyzerContentView(viewModel: ipaViewModel)
            case .unusedAssets:
                UnusedAssetsContentView(viewModel: unusedAssetsViewModel)
            case .securityScanner:
                SecurityScannerContentView(viewModel: securityScannerViewModel)
            case .deadCodeSanner:
                DeadCodeContentView(viewModel: deadCodeViewModel)
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
            case .deadCodeSanner:
                    DeadCodeResultView(viewModel: deadCodeViewModel)
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
