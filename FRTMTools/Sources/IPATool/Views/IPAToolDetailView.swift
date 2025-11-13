import SwiftUI
import AppKit

struct IPAToolDetailView: View {
    @ObservedObject var viewModel: IPAToolViewModel
    let selectedApp: IPAToolStoreApp
    @State private var gradientColors: [Color]
    @State private var usesLightText: Bool

    init(viewModel: IPAToolViewModel, selectedApp: IPAToolStoreApp) {
        self.viewModel = viewModel
        self.selectedApp = selectedApp
        let palette = defaultAppGradient(for: selectedApp)
        _gradientColors = State(initialValue: palette.colors.map { Color(nsColor: $0) })
        _usesLightText = State(initialValue: palette.useLightText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            versionsSection
            downloadSection
            logSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: selectedApp.id) {
            await updateGradientPalette()
        }
    }

    private var headerSection: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.12))
                    .blendMode(.plusLighter)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 18) {
                    ArtworkImageView(url: makeArtworkURL(from: selectedApp.artworkUrl100), size: 88, cornerRadius: 20)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedApp.trackName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(headerPrimaryColor)
                        Text(selectedApp.bundleId)
                            .font(.caption)
                            .foregroundStyle(headerSecondaryColor)
                            .textSelection(.enabled)
                        if let seller = selectedApp.sellerName {
                            Text("by \(seller)")
                                .font(.caption)
                                .foregroundStyle(headerSecondaryColor)
                        }
                    }
                    Spacer()
                    if let price = selectedApp.formattedPrice ?? selectedApp.priceString {
                        ChipView(
                            title: price,
                            systemImage: "tag.fill",
                            style: usesLightText ? .light : .dark
                        )
                    }
                }

                metricsRow
            }
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.2))
        )
    }

    private var metricsRow: some View {
        HStack(spacing: 18) {
            MetricTile(
                title: "Versions",
                value: "\(viewModel.versions.count)",
                icon: "clock.arrow.circlepath",
                usesLightText: usesLightText
            )
            MetricTile(
                title: "Selected",
                value: viewModel.selectedVersion?.displayVersion ?? "None",
                icon: "app.fill",
                usesLightText: usesLightText
            )
        }
    }

    private var headerPrimaryColor: Color {
        usesLightText ? .white : .primary
    }

    private var headerSecondaryColor: Color {
        usesLightText ? Color.white.opacity(0.85) : Color.secondary
    }

    private func updateGradientPalette() async {
        let fallback = defaultAppGradient(for: selectedApp)
        guard let url = makeArtworkURL(from: selectedApp.artworkUrl100) else {
            applyPalette(fallback)
            return
        }
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let image = NSImage(data: data) {
                let palette = AppIconPaletteGenerator.palette(from: image, fallback: fallback)
                applyPalette(palette)
                return
            }
        } catch {
            // Fallback to default palette on failure
        }
        applyPalette(fallback)
    }

    @MainActor
    private func applyPalette(_ palette: AppGradientPalette) {
        gradientColors = palette.colors.map { Color(nsColor: $0) }
        usesLightText = palette.useLightText
    }

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Versions", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.selectApp(selectedApp)
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoadingVersions)

                if viewModel.isLoadingVersions {
                    ProgressView().controlSize(.small)
                }
            }

            Divider()

            if viewModel.isLoadingVersions {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else if viewModel.versions.isEmpty {
                Text("No versions available for this app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                versionsList
                    .frame(minHeight: 160, maxHeight: 280)
            }
        }
        .sectionCard()
    }

    private var versionsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.versions) { version in
                    let isSelected = viewModel.selectedVersion?.id == version.id
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.selectedVersion = version
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(version.displayVersion ?? version.version)
                                    .font(.body.weight(isSelected ? .semibold : .regular))
                                    .foregroundColor(.primary)
                                if let build = version.build, !build.isEmpty {
                                    Text("Build \(build)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let identifier = version.externalIdentifier, !identifier.isEmpty {
                                    Text(identifier)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    Divider()
                        .padding(.leading, 30)
                }
            }
        }
    }

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Download", systemImage: "square.and.arrow.down")
                .font(.headline)
            Divider()
            HStack {
                Button(action: startDownload) {
                    if viewModel.isDownloading {
                        ProgressView()
                    } else {
                        Label(downloadButtonTitle, systemImage: "tray.and.arrow.down.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isDownloading || viewModel.selectedVersion == nil)

                if let selection = viewModel.selectedVersion {
                    Text("Will download version \(selection.version) for \(selectedApp.bundleId).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Choose a version first.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sectionCard()
    }

    private var logSection: some View {
        Group {
            if !viewModel.downloadLog.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Activity Log", systemImage: "terminal")
                            .font(.headline)
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.downloadLog = ""
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Clear log")
                    }
                    Divider()
                    ScrollView {
                        Text(viewModel.downloadLog)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 100, maxHeight: 200)
                }
                .sectionCard()
            }
        }
    }

    private var downloadButtonTitle: String {
        if let display = viewModel.selectedVersion?.displayVersion ?? viewModel.selectedVersion?.version {
            return "Download \(display)"
        }
        return "Download"
    }

    private func startDownload() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose Folder"
        panel.message = "Select where the downloaded .ipa should be saved."
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let directory = panel.url {
            viewModel.downloadSelectedApp(to: directory) { url in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}
