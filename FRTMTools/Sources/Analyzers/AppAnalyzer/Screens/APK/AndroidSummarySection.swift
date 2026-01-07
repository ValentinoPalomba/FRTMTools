import SwiftUI

struct AndroidSummarySection: View {
    let analysis: APKAnalysis
    let apkViewModel: APKDetailViewModel?
    let byteFormatter: ByteCountFormatter

    @State private var showPermissionsDetails = false
    @State private var showImageExtractionOptions = false
    @State private var extractionInProgress = false
    @State private var showExtractionAlert = false
    @State private var extractionAlertMessage = ""
    @State private var showCertificateInfo = false
    @State private var showFeatureDetails = false

    var body: some View {
        Group {
            if let installCard = installedSizeCardContent() {
                SummaryCard(
                    title: "📲 Installed Size",
                    value: installCard.value,
                    subtitle: installCard.subtitle
                )
            }

            if let downloadCard = downloadSizeCardContent() {
                SummaryCard(
                    title: "⬇️ Download Size",
                    value: downloadCard.value,
                    subtitle: downloadCard.subtitle,
                    backgroundColor: downloadCard.backgroundColor
                )
            }

            if let minSDK = analysis.minSDK, let targetSDK = analysis.targetSDK {
                SummaryCard(
                    title: "🎯 SDK Targets",
                    value: "\(minSDK) ▸ \(targetSDK)",
                    subtitle: "Min ▸ Target"
                )
            }

            let stats = androidStats()
            SummaryCard(
                title: "📚 Dex vs Native",
                value: "\(stats.dexCount) dex / \(stats.nativeLibCount) so",
                subtitle: stats.abiSubtitle
            )

            permissionsCard(stats: stats)
            certificateCard()
            launchActivityCard()
            localesCard()
            screenSupportCard()
            featureCard()
            imageExtractionCard()
        }
    }

    @ViewBuilder
    private func permissionsCard(stats: AndroidStats) -> some View {
        if analysis.permissions.isEmpty {
            SummaryCard(
                title: "🔐 Permissions",
                value: "\(analysis.permissions.count)",
                subtitle: "\(stats.dangerousPermissions) dangerous"
            )
        } else {
            Button {
                showPermissionsDetails.toggle()
            } label: {
                SummaryCard(
                    title: "🔐 Permissions",
                    value: "\(analysis.permissions.count)",
                    subtitle: "\(stats.dangerousPermissions) dangerous"
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPermissionsDetails) {
                AndroidPermissionsPopover(permissions: analysis.permissions)
                    .frame(width: 420, height: 360)
            }
        }
    }

    @ViewBuilder
    private func certificateCard() -> some View {
        if let signatureInfo = analysis.signatureInfo {
            Button {
                showCertificateInfo.toggle()
            } label: {
                let certStatus = signatureInfo.isDebugSigned ? "Debug" :
                (signatureInfo.primaryCertificate?.isValid == true ? "Valid" : "Invalid")
                SummaryCard(
                    title: "🔐 Certificate",
                    value: certStatus,
                    subtitle: signatureInfo.signatureSchemesDescription
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCertificateInfo) {
                CertificateInfoPopover(signatureInfo: signatureInfo)
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func launchActivityCard() -> some View {
        if let launchable = analysis.launchableActivity {
            SummaryCard(
                title: "🚀 Launch Activity",
                value: analysis.launchableActivityLabel ?? shortActivityName(launchable),
                subtitle: launchable
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func localesCard() -> some View {
        if !analysis.supportedLocales.isEmpty {
            SummaryCard(
                title: "🌐 Locales",
                value: "\(analysis.supportedLocales.count)",
                subtitle: listPreviewDescription(for: analysis.supportedLocales, limit: 4)
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func screenSupportCard() -> some View {
        if shouldShowScreenCard(for: analysis) {
            SummaryCard(
                title: "🖥️ Screen Buckets",
                value: screenSupportValue(for: analysis),
                subtitle: screenSupportSubtitle(for: analysis)
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func featureCard() -> some View {
        if !analysis.requiredFeatures.isEmpty || !analysis.optionalFeatures.isEmpty {
            Button {
                showFeatureDetails.toggle()
            } label: {
                SummaryCard(
                    title: "🧩 Features",
                    value: "\(analysis.requiredFeatures.count) required",
                    subtitle: analysis.optionalFeatures.isEmpty
                        ? "Tap to inspect hardware features"
                        : "\(analysis.optionalFeatures.count) optional · Tap to inspect"
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFeatureDetails) {
                AndroidFeaturesPopover(
                    requiredFeatures: analysis.requiredFeatures,
                    optionalFeatures: analysis.optionalFeatures
                )
                .frame(width: 360, height: 320)
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func imageExtractionCard() -> some View {
        if let apkViewModel {
            Button {
                showImageExtractionOptions.toggle()
            } label: {
                SummaryCard(
                    title: "🖼️ Images",
                    value: "\(apkViewModel.imageCount)",
                    subtitle: extractionInProgress ? "Extracting..." : "Tap to extract"
                )
            }
            .buttonStyle(.plain)
            .disabled(extractionInProgress)
            .confirmationDialog("Extract Images", isPresented: $showImageExtractionOptions) {
                Button("Extract with folder structure") {
                    extractImages(from: apkViewModel, preserveStructure: true)
                }
                Button("Extract all to one folder") {
                    extractImages(from: apkViewModel, preserveStructure: false)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose how to extract \(apkViewModel.imageCount) images from the APK")
            }
            .alert("Image Extraction", isPresented: $showExtractionAlert) {
                Button("OK") { }
            } message: {
                Text(extractionAlertMessage)
            }
        } else {
            EmptyView()
        }
    }

    private func installedSizeCardContent() -> (value: String, subtitle: String)? {
        if let installBytes = analysis.bundletoolInstallSizeBytes {
            let value = byteFormatter.string(fromByteCount: installBytes)
            let subtitle = "bundletool install estimate"
            return (value, subtitle)
        }

        if let metrics = analysis.installedSize {
            return (
                value: "\(metrics.total) MB",
                subtitle: installedSizeBreakdownSubtitle(for: metrics)
            )
        }

        return nil
    }

    private func downloadSizeCardContent() -> (value: String, subtitle: String, backgroundColor: Color?)? {
        guard let downloadBytes = analysis.bundletoolDownloadSizeBytes else {
            return nil
        }
        let value = byteFormatter.string(fromByteCount: downloadBytes)
        let subtitle: String
        if let installBytes = analysis.bundletoolInstallSizeBytes {
            subtitle = "Install \(byteFormatter.string(fromByteCount: installBytes))"
        } else {
            subtitle = "bundletool download estimate"
        }

        let downloadMegabytes = Double(downloadBytes) / 1_048_576.0
        let backgroundColor: Color?
        if downloadMegabytes >= 200 {
            backgroundColor = Color.red.opacity(0.2)
        } else if downloadMegabytes >= 180 {
            backgroundColor = Color.orange.opacity(0.2)
        } else {
            backgroundColor = nil
        }

        return (value, subtitle, backgroundColor)
    }

    private func androidStats() -> AndroidStats {
        let files = analysis.rootFile.flattened(includeDirectories: false)
        let dexFiles = files.filter { $0.name.lowercased().hasSuffix(".dex") }
        let nativeLibs = files.filter { $0.name.lowercased().hasSuffix(".so") }
        let largestDex = dexFiles.map(\.size).max() ?? 0
        let dangerousPermissions = analysis.permissions.filter { perm in
            AndroidPermissionCatalog.dangerousPermissions.contains(perm)
        }.count
        let largestDexLabel = ByteCountFormatter.string(fromByteCount: largestDex, countStyle: .file)
        let abiSubtitle: String
        if analysis.supportedABIs.isEmpty {
            abiSubtitle = "Largest dex: \(largestDexLabel)"
        } else {
            abiSubtitle = "ABIs: \(analysis.supportedABIs.joined(separator: ", ")) · Dex max \(largestDexLabel)"
        }
        return AndroidStats(
            dexCount: dexFiles.count,
            nativeLibCount: nativeLibs.count,
            dangerousPermissions: dangerousPermissions,
            abiSubtitle: abiSubtitle
        )
    }

    private func extractImages(from apkViewModel: APKDetailViewModel, preserveStructure: Bool) {
        extractionInProgress = true

        Task { @MainActor in
            if let result = apkViewModel.extractImages(preserveStructure: preserveStructure) {
                extractionInProgress = false

                if result.errors.isEmpty {
                    extractionAlertMessage = "Successfully extracted \(result.extractedImages) of \(result.totalImages) images!"
                    showExtractionAlert = true
                    apkViewModel.revealExtractedImages(result)
                } else {
                    extractionAlertMessage = "Extracted \(result.extractedImages) of \(result.totalImages) images with \(result.errors.count) errors."
                    showExtractionAlert = true
                }
            } else {
                extractionInProgress = false
            }
        }
    }

    private struct AndroidStats {
        let dexCount: Int
        let nativeLibCount: Int
        let dangerousPermissions: Int
        let abiSubtitle: String
    }
}

func installedSizeBreakdownSubtitle(for metrics: InstalledSizeMetrics) -> String {
    var parts: [String] = []
    if metrics.binaries > 0 {
        parts.append("Bin \(metrics.binaries) MB")
    }
    if metrics.frameworks > 0 {
        parts.append("Native \(metrics.frameworks) MB")
    }
    if metrics.resources > 0 {
        parts.append("Res \(metrics.resources) MB")
    }
    return parts.isEmpty ? "Estimated footprint" : parts.joined(separator: " · ")
}

func shortActivityName(_ name: String) -> String {
    name.components(separatedBy: ".").last ?? name
}

func listPreviewDescription(for values: [String], limit: Int = 3) -> String {
    guard !values.isEmpty else { return "—" }
    let displayed = values.prefix(limit)
    var summary = displayed.joined(separator: ", ")
    let remaining = values.count - displayed.count
    if remaining > 0 {
        summary += " +\(remaining)"
    }
    return summary
}

func shouldShowScreenCard(for analysis: APKAnalysis) -> Bool {
    !analysis.supportsScreens.isEmpty || !analysis.densities.isEmpty || analysis.supportsAnyDensity != nil
}

func screenSupportValue(for analysis: APKAnalysis) -> String {
    if !analysis.supportsScreens.isEmpty {
        return listPreviewDescription(for: analysis.supportsScreens, limit: 4)
    }
    if let supportsAnyDensity = analysis.supportsAnyDensity, supportsAnyDensity {
        return "Any density"
    }
    return "—"
}

func screenSupportSubtitle(for analysis: APKAnalysis) -> String? {
    var parts: [String] = []
    if !analysis.densities.isEmpty {
        parts.append("DPI \(listPreviewDescription(for: analysis.densities, limit: 4))")
    }
    if let supportsAnyDensity = analysis.supportsAnyDensity {
        parts.append(supportsAnyDensity ? "Runs on all densities" : "Limited densities")
    }
    guard !parts.isEmpty else { return nil }
    return parts.joined(separator: " · ")
}
