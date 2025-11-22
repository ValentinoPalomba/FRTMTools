import SwiftUI
import Charts

struct DetailView<ViewModel: AppDetailViewModel>: View {
    var viewModel: ViewModel

    @State private var expandedSections: Set<String> = []
    @State private var selectedCategoryName: String? = nil
    @State private var searchText = ""
    @State private var showPermissionsDetails = false
    @State private var showImageExtractionOptions = false
    @State private var extractionInProgress = false
    @State private var showExtractionAlert = false
    @State private var extractionAlertMessage = ""
    @State private var showCertificateInfo = false
    @State private var showFeatureDetails = false
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

    private var categoryColorDomain: [String] { Array(categoryColorScale.keys) }
    private var categoryColorRange: [Color] { categoryColorDomain.compactMap { categoryColorScale[$0] } }

    private var filteredCategories: [CategoryResult] {
        viewModel.filteredCategories(searchText: searchText)
    }
    
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

                    if let sizeAnalyzer = viewModel.sizeAnalyzer {
                        InstalledSizeAnalysisView(
                            viewModel: sizeAnalyzer,
                            analysis: viewModel.analysis
                        )
                    }

                    SummaryCard(
                        title: "📂 Categories",
                        value: "\(viewModel.categoriesCount)",
                        subtitle: "Main groups"
                    )

                    SummaryCard(
                        title: "📐 Architectures",
                        value: "\(viewModel.archs.number)",
                        subtitle: viewModel.archTypesDescription
                    )

                    if let ipaViewModel = viewModel.sizeAnalyzer as? IPAViewModel,
                       let ipaAnalysis = viewModel.analysis as? IPAAnalysis {
                        StartupTimeAnalysisView(
                            viewModel: ipaViewModel,
                            analysis: ipaAnalysis
                        )
                    }
                }
                .padding(.horizontal)
                
                if let apkAnalysis = viewModel.analysis as? APKAnalysis {
                    androidSummarySection(for: apkAnalysis)
                        .padding(.horizontal)
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
                                    Text("\(String(format: "%.0f", (Double(category.totalSize) / Double(viewModel.analysis.totalSize)) * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.white)
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
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
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
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
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
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
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
    
    @State private var showAISummary: Bool = false
    
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
    private func androidSummarySection(for analysis: APKAnalysis) -> some View {
        let stats = androidStats(for: analysis)
        return VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
            if let minSDK = analysis.minSDK, let targetSDK = analysis.targetSDK {
                SummaryCard(
                    title: "🎯 SDK Targets",
                    value: "\(analysis.minSDK ?? "—") ▸ \(analysis.targetSDK ?? "—")",
                    subtitle: "Min ▸ Target"
                )
            }

            SummaryCard(
                title: "📚 Dex vs Native",
                value: "\(stats.dexCount) dex / \(stats.nativeLibCount) so",
                subtitle: stats.abiSubtitle
            )

            if analysis.permissions.isEmpty {
                SummaryCard(
                    title: "🔐 Permissions",
                    value: "\(analysis.permissions.count)",
                    subtitle: "\(stats.dangerousPermissions) dangerous"
                )
            } else {
                Button {
                    showPermissionsDetails.toggle()
                } label: {
                    SummaryCard(
                        title: "🔐 Permissions",
                        value: "\(analysis.permissions.count)",
                        subtitle: "\(stats.dangerousPermissions) dangerous"
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPermissionsDetails) {
                    AndroidPermissionsPopover(permissions: analysis.permissions)
                        .frame(width: 420, height: 360)
                }
            }

            // Certificate info card
            if let signatureInfo = analysis.signatureInfo {
                Button {
                    showCertificateInfo.toggle()
                } label: {
                    let certStatus = signatureInfo.isDebugSigned ? "Debug" :
                                    (signatureInfo.primaryCertificate?.isValid == true ? "Valid" : "Invalid")
                    SummaryCard(
                        title: "🔐 Certificate",
                        value: certStatus,
                        subtitle: signatureInfo.signatureSchemesDescription
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showCertificateInfo) {
                    CertificateInfoPopover(signatureInfo: signatureInfo)
                }
            }

            if let launchable = analysis.launchableActivity {
                SummaryCard(
                    title: "🚀 Launch Activity",
                    value: analysis.launchableActivityLabel ?? shortActivityName(launchable),
                    subtitle: launchable
                )
            }

            if !analysis.supportedLocales.isEmpty {
                SummaryCard(
                    title: "🌐 Locales",
                    value: "\(analysis.supportedLocales.count)",
                    subtitle: listPreviewDescription(for: analysis.supportedLocales, limit: 4)
                )
            }

            if shouldShowScreenCard(for: analysis) {
                SummaryCard(
                    title: "🖥️ Screen Buckets",
                    value: screenSupportValue(for: analysis),
                    subtitle: screenSupportSubtitle(for: analysis)
                )
            }

            if !analysis.requiredFeatures.isEmpty || !analysis.optionalFeatures.isEmpty {
                Button {
                    showFeatureDetails.toggle()
                } label: {
                    SummaryCard(
                        title: "🧩 Features",
                        value: "\(analysis.requiredFeatures.count) required",
                        subtitle: analysis.optionalFeatures.isEmpty
                            ? "Tap to inspect hardware features"
                            : "\(analysis.optionalFeatures.count) optional · Tap to inspect"
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showFeatureDetails) {
                    AndroidFeaturesPopover(
                        requiredFeatures: analysis.requiredFeatures,
                        optionalFeatures: analysis.optionalFeatures
                    )
                    .frame(width: 360, height: 320)
                }
            }

            // Image extraction card
            if let apkViewModel = viewModel as? APKDetailViewModel {
                Button {
                    showImageExtractionOptions.toggle()
                } label: {
                    SummaryCard(
                        title: "🖼️ Images",
                        value: "\(apkViewModel.imageCount)",
                        subtitle: extractionInProgress ? "Extracting..." : "Tap to extract"
                    )
                }
                .buttonStyle(.plain)
                .disabled(extractionInProgress)
                .confirmationDialog("Extract Images", isPresented: $showImageExtractionOptions) {
                    Button("Extract with folder structure") {
                        extractImages(from: apkViewModel, preserveStructure: true)
                    }
                    Button("Extract all to one folder") {
                        extractImages(from: apkViewModel, preserveStructure: false)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Choose how to extract \(apkViewModel.imageCount) images from the APK")
                }
                .alert("Image Extraction", isPresented: $showExtractionAlert) {
                    Button("OK") { }
                } message: {
                    Text(extractionAlertMessage)
                }
            }
            }
            
            manifestInsights(for: analysis)
        }
    }

    private func androidStats(for analysis: APKAnalysis) -> (dexCount: Int, nativeLibCount: Int, largestDexSize: Int64, dangerousPermissions: Int, abiSubtitle: String) {
        let files = analysis.rootFile.flattened(includeDirectories: false)
        let dexFiles = files.filter { $0.name.lowercased().hasSuffix(".dex") }
        let nativeLibs = files.filter { $0.name.lowercased().hasSuffix(".so") }
        let largestDex = dexFiles.map(\.size).max() ?? 0
        let dangerousPermissions = analysis.permissions.filter { perm in
            AndroidPermissionCatalog.dangerousPermissions.contains(perm)
        }.count
        let abiSubtitle: String
        let largestDexLabel = ByteCountFormatter.string(fromByteCount: largestDex, countStyle: .file)
        if analysis.supportedABIs.isEmpty {
            abiSubtitle = "Largest dex: \(largestDexLabel)"
        } else {
            abiSubtitle = "ABIs: \(analysis.supportedABIs.joined(separator: ", ")) · Dex max \(largestDexLabel)"
        }
        return (dexFiles.count, nativeLibs.count, largestDex, dangerousPermissions, abiSubtitle)
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
                                        .foregroundColor(.secondary)
                                    Text(formatSize(lib.estimatedSize))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            if lib.id != displayed.last?.id {
                                Divider()
                            }
                        }
                        if thirdPartyLibraries.count > displayed.count {
                            Text("+\(thirdPartyLibraries.count - displayed.count) more SDKs")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                                    .foregroundColor(.secondary)
                            }
                            if link.id != displayed.last?.id {
                                Divider()
                            }
                        }
                        if deepLinks.count > displayed.count {
                            Text("+\(deepLinks.count - displayed.count) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                                                .foregroundColor(.secondary)
                                        }
                                        if !filter.categories.isEmpty {
                                            Text("Categories: \(filter.categories.joined(separator: ", "))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        if let dataSummary = intentDataSummary(filter.data) {
                                            Text("Data: \(dataSummary)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
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
                                .foregroundColor(.secondary)
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
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(component.name)
                                        .font(.body)
                                    if let label = component.label {
                                        Text(label)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
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
                                .foregroundColor(.secondary)
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

    private func shortActivityName(_ name: String) -> String {
        name.components(separatedBy: ".").last ?? name
    }

    private func listPreviewDescription(for values: [String], limit: Int = 3) -> String {
        guard !values.isEmpty else { return "—" }
        let displayed = values.prefix(limit)
        var summary = displayed.joined(separator: ", ")
        let remaining = values.count - displayed.count
        if remaining > 0 {
            summary += " +\(remaining)"
        }
        return summary
    }

    private func shouldShowScreenCard(for analysis: APKAnalysis) -> Bool {
        !analysis.supportsScreens.isEmpty || !analysis.densities.isEmpty || analysis.supportsAnyDensity != nil
    }

    private func screenSupportValue(for analysis: APKAnalysis) -> String {
        if !analysis.supportsScreens.isEmpty {
            return listPreviewDescription(for: analysis.supportsScreens, limit: 4)
        }
        if let supportsAnyDensity = analysis.supportsAnyDensity, supportsAnyDensity {
            return "Any density"
        }
        return "—"
    }

    private func screenSupportSubtitle(for analysis: APKAnalysis) -> String? {
        var parts: [String] = []
        if !analysis.densities.isEmpty {
            parts.append("DPI \(listPreviewDescription(for: analysis.densities, limit: 4))")
        }
        if let supportsAnyDensity = analysis.supportsAnyDensity {
            parts.append(supportsAnyDensity ? "Runs on all densities" : "Limited densities")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
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
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
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

    private func extractImages(from apkViewModel: APKDetailViewModel, preserveStructure: Bool) {
        extractionInProgress = true

        Task { @MainActor in
            if let result = apkViewModel.extractImages(preserveStructure: preserveStructure) {
                extractionInProgress = false

                if result.errors.isEmpty {
                    extractionAlertMessage = "Successfully extracted \(result.extractedImages) of \(result.totalImages) images!"
                    showExtractionAlert = true
                    apkViewModel.revealExtractedImages(result)
                } else {
                    extractionAlertMessage = "Extracted \(result.extractedImages) of \(result.totalImages) images with \(result.errors.count) errors."
                    showExtractionAlert = true
                }
            } else {
                extractionInProgress = false
            }
        }
    }
}
