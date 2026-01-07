import SwiftUI
import Charts

struct DetailView<ViewModel: AppDetailViewModel>: View {
    var viewModel: ViewModel

    @State private var expandedSections: Set<String> = []
    @State private var selectedCategoryName: String? = nil
    @State private var searchText = ""
    @State private var showSDKList = false

    private let categoryColorScale: [String: Color] = [
        "Resources": .green,
        "Frameworks": .blue,
        "Main app binary": .red,
        "Assets": .purple,
        "Bundles": .orange,
        "Native Libraries": .teal,
        "Dex Files": .pink
    ]

    private var categoryColorDomain: [String] {
        // Only include categories that actually exist in the current analysis
        viewModel.categories.map { $0.name }
    }
    private var categoryColorRange: [Color] { categoryColorDomain.compactMap { categoryColorScale[$0] } }

    private var filteredCategories: [CategoryResult] {
        viewModel.filteredCategories(searchText: searchText)
    }

    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // Grid overview
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    SummaryCard(
                        title: "📦 Uncompressed Size",
                        value: ByteCountFormatter.string(fromByteCount: viewModel.analysis.totalSize, countStyle: .file),
                        subtitle: viewModel.analysis.fileName
                    )

                    SummaryCard(
                        title: "📐 Architectures",
                        value: "\(viewModel.archs.number)",
                        subtitle: viewModel.archTypesDescription
                    )

                    if let ipaViewModel = viewModel.sizeAnalyzer as? IPAViewModel,
                       let ipaAnalysis = viewModel.analysis as? IPAAnalysis {
                        InstalledSizeAnalysisView(
                            viewModel: ipaViewModel,
                            analysis: ipaAnalysis
                        )

                        StartupTimeAnalysisView(
                            viewModel: ipaViewModel,
                            analysis: ipaAnalysis
                        )
                    } else if let apkAnalysis = viewModel.analysis as? APKAnalysis {
                        AndroidSummarySection(
                            analysis: apkAnalysis,
                            apkViewModel: viewModel as? APKDetailViewModel,
                            byteFormatter: byteFormatter
                        )
                    }
                }
                .padding(.horizontal)

                if let apkAnalysis = viewModel.analysis as? APKAnalysis {
                    
                    if !apkAnalysis.playAssetPacks.isEmpty {
                        assetPackSummaryView(for: apkAnalysis)
                    }

                    manifestInsights(for: apkAnalysis)
                        .padding(.horizontal)

                    // Package breakdown disabled (attribution currently off)

                    if !apkAnalysis.dynamicFeatures.isEmpty {
                        dynamicFeatureDetails(for: apkAnalysis)
                    }

                    if !apkAnalysis.playAssetPacks.isEmpty {
                        playAssetPackDetails(for: apkAnalysis)
                    }
                }
                
                if viewModel.analysis.totalSize > 0 {
                    ExpandableGraphView(
                        analysis: viewModel.analysis
                    )
                    .id(viewModel.analysis.id)
                }

                // Dependency Graph Section (on demand)
                if let dependencyGraph = viewModel.analysis.dependencyGraph, !dependencyGraph.nodes.isEmpty {
                    DependencyGraphOnDemandSection(graph: dependencyGraph)
                        .padding(.horizontal)
                }
                
                HStack(alignment: .top, spacing: 24) {
                    // Pie chart
                    if viewModel.hasCategories {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Distribution by Category")
                                .font(.title3).bold()
                            
                            Chart(viewModel.categories) { category in
                                SectorMark(
                                    angle: .value("Size", category.totalSize),
                                    innerRadius: .ratio(0.55),
                                    outerRadius: selectedCategoryName == category.id ?
                                        .ratio(1) :
                                            .ratio(0.9),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(by: .value("Category", category.name))
                                .annotation(position: .overlay) {
                                    let totalSize = max(Double(viewModel.analysis.totalSize), 1)
                                    let percentage = (Double(category.totalSize) / totalSize) * 100
                                    Text("\(percentage, format: .number.precision(.fractionLength(0)))%")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .bold()
                                }
                            }
                            .chartForegroundStyleScale(
                                domain: categoryColorDomain,
                                range: categoryColorRange
                            )
                            .frame(height: 240)
                            .chartLegend(position: .bottom, spacing: 12)
                        }
                        .padding()
                        .dsSurface(.surface, cornerRadius: 16, border: true, shadow: true)
                    }
                    
                    // Bar chart for selected category
                    if let selectedCategoryName = selectedCategoryName {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top Files in \(selectedCategoryName)")
                                .font(.title3).bold()
                            
                            Chart(viewModel.topFiles(for: selectedCategoryName, limit: 5)) { item in
                                BarMark(
                                    x: .value("Size", item.size),
                                    y: .value("File", item.name)
                                )
                                .foregroundStyle(categoryColorScale[selectedCategoryName] ?? .accentColor)
                            }
                            .frame(height: 240)
                            .chartLegend(.hidden)
                        }
                        .padding()
                        .dsSurface(.surface, cornerRadius: 16, border: true, shadow: true)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal)
                
                if viewModel.buildsForApp.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Build Size by Version")
                            .font(.title3).bold()
                        
                        Chart(viewModel.buildsForApp, id: \.id) { build in
                            let sizeMB = Double(build.totalSize) / 1_048_576.0
                            BarMark(
                                x: .value("Version", build.version ?? "Unknown"),
                                y: .value("Size (MB)", sizeMB)
                            )
                            .foregroundStyle(.blue)
                        }
                        .chartXScale(domain: viewModel.buildsForApp.map { $0.version ?? "Unknown" })
                        .frame(height: 260)
                    }
                    .padding()
                    .dsSurface(.surface, cornerRadius: 16, border: true, shadow: true)
                    .padding(.horizontal)
                }
                
                // Collapsible sections
                VStack(spacing: 12) {
                    ForEach(filteredCategories) { category in
                        CollapsibleSection(
                            category: category,
                            action: {},
                            expandedSections: $expandedSections
                        )
                    }
                }
                .padding(.horizontal)
                
                TipsSection(
                    tips: viewModel.tips,
                    baseURL: viewModel.tipsBaseURL,
                    imagePreviewLookup: viewModel.tipImagePreviewMap
                )
                    .id(viewModel.analysis.id)
                    .padding(.top)
            }
            .padding(.vertical, 16)
        }
        .searchable(text: $searchText, prompt: "Search files...")
        .navigationTitle(viewModel.analysis.fileName)
        .onChange(of: expandedSections) {
            updateSelectedCategory()
        }
    }
    
    private func updateSelectedCategory() {
        withAnimation {
            if let expandedID = expandedSections.first {
                selectedCategoryName = viewModel.categoryName(for: expandedID)
            } else {
                selectedCategoryName = nil
            }
        }
    }

    @ViewBuilder
    private func manifestInsights(for analysis: APKAnalysis) -> some View {
        let thirdPartyLibraries = analysis.thirdPartyLibraries
        let deepLinks = analysis.deepLinks
        let activityComponents = analysis.components.filter {
            ($0.type == .activity || $0.type == .activityAlias) && !$0.intentFilters.isEmpty
        }
        let exportedComponents = analysis.components.filter { $0.exported == true }
        
        if thirdPartyLibraries.isEmpty && deepLinks.isEmpty && activityComponents.isEmpty && exportedComponents.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 16) {
                if !thirdPartyLibraries.isEmpty {
                    manifestInfoCard(
                        title: "📦 Third-party SDKs",
                        trailingButton: AnyView(
                            Button("View All") {
                                showSDKList.toggle()
                            }
                            .buttonStyle(.borderless)
                        )
                    ) {
                        let displayed = Array(thirdPartyLibraries.prefix(6))
                        ForEach(displayed) { lib in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lib.name)
                                    .font(.body)
                                    .bold()
                                HStack(spacing: 12) {
                                    Text("Version: \(lib.version ?? "Unknown")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(formatSize(lib.estimatedSize))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if lib.id != displayed.last?.id {
                                Divider()
                            }
                        }
                        if thirdPartyLibraries.count > displayed.count {
                            Text("+\(thirdPartyLibraries.count - displayed.count) more SDKs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if !deepLinks.isEmpty {
                    manifestInfoCard(title: "🔗 Deep Links") {
                        let displayed = Array(deepLinks.prefix(6))
                        ForEach(displayed) { link in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deepLinkDisplay(link))
                                    .font(.body)
                                Text(link.componentName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if link.id != displayed.last?.id {
                                Divider()
                            }
                        }
                        if deepLinks.count > displayed.count {
                            Text("+\(deepLinks.count - displayed.count) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if !activityComponents.isEmpty {
                    manifestInfoCard(title: "🧭 Activity Intent Filters") {
                        let displayedComponents = Array(activityComponents.prefix(3))
                        ForEach(displayedComponents.indices, id: \.self) { index in
                            let component = displayedComponents[index]
                            VStack(alignment: .leading, spacing: 6) {
                                Text(component.name)
                                    .font(.subheadline)
                                    .bold()
                                let filters = component.intentFilters.prefix(2)
                                ForEach(filters.indices, id: \.self) { filterIndex in
                                    let filter = filters[filterIndex]
                                    VStack(alignment: .leading, spacing: 2) {
                                        if !filter.actions.isEmpty {
                                            Text("Actions: \(filter.actions.joined(separator: ", "))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if !filter.categories.isEmpty {
                                            Text("Categories: \(filter.categories.joined(separator: ", "))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let dataSummary = intentDataSummary(filter.data) {
                                            Text("Data: \(dataSummary)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            if index < displayedComponents.count - 1 {
                                Divider()
                            }
                        }
                        if activityComponents.count > displayedComponents.count {
                            Text("+\(activityComponents.count - displayedComponents.count) more activities")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if !exportedComponents.isEmpty {
                    manifestInfoCard(title: "⚠️ Exported Components") {
                        let displayed = Array(exportedComponents.prefix(6))
                        ForEach(displayed.indices, id: \.self) { index in
                            let component = displayed[index]
                            HStack(spacing: 8) {
                                Image(systemName: componentIcon(for: component.type))
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(component.name)
                                        .font(.body)
                                    if let label = component.label {
                                        Text(label)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if index < displayed.count - 1 {
                                Divider()
                            }
                        }
                        if exportedComponents.count > displayed.count {
                            Text("+\(exportedComponents.count - displayed.count) more exported components")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSDKList) {
                ThirdPartyLibrariesListView(libraries: analysis.thirdPartyLibraries)
                    .frame(width: 520, height: 600)
            }
        }
    }

    @ViewBuilder
    private func assetPackSummaryView(for analysis: APKAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Play Asset Delivery")
                .font(.title3)
                .bold()
            Text("\(analysis.playAssetPacks.count) asset pack\(analysis.playAssetPacks.count == 1 ? "" : "s") included")
                .foregroundStyle(.secondary)
            Text(assetPackPreviewDescription(for: analysis.playAssetPacks))
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(.surface, cornerRadius: 16, border: true, shadow: true)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func playAssetPackDetails(for analysis: APKAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Asset Packs")
                .font(.headline)
            ForEach(analysis.playAssetPacks) { pack in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(pack.name)
                            .font(.body)
                            .bold()
                        Spacer()
                        Text(byteFormatter.string(fromByteCount: pack.compressedSizeBytes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(pack.deliveryType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if pack.id != analysis.playAssetPacks.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .dsSurface(.surface, cornerRadius: 16, border: true, shadow: true)
        .padding(.horizontal)
    }

    private func assetPackPreviewDescription(for packs: [PlayAssetPackInfo]) -> String {
        let names = packs.map(\.name)
        return listPreviewDescription(for: names, limit: 4)
    }

    @ViewBuilder
    private func dynamicFeatureDetails(for analysis: APKAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dynamic Feature Modules")
                .font(.headline)
            ForEach(analysis.dynamicFeatures) { feature in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(feature.name)
                            .font(.body)
                            .bold()
                        Spacer()
                        Text(byteFormatter.string(fromByteCount: feature.estimatedSizeBytes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(feature.deliveryType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if feature.id != analysis.dynamicFeatures.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .dsSurface(.surface, cornerRadius: 16, border: true, shadow: true)
        .padding(.horizontal)
    }

    private func dynamicFeaturePreviewDescription(for features: [DynamicFeatureInfo]) -> String {
        let names = features.map(\.name)
        return listPreviewDescription(for: names, limit: 4)
    }

    @ViewBuilder
    private func manifestInfoCard<Content: View>(title: String, trailingButton: AnyView? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if let trailingButton {
                    trailingButton
                }
            }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(.surface, cornerRadius: 16, border: true, shadow: true)
    }

    private func deepLinkDisplay(_ link: AndroidDeepLinkInfo) -> String {
        var parts: [String] = []
        if let scheme = link.scheme {
            parts.append("\(scheme)://")
        }
        if let host = link.host {
            parts.append(host)
        }
        if let path = link.path {
            if !path.hasPrefix("/") && !path.hasPrefix("prefix:") && !path.hasPrefix("pattern:") {
                parts.append("/\(path)")
            } else {
                parts.append(path)
            }
        }
        var result = parts.joined()
        if result.isEmpty {
            result = link.componentName
        }
        if let mime = link.mimeType {
            result += " (\(mime))"
        }
        return result
    }
    
    private func intentDataSummary(_ entries: [AndroidIntentData]) -> String? {
        guard !entries.isEmpty else { return nil }
        let summaries = entries.compactMap { entry -> String? in
            var components: [String] = []
            if let scheme = entry.scheme {
                components.append("\(scheme)://")
            }
            if let host = entry.host {
                components.append(host)
            }
            if let path = entry.path {
                components.append(path)
            } else if let prefix = entry.pathPrefix {
                components.append("prefix:\(prefix)")
            } else if let pattern = entry.pathPattern {
                components.append("pattern:\(pattern)")
            }
            if components.isEmpty, let mime = entry.mimeType {
                components.append(mime)
            }
            return components.isEmpty ? nil : components.joined()
        }
        guard !summaries.isEmpty else { return nil }
        return summaries.joined(separator: ", ")
    }
    
    private func componentIcon(for type: AndroidComponentType) -> String {
        switch type {
        case .activity, .activityAlias:
            return "rectangle.and.arrow.up.right.and.arrow.down.left.slash"
        case .service:
            return "gearshape.fill"
        case .receiver:
            return "antenna.radiowaves.left.and.right"
        case .provider:
            return "externaldrive.fill.badge.checkmark"
        }
    }
    
    private func formatSize(_ size: Int64) -> String {
        guard size > 0 else { return "Size: —" }
        return "Size: " + ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

}
