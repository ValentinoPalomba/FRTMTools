import SwiftUI
import AppKit

struct IPAToolContentView: View {
    @ObservedObject var viewModel: IPAToolViewModel
    @FocusState private var focusedField: Field?
    @Environment(\.theme) private var theme

    private enum Field: Hashable {
        case email
        case password
        case otp
        case search
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if viewModel.isLoggedIn {
                    authenticationSummary
                } else {
                    authenticationSection
                }
                searchSection
                if viewModel.selectedApp == nil {
                    Text("Select an app in the list to inspect its versions and download the .ipa on the right.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(theme.palette.background)
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
                        .disabled(viewModel.isAwaitingOTP)
                        .frame(minWidth: 240)
                }
                GridRow {
                    Text("Password").font(.subheadline).foregroundStyle(.secondary)
                    SecureField("Password", text: $viewModel.loginPassword)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .password)
                        .disabled(viewModel.isAwaitingOTP)
                        .frame(minWidth: 200)
                }
                GridRow {
                    Text("OTP").font(.subheadline).foregroundStyle(.secondary)
                    TextField("One-time code (if prompted)", text: $viewModel.loginOTP)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .otp)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(viewModel.isAwaitingOTP ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                        .frame(minWidth: 200)
                }
            }

            HStack(spacing: 12) {
                Button(action: viewModel.login) {
                    if viewModel.loginInProgress {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Label(viewModel.isAwaitingOTP ? "Submit OTP" : "Sign In",
                              systemImage: viewModel.isAwaitingOTP ? "number.circle" : "key.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.loginInProgress ||
                    (viewModel.isAwaitingOTP ? viewModel.loginOTP.isEmpty : (viewModel.loginEmail.isEmpty || viewModel.loginPassword.isEmpty))
                )

                Button(role: .cancel) {
                    viewModel.loginEmail = ""
                    viewModel.loginPassword = ""
                    viewModel.loginOTP = ""
                    viewModel.isAwaitingOTP = false
                    focusedField = .email
                } label: {
                    Text("Clear")
                }
                .disabled(viewModel.loginEmail.isEmpty && viewModel.loginPassword.isEmpty && viewModel.loginOTP.isEmpty)

                Spacer()
            }

            if viewModel.isAwaitingOTP {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(theme.palette.accent)
                    Text("A verification code has been sent to your trusted device. Enter the OTP above and press Submit OTP within a few minutes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
                        .fill(theme.palette.surface)
                )
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.palette.border))
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

    private var authenticationSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 34))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signed in")
                        .font(.title3.weight(.semibold))
                    Text("You are authenticated with ipatool and ready to download apps.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    viewModel.refreshInstallationState()
                } label: {
                    Label("Re-check status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    focusedField = .email
                    viewModel.requireReauthentication()
                } label: {
                    Label("Switch account", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)

                Spacer()
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
                    .controlSize(.large)
                    .disabled(viewModel.isSearching || viewModel.searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear Results") {
                        viewModel.searchResults = []
                        viewModel.searchTerm = ""
                        viewModel.selectedApp = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)
                    .controlSize(.large)
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
