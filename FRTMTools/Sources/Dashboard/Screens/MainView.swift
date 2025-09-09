import SwiftUI


struct MainView: View {
    @State private var selectedTool: Tool? = .ipaAnalyzer
    
    enum Tool: String, Hashable, Identifiable {
        case ipaAnalyzer = "IPA Analyzer"
        case unusedAssets = "Unused Assets Analyzer"

        var id: String { rawValue }
    }


    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTool) {
                Label("IPA Analyzer", systemImage: "app.box")
                    .tag(Tool.ipaAnalyzer)
                Label("Unused Assets Analyzer", systemImage: "trash")
                    .tag(Tool.unusedAssets)
            }
            .listStyle(.sidebar)
            .navigationTitle("FRTM Tools")

        } detail: {
            switch selectedTool {
            case .ipaAnalyzer:
                NavigationStack {
                    IPAAnalyzerView()
                }
            case .unusedAssets:
                NavigationStack {
                    UnusedAssetsDetailView()
                }
            case .none:
                Text("Select a tool from the sidebar.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
