import Foundation
import SwiftUI

@MainActor
final class PlayStoreToolViewModel: ObservableObject {
    @Published var isInstalled: Bool = false
    @Published var searchTerm: String = ""
    @Published var isSearching: Bool = false
    @Published var searchResults: [PlayStoreApp] = []

    @Published var selectedApp: PlayStoreApp? = nil

    @Published var isDownloading: Bool = false
    @Published var downloadLog: String = ""
    @Published var downloadAlert: AlertContent? = nil

    let client = PlayStoreToolClient()

    struct AlertContent: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    func refreshInstallationState() {
        Task { @MainActor in
            self.isInstalled = await client.isInstalled()
        }
    }

    func search() {
        Task { @MainActor in
            guard !searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                self.searchResults = try await client.searchApps(term: searchTerm)
            } catch {
                self.searchResults = []
            }
        }
    }

    func selectApp(_ app: PlayStoreApp) {
        selectedApp = app
    }

    func downloadSelectedApp(to directory: URL, completion: @escaping (URL) -> Void) {
        guard let app = selectedApp else { return }
        Task { @MainActor in
            isDownloading = true
            downloadLog = ""
            defer { isDownloading = false }
            do {
                let apkURL = try await client.downloadAPK(
                    packageName: app.package_name,
                    to: directory
                ) { [weak self] line in
                    Task { @MainActor in self?.downloadLog += line }
                }
                completion(apkURL)
            } catch {
                self.downloadAlert = AlertContent(title: "Download Failed", message: error.localizedDescription)
            }
        }
    }
}
