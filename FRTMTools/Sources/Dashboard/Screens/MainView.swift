import SwiftUI

struct MainView: View {
    @State private var model = MainViewModel()
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedTool) {
                ForEach(MainViewModel.Tool.allCases) { tool in
                    HStack(spacing: 10) {
                        SidebarIconView(
                            imageName: tool.systemImage,
                            color: toolTint(for: tool.tintRole),
                            isSelected: model.selectedTool == tool,
                            isHovering: model.hoveredTool == tool
                        )
                        Text(tool.rawValue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(.rect)
                    .onHover { hovering in
                        model.hoveredTool = hovering ? tool : nil
                    }
                    .tag(tool)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(tool.rawValue)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Tools")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } content: {
            Group {
                switch model.selectedTool {
                case .ipaAnalyzer:
                    IPAAnalyzerContentView(viewModel: model.ipaViewModel)
                case .apkAnalyzer:
                    APKAnalyzerContentView(viewModel: model.apkViewModel)
                case .unusedAssets:
                    UnusedAssetsContentView(viewModel: model.unusedAssetsViewModel)
                case .securityScanner:
                    SecurityScannerContentView(viewModel: model.securityScannerViewModel)
                case .deadCodeScanner:
                    DeadCodeContentView(viewModel: model.deadCodeViewModel)
                case .ipatool:
                    IPAToolContentView(viewModel: model.ipaToolViewModel)
                case .badWordScanner:
                    BadWordScannerContentView(viewModel: model.badWordScannerViewModel)
                case .none:
                    ContentUnavailableView(
                        "Choose a Tool",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("Select a tool from the sidebar to get started.")
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 520)
        } detail: {
            switch model.selectedTool {
            case .ipaAnalyzer:
                IPAAnalyzerDetailView(viewModel: model.ipaViewModel)
            case .apkAnalyzer:
                APKAnalyzerDetailView(viewModel: model.apkViewModel)
            case .unusedAssets:
                UnusedAssetsResultView(viewModel: model.unusedAssetsViewModel)
            case .securityScanner:
                SecurityScannerResultView(viewModel: model.securityScannerViewModel)
            case .deadCodeScanner:
                DeadCodeResultView(viewModel: model.deadCodeViewModel)
            case .ipatool:
                IPAToolSelectionDetailView(viewModel: model.ipaToolViewModel)
            case .badWordScanner:
                BadWordScannerDetailView(viewModel: model.badWordScannerViewModel)
            case .none:
                ContentUnavailableView(
                    "No Tool Selected",
                    systemImage: "sidebar.left",
                    description: Text("Choose a tool to inspect its results.")
                )
            }
        }
        .background(theme.palette.background)
        .frame(minWidth: 980, minHeight: 640)
        .loaderOverlay(
            isPresented: Binding(
                get: { model.activeLoader != nil },
                set: { _ in }
            ),
            content: {
                if let loader = model.activeLoader {
                    LoaderView(
                        style: .indeterminate,
                        title: loader.title,
                        subtitle: loader.subtitle,
                        showsCancel: false,
                        cancelAction: nil
                    )
                }
            }
        )
        .onChange(of: model.selectedTool) { oldValue, newValue in
            model.handleSelectedToolChange(oldValue: oldValue, newValue: newValue)
        }
        .task {
            model.onAppear()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearIPAToolMetadataCache)) { _ in
            model.clearIPAToolMetadataCache()
        }
        .onDisappear {
            model.hoveredTool = nil
        }
    }

    private func toolTint(for role: MainViewModel.TintRole) -> Color {
        switch role {
        case .accent:
            theme.palette.accent
        case .accentMuted:
            theme.palette.accent.opacity(theme.colorScheme == .dark ? 0.7 : 0.6)
        case .success:
            theme.palette.success
        case .warning:
            theme.palette.warning
        case .danger:
            theme.palette.danger
        }
    }
}
