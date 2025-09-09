import SwiftUI
import AppKit
import FRTMCore

class UnusedAssetsViewModel: ObservableObject {
    @Published var result: UnusedAssetResult?
    @Published var isLoading = false
    @Published var error: UnusedAssetsError?

    @Dependency var analyzer: any Analyzer<UnusedAssetResult>

    func analyzeProject(at url: URL) {
        isLoading = true
        error = nil
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                if let analysisResult = try await self.analyzer.analyze(at: url) {
                    await MainActor.run {
                        withAnimation {
                            self.result = analysisResult
                            self.isLoading = false
                        }
                    }
                } else {
                     await MainActor.run {
                        self.isLoading = false
                        // Optional: Set a specific error for no results
                    }
                }
            } catch let anError as UnusedAssetsError {
                await MainActor.run {
                    self.error = anError
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = .invalidConfiguration
                    self.isLoading = false
                }
            }
        }
    }

    func selectProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select a project folder"

        if panel.runModal() == .OK, let url = panel.url {
            analyzeProject(at: url)
        }
    }
}
