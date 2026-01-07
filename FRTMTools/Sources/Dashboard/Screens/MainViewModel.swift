import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MainViewModel {
    enum Tool: String, Hashable, Identifiable, CaseIterable {
        case ipaAnalyzer = "IPA Analyzer"
        case apkAnalyzer = "APK/ABB Analyzer"
        case unusedAssets = "Unused Assets Analyzer"
        case securityScanner = "Security Scanner"
        case deadCodeScanner = "Dead Code Scanner"
        case ipatool = "App Store"
        case badWordScanner = "Bad Word Scanner"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .ipaAnalyzer: "app.badge"
            case .apkAnalyzer: "shippingbox"
            case .unusedAssets: "trash"
            case .securityScanner: "shield.lefthalf.filled"
            case .deadCodeScanner: "text.magnifyingglass"
            case .ipatool: "bag.badge.plus"
            case .badWordScanner: "exclamationmark.bubble"
            }
        }

        var tintRole: TintRole {
            switch self {
            case .ipaAnalyzer: .accent
            case .apkAnalyzer: .success
            case .unusedAssets: .accentMuted
            case .securityScanner: .danger
            case .deadCodeScanner: .warning
            case .ipatool: .success
            case .badWordScanner: .accentMuted
            }
        }
    }

    enum TintRole: Hashable {
        case accent
        case accentMuted
        case success
        case warning
        case danger
    }

    struct LoaderPresentation: Equatable {
        var title: String
        var subtitle: String
    }

    var selectedTool: Tool? = .ipaAnalyzer
    var hoveredTool: Tool? = nil

    let ipaViewModel = IPAViewModel()
    let apkViewModel = APKViewModel()
    let unusedAssetsViewModel = UnusedAssetsViewModel()
    let securityScannerViewModel = SecurityScannerViewModel()
    let deadCodeViewModel = DeadCodeViewModel()
    let ipaToolViewModel = IPAToolViewModel()
    let badWordScannerViewModel = BadWordScannerViewModel()

    var activeLoader: LoaderPresentation? {
        if ipaViewModel.isLoading {
            return LoaderPresentation(
                title: "Analyzing IPA",
                subtitle: "This can take a few minutes…"
            )
        }

        if apkViewModel.isLoading {
            return LoaderPresentation(
                title: "Analyzing APK/ABB",
                subtitle: "Unpacking bundle…"
            )
        }

        if unusedAssetsViewModel.isLoading {
            return LoaderPresentation(
                title: "Analyzing project...",
                subtitle: "Finding unused assets..."
            )
        }

        if deadCodeViewModel.isLoading {
            return LoaderPresentation(
                title: "Analyzing project...",
                subtitle: "Finding dead code..."
            )
        }

        if securityScannerViewModel.isLoading {
            return LoaderPresentation(
                title: "Scanning project...",
                subtitle: "Searching for secrets..."
            )
        }

        return nil
    }

    func onAppear() {
        if selectedTool == .ipatool {
            ipaToolViewModel.refreshInstallationState()
        }
    }

    func handleSelectedToolChange(oldValue: Tool?, newValue: Tool?) {
        guard oldValue != newValue else { return }
        if newValue == .ipatool {
            ipaToolViewModel.refreshInstallationState()
        }
    }

    func clearIPAToolMetadataCache() {
        ipaToolViewModel.clearMetadataCache()
    }
}

