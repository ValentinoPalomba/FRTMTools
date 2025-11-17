import SwiftUI

struct PlayStoreToolSelectionDetailView: View {
    @ObservedObject var viewModel: PlayStoreToolViewModel

    var body: some View {
        VStack {
            if let app = viewModel.selectedApp {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.displayName)
                            .font(.largeTitle.weight(.bold))
                        Text(app.package_name)
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        if let creator = app.creator {
                            HStack {
                                Text("Creator:")
                                    .font(.headline)
                                Text(creator)
                                    .font(.body)
                            }
                        }
                        if let version = app.version {
                            HStack {
                                Text("Version:")
                                    .font(.headline)
                                Text(version)
                                    .font(.body)
                            }
                        }
                        if let size = app.size {
                            HStack {
                                Text("Size:")
                                    .font(.headline)
                                Text(size)
                                    .font(.body)
                            }
                        }
                    }

                    Spacer()

                    if viewModel.isDownloading {
                        ProgressView()
                            .progressViewStyle(.linear)
                        ScrollView {
                            Text(viewModel.downloadLog)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                    } else {
                        Button(action: download) {
                            Label("Download APK", systemImage: "arrow.down.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            } else {
                Text("Select an app to see details.")
                    .font(.title)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func download() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select a directory to save the APK"

        if panel.runModal() == .OK {
            if let directoryURL = panel.url {
                viewModel.downloadSelectedApp(to: directoryURL) { downloadedURL in
                    NSWorkspace.shared.activateFileViewerSelecting([downloadedURL])
                }
            }
        }
    }
}
