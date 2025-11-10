import SwiftUI
import AppKit

struct IPAToolContentView: View {
    @ObservedObject var viewModel: IPAToolViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("App Store")
                    .font(.title2).bold()
                Spacer()
                Button("Refresh") { viewModel.refreshInstallationState() }
            }

            GroupBox(label: Label("Authentication", systemImage: "person.badge.key.fill")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Status: \(viewModel.isLoggedIn ? "🟢 Logged" : "🔴 Unlogged")")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("Apple ID email", text: $viewModel.loginEmail)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 260)
                        SecureField("Password", text: $viewModel.loginPassword)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180)
                        TextField("OTP (if prompted)", text: $viewModel.loginOTP)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 160)
                        Button(action: { viewModel.login() }) {
                            if viewModel.loginInProgress {
                                ProgressView()
                            } else {
                                Text("Login")
                            }
                        }
                        .disabled(viewModel.loginInProgress)
                    }
                    if let msg = viewModel.loginMessage, !msg.isEmpty {
                        ScrollView { Text(msg).font(.caption.monospaced()) }
                            .frame(maxHeight: 80)
                    }
                    if !viewModel.isInstalled {
                        Text("ipatool not found. Install with Homebrew: brew install ipatool")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
                .padding(.vertical, 6)
            }

            GroupBox(label: Label("Search", systemImage: "magnifyingglass")) {
                HStack(spacing: 8) {
                    TextField("Search App Store…", text: $viewModel.searchTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { viewModel.search() }
                    Button("Search") { viewModel.search() }
                        .disabled(viewModel.isSearching)
                }
                if viewModel.isSearching {
                    ProgressView().padding(.top, 6)
                }
                List(viewModel.searchResults, id: \.id) { app in
                    Button(action: { viewModel.selectApp(app) }) {
                        HStack(alignment: .center, spacing: 12) {
                            ArtworkImageView(url: makeArtworkURL(from: app.artworkUrl100), size: 44, cornerRadius: 8)
                            VStack(alignment: .leading) {
                                Text(app.trackName).font(.headline)
                                Text(app.bundleId).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let price = app.formattedPrice { Text(price).font(.footnote) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 200)
            }

            if viewModel.selectedApp == nil {
                Text("Select an app to see its versions in the detail pane →")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .onAppear { viewModel.refreshInstallationState() }
        .alert(item: $viewModel.downloadAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }
}

private func makeArtworkURL(from string: String?) -> URL? {
    guard let s = string, let url = URL(string: s) else { return nil }
    return url
}

private struct ArtworkImageView: View {
    let url: URL?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                placeholder
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Color.gray.opacity(0.2)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct IPAToolDetailView: View {
    @ObservedObject var viewModel: IPAToolViewModel
    let selectedApp: IPAToolStoreApp

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            versionsSection
            downloadRow
            logSection
        }
        .padding(.top, 8)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ArtworkImageView(url: makeArtworkURL(from: selectedApp.artworkUrl100), size: 72, cornerRadius: 12)
            VStack(alignment: .leading) {
                Text(selectedApp.trackName)
                    .font(.title3)
                    .bold()
                Text(selectedApp.bundleId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let seller = selectedApp.sellerName {
                    Text(seller)
                        .font(.caption)
                }
            }
            Spacer()
        }
    }

    private var versionsSection: some View {
        GroupBox(label:
            HStack(spacing: 8) {
                Label("Versions", systemImage: "clock.arrow.circlepath")
                Spacer()
                Button {
                    // Re-trigger versions loading by re-selecting the current app
                    viewModel.selectApp(selectedApp)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Reload versions")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoadingVersions)
                if viewModel.isLoadingVersions {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        ) {
            if viewModel.isLoadingVersions {
                ProgressView()
                    .padding(.vertical, 8)
            } else if viewModel.versions.isEmpty {
                Text("No versions found.")
                    .foregroundStyle(.secondary)
            } else {
                versionsList
                    .frame(maxHeight: 200)
            }
        }
    }

    private var versionsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.versions) { ver in
                    let isSelected = viewModel.selectedVersion?.id == ver.id
                    Button(action: { viewModel.selectedVersion = ver }) {
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(versionTitle(ver))
                                if let subtitle = versionSubtitle(ver) {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    private var downloadRow: some View {
        HStack {
            Button(action: startDownload) {
                if viewModel.isDownloading {
                    ProgressView()
                } else {
                    Label(downloadButtonTitle, systemImage: "square.and.arrow.down")
                }
            }
            .disabled(viewModel.isDownloading)
            Spacer()
        }
    }

    private var downloadButtonTitle: String {
        if let v = viewModel.selectedVersion?.displayVersion ?? viewModel.selectedVersion?.version {
            return "Download \(v) .ipa"
        } else {
            return "Download .ipa"
        }
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

    private var logSection: some View {
        Group {
            if !viewModel.downloadLog.isEmpty {
                GroupBox(label: Label("Log", systemImage: "terminal")) {
                    ScrollView {
                        Text(viewModel.downloadLog)
                            .font(.caption.monospaced())
                    }
                    .frame(minHeight: 80, maxHeight: 160)
                }
            }
        }
    }
}

struct IPAToolSelectionDetailView: View {
    @ObservedObject var viewModel: IPAToolViewModel

    var body: some View {
        Group {
            if let selected = viewModel.selectedApp {
                ScrollView {
                    IPAToolDetailView(viewModel: viewModel, selectedApp: selected)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                Text("Select an app from the list to see its App Store versions.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private let versionDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()

private func versionTitle(_ version: IPAToolAppVersion) -> String {
    if let display = version.displayVersion, !display.isEmpty {
        if let build = version.build, !build.isEmpty {
            return "\(display) (\(build))"
        }
        let identifier = version.externalIdentifier ?? version.version
        if identifier == display {
            return display
        } else {
            return "\(display) (\(identifier))"
        }
    }
    if let build = version.build, !build.isEmpty {
        return "\(version.version) (\(build))"
    }
    return version.version
}

private func versionSubtitle(_ version: IPAToolAppVersion) -> String? {
    guard let date = version.releaseDate else { return nil }
    return versionDateFormatter.string(from: date)
}
