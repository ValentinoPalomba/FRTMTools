//
//  ipaAnalyzerApp.swift
//  ipaAnalyzer
//
//  Created by PALOMBA VALENTINO on 02/09/25.
//

import SwiftUI
import AppKit

@main
struct FRTMTools: App {
    
    init() {
        DependencyRegister.register()
    }
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var showCleanCacheConfirmation = false
    @State private var showClearAppStoreCacheConfirmation = false
    
    private var extractedIPAsCacheURL: URL { CacheLocations.extractedIPAsDirectory }

    private func ensureExtractedCacheExists() {
        CacheLocations.ensureExtractedIPAsDirectoryExists()
    }

    private func showExtractedIPAsInFinder() {
        ensureExtractedCacheExists()
        NSWorkspace.shared.activateFileViewerSelecting([extractedIPAsCacheURL])
    }

    private func cleanExtractedIPAsCache() {
        let fm = FileManager.default
        if fm.fileExists(atPath: extractedIPAsCacheURL.path) {
            try? fm.removeItem(at: extractedIPAsCacheURL)
        }
    }

    private func clearAppStoreVersionsCache() {
        IPAToolClient.removePersistedMetadataCache()
        NotificationCenter.default.post(name: .clearIPAToolMetadataCache, object: nil)
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                }
                .alert("Clean Extracted IPAs Cache?", isPresented: $showCleanCacheConfirmation) {
                    Button("Delete", role: .destructive) {
                        cleanExtractedIPAsCache()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove all extracted IPA copies from the cache.")
                }
                .confirmationDialog("Clear App Store Versions Cache?", isPresented: $showClearAppStoreCacheConfirmation, titleVisibility: .visible) {
                    Button("Clear Cache", role: .destructive) {
                        clearAppStoreVersionsCache()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will delete cached ipatool version metadata so the app can fetch fresh data.")
                }
        }
        .commands {
            CommandMenu("Cache") {
                Button("Show Extracted IPAs in Finder") {
                    showExtractedIPAsInFinder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Clean Extracted IPAs Cache", role: .destructive) {
                    showCleanCacheConfirmation = true
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])

                Divider()

                Button("Clear App Store Versions Cache", role: .destructive) {
                    showClearAppStoreCacheConfirmation = true
                }
            }
        }
    }
}
