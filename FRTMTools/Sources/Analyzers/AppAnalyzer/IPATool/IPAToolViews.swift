import SwiftUI
import AppKit

struct IPAToolContentView: View {
    @ObservedObject var viewModel: IPAToolViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email
        case password
        case otp
        case search
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                authenticationSection
                searchSection
                if viewModel.selectedApp == nil {
                    Text("Select an app in the list to inspect its versions and download the .ipa on the right.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { viewModel.refreshInstallationState() }
        .alert(item: $viewModel.downloadAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("App Store Connector")
                    .font(.largeTitle.weight(.semibold))
                Text("Authenticate, search, and retrieve .ipa files using ipatool.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.refreshInstallationState()
            } label: {
                Label("Refresh Status", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Authentication", systemImage: "person.badge.key.fill")
                    .font(.headline)
                Spacer()
                statusBadge
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Email").font(.subheadline).foregroundStyle(.secondary)
                    TextField("Apple ID email", text: $viewModel.loginEmail)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .email)
                        .frame(minWidth: 240)
                }
                GridRow {
                    Text("Password").font(.subheadline).foregroundStyle(.secondary)
                    SecureField("Password", text: $viewModel.loginPassword)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .password)
                        .frame(minWidth: 200)
                }
                GridRow {
                    Text("OTP").font(.subheadline).foregroundStyle(.secondary)
                    TextField("One-time code (if prompted)", text: $viewModel.loginOTP)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .otp)
                        .frame(minWidth: 200)
                }
            }

            HStack(spacing: 12) {
                Button(action: viewModel.login) {
                    if viewModel.loginInProgress {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Label("Sign In", systemImage: "key.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.loginInProgress || viewModel.loginEmail.isEmpty || viewModel.loginPassword.isEmpty)

                Button(role: .cancel) {
                    viewModel.loginEmail = ""
                    viewModel.loginPassword = ""
                    viewModel.loginOTP = ""
                    focusedField = .email
                } label: {
                    Text("Clear")
                }
                .disabled(viewModel.loginEmail.isEmpty && viewModel.loginPassword.isEmpty && viewModel.loginOTP.isEmpty)

                Spacer()
            }

            if let msg = viewModel.loginMessage, !msg.isEmpty {
                ScrollView {
                    Text(msg)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }

            if !viewModel.isInstalled {
                VStack(alignment: .leading, spacing: 4) {
                    Label("ipatool not detected", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                    Text("Install via Homebrew (`brew install ipatool`) or place the binary in your PATH. You can also add ~/homebrew/bin to PATH.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                )
            }
        }
        .sectionCard()
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Search App Store", systemImage: "magnifyingglass")
                    .font(.headline)
                Spacer()
                if viewModel.isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search apps by name, bundle ID, or developer", text: $viewModel.searchTerm)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .search)
                    .disabled(viewModel.isSearching)
                    .onSubmit { viewModel.search() }

                HStack(spacing: 12) {
                    Button {
                        viewModel.search()
                    } label: {
                        Label("Search", systemImage: "text.magnifyingglass")
                            .frame(minWidth: 90)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSearching || viewModel.searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear Results") {
                        viewModel.searchResults = []
                        viewModel.searchTerm = ""
                        viewModel.selectedApp = nil
                    }
                    .disabled(viewModel.searchResults.isEmpty && viewModel.searchTerm.isEmpty)
                    Spacer()
                }
            }

            if viewModel.searchResults.isEmpty {
                Text("No results yet. Try searching for a bundle identifier or app name.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } else {
                searchResultsList
            }
        }
        .sectionCard()
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.searchResults) { app in
                    Button {
                        viewModel.selectApp(app)
                    } label: {
                        SearchResultRow(app: app, isSelected: viewModel.selectedApp?.id == app.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minHeight: 220)
    }

    private var statusBadge: some View {
        Label(
            viewModel.isLoggedIn ? "Signed In" : "Signed Out",
            systemImage: viewModel.isLoggedIn ? "checkmark.shield.fill" : "xmark.shield"
        )
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill((viewModel.isLoggedIn ? Color.green : Color.secondary).opacity(0.15))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke((viewModel.isLoggedIn ? Color.green : Color.secondary).opacity(0.3))
        )
    }
}

struct IPAToolDetailView: View {
    @ObservedObject var viewModel: IPAToolViewModel
    let selectedApp: IPAToolStoreApp

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            versionsSection
            downloadSection
            logSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                ArtworkImageView(url: makeArtworkURL(from: selectedApp.artworkUrl100), size: 80, cornerRadius: 16)
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedApp.trackName)
                        .font(.title3.weight(.semibold))
                    Text(selectedApp.bundleId)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                    if let seller = selectedApp.sellerName {
                        Text(seller)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let price = selectedApp.formattedPrice ?? selectedApp.priceString {
                    Text(price)
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
            }
        }
        .sectionCard()
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
            LazyVStack(spacing: 0) {
                ForEach(viewModel.versions) { version in
                    let isSelected = viewModel.selectedVersion?.id == version.id
                    Button {
                        viewModel.selectedVersion = version
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(versionTitle(version))
                                    .font(.body.weight(isSelected ? .semibold : .regular))
                            }
                            Spacer()
                            if let identifier = version.externalIdentifier, !identifier.isEmpty {
                                Text(identifier)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                    Label("Activity Log", systemImage: "terminal")
                        .font(.headline)
                    Divider()
                    ScrollView {
                        Text(viewModel.downloadLog)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 100, maxHeight: 180)
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
                VStack(spacing: 12) {
                    Image(systemName: "bag.badge.plus")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                    Text("Select an app from the list to inspect versions.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Helpers & Subviews

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
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.secondary.opacity(0.1))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "app")
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(.secondary.opacity(0.6))
            )
    }
}

private struct SearchResultRow: View {
    let app: IPAToolStoreApp
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ArtworkImageView(url: makeArtworkURL(from: app.artworkUrl100), size: 44, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.trackName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(app.bundleId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if let price = app.formattedPrice ?? app.priceString {
                Text(price)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.black.opacity(0.04))
        )
    }
}

private struct SectionCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.05))
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
    }
}

private extension View {
    func sectionCard() -> some View {
        modifier(SectionCard())
    }
}

private func versionTitle(_ version: IPAToolAppVersion) -> String {
    if let display = version.displayVersion, !display.isEmpty {
        if let build = version.build, !build.isEmpty {
            return "\(display) (\(build))"
        }
        return display
    }
    if let build = version.build, !build.isEmpty {
        return "\(version.version) (\(build))"
    }
    return version.version
}

private extension IPAToolStoreApp {
    var priceString: String? {
        guard let price else { return nil }
        if price == 0 {
            return "Free"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        if #available(macOS 13.0, *) {
            formatter.currencyCode = Locale.current.currency?.identifier ?? Locale.current.currencyCode ?? "USD"
        } else {
            formatter.currencyCode = Locale.current.currencyCode ?? "USD"
        }
        return formatter.string(from: NSNumber(value: price))
    }
}
