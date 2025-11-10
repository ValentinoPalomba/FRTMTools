import Foundation
import SwiftUI

@MainActor
final class IPAToolViewModel: ObservableObject {
    @Published var isInstalled: Bool = false
    @Published var isLoggedIn: Bool = false
    @Published var loginEmail: String = ""
    @Published var loginPassword: String = ""
    @Published var loginOTP: String = ""
    @Published var loginInProgress: Bool = false
    @Published var loginMessage: String? = nil

    @Published var searchTerm: String = ""
    @Published var isSearching: Bool = false
    @Published var searchResults: [IPAToolStoreApp] = []

    @Published var selectedApp: IPAToolStoreApp? = nil
    @Published var versions: [IPAToolAppVersion] = []
    @Published var selectedVersion: IPAToolAppVersion? = nil
    @Published var isLoadingVersions: Bool = false

    @Published var isDownloading: Bool = false
    @Published var downloadLog: String = ""
    @Published var downloadAlert: AlertContent? = nil

    let client = IPAToolClient()

    struct AlertContent: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    func refreshInstallationState() {
        Task { @MainActor in
            self.isInstalled = await client.isInstalled()
            do {
                self.isLoggedIn = try await client.authInfo()
            } catch {
                self.isLoggedIn = false
            }
        }
    }

    func login() {
        Task { @MainActor in
            guard !loginEmail.isEmpty, !loginPassword.isEmpty else {
                self.loginMessage = "Email and password are required."
                return
            }
            loginInProgress = true
            loginMessage = nil
            defer { loginInProgress = false }
            do {
                let output = try await client.login(email: loginEmail, password: loginPassword, otp: loginOTP.isEmpty ? nil : loginOTP)
                self.loginMessage = output
                self.isLoggedIn = try (await client.authInfo())
            } catch {
                self.loginMessage = error.localizedDescription
                self.isLoggedIn = false
            }
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

    func selectApp(_ app: IPAToolStoreApp) {
        selectedApp = app
        loadVersions(for: app)
    }

    func loadVersions(for app: IPAToolStoreApp) {
        Task { @MainActor in
            isLoadingVersions = true
            defer { isLoadingVersions = false }
            let list = await client.listVersions(bundleId: app.bundleId, appId: app.id, fallbackCurrentVersion: app.version)
            self.versions = list
            self.selectedVersion = list.first
        }
    }

    func downloadSelectedApp(to directory: URL, completion: @escaping (URL) -> Void) {
        guard let app = selectedApp else { return }
        Task { @MainActor in
            isDownloading = true
            downloadLog = ""
            defer { isDownloading = false }
            do {
                let selectedIdentifier = self.selectedVersion?.externalIdentifier ?? self.selectedVersion?.version
                let ipaURL = try await client.downloadIPA(
                    bundleId: app.bundleId,
                    appId: app.id,
                    externalVersionId: selectedIdentifier,
                    to: directory
                ) { [weak self] line in
                    Task { @MainActor in self?.downloadLog += line }
                }
                completion(ipaURL)
            } catch {
                self.downloadAlert = AlertContent(title: "Download Failed", message: error.localizedDescription)
            }
        }
    }

    func clearMetadataCache() {
        client.clearMetadataCache()
        versions.removeAll()
        selectedVersion = nil
        if let app = selectedApp {
            loadVersions(for: app)
        }
    }
}
