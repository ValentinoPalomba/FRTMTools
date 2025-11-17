import SwiftUI

struct PlayStoreToolContentView: View {
    @ObservedObject var viewModel: PlayStoreToolViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case search
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                searchSection
                if viewModel.selectedApp == nil {
                    Text("Select an app in the list to inspect its details and download the .apk on the right.")
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
                Text("Play Store Connector")
                    .font(.largeTitle.weight(.semibold))
                Text("Search and retrieve .apk files using gplaycli.")
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

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Search Play Store", systemImage: "magnifyingglass")
                    .font(.headline)
                Spacer()
                if viewModel.isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search apps by name or package ID", text: $viewModel.searchTerm)
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

            if !viewModel.isInstalled {
                VStack(alignment: .leading, spacing: 4) {
                    Label("gplaycli not detected", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                    Text("Install via pip (`pip install gplaycli`) or place the binary in your PATH.")
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

            if viewModel.searchResults.isEmpty {
                Text("No results yet. Try searching for a package identifier or app name.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } else {
                searchResultsList
            }
        }
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.searchResults) { app in
                    Button {
                        viewModel.selectApp(app)
                    } label: {
                        PlayStoreSearchResultRow(app: app, isSelected: viewModel.selectedApp?.id == app.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minHeight: 220)
    }
}
