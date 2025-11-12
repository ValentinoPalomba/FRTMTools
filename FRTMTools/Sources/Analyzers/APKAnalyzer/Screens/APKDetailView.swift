//
//  APKDetailView.swift
//  FRTMTools
//
//

import SwiftUI
import Charts

/// Detailed view of an APK analysis
struct APKDetailView: View {
    @StateObject private var viewModel: APKDetailViewModel
    @State private var showPermissionsPopover = false
    @State private var selectedCategoryForInfo: String?

    init(analysis: APKAnalysis) {
        _viewModel = StateObject(wrappedValue: APKDetailViewModel(analysis: analysis))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                summarySection
                chartSection
                tipsSection
                fileHierarchySection
            }
            .padding()
        }
        .navigationTitle(viewModel.analysis.packageName ?? "APK Analysis")
        .toolbar {
            ToolbarItem {
                HStack {
                    if let minSdk = viewModel.analysis.minSdkVersion {
                        Text("Min SDK: \(minSdk)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let targetSdk = viewModel.analysis.targetSdkVersion {
                        Text("Target SDK: \(targetSdk)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: 20) {
            // App icon
            if let image = viewModel.analysis.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(16)
                    .shadow(radius: 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let appLabel = viewModel.analysis.appLabel {
                    Text(appLabel)
                        .font(.title)
                        .fontWeight(.bold)

                    Text(viewModel.analysis.packageName ?? "Unknown Package")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text(viewModel.analysis.packageName ?? "Unknown Package")
                        .font(.title)
                        .fontWeight(.bold)
                }

                if let version = viewModel.analysis.versionName {
                    Text("Version \(version)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                if let versionCode = viewModel.analysis.versionCode {
                    Text("Build \(versionCode)")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    private var summarySection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            SummaryCard(
                title: "Total Size",
                value: formatSize(viewModel.analysis.totalSize),
                icon: "doc.fill",
                color: .blue
            )

            if let installedSize = viewModel.analysis.installedSize {
                SummaryCard(
                    title: "Installed Size",
                    value: "\(installedSize.total) MB",
                    icon: "internaldrive.fill",
                    color: .green
                )
            }

            SummaryCard(
                title: "Files",
                value: "\(viewModel.fileCount)",
                icon: "doc.on.doc.fill",
                color: .orange
            )

            if let dexCount = viewModel.analysis.dexFileCount {
                SummaryCard(
                    title: "DEX Files",
                    value: "\(dexCount)",
                    icon: "cpu.fill",
                    color: .purple
                )
            }

            if viewModel.abiInfo.count > 0 {
                SummaryCard(
                    title: "ABIs",
                    value: "\(viewModel.abiInfo.count)",
                    subtitle: viewModel.abiDescription,
                    icon: "gearshape.2.fill",
                    color: .indigo
                )
            }

            if let permissions = viewModel.analysis.permissions {
                Button {
                    showPermissionsPopover.toggle()
                } label: {
                    SummaryCard(
                        title: "Permissions",
                        value: "\(permissions.count)",
                        icon: "lock.shield.fill",
                        color: .red
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPermissionsPopover) {
                    PermissionsPopoverView(permissions: permissions)
                }
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Size Distribution")
                .font(.title2)
                .fontWeight(.semibold)

            let categories = viewModel.filteredCategories

            if !categories.isEmpty {
                Chart(categories) { category in
                    SectorMark(
                        angle: .value("Size", category.totalSize),
                        innerRadius: .ratio(0.5),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(category.color)
                    .opacity(viewModel.selectedCategory == category.name ? 1.0 : 0.8)
                }
                .frame(height: 300)
                .chartLegend(position: .trailing)
                .chartAngleSelection(value: $viewModel.selectedCategory)

                // Category breakdown
                VStack(spacing: 8) {
                    ForEach(categories) { category in
                        HStack {
                            Circle()
                                .fill(category.color)
                                .frame(width: 12, height: 12)

                            Text(category.name)
                                .font(.body)

                            Spacer()

                            Text(formatSize(category.totalSize))
                                .font(.body)
                                .foregroundColor(.secondary)

                            Text(String(format: "%.1f%%", percentage(category.totalSize)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    private var tipsSection: some View {
        let tips = viewModel.tips

        return Group {
            if !tips.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Optimization Tips")
                        .font(.title2)
                        .fontWeight(.semibold)

                    ForEach(tips) { tip in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: iconForTipCategory(tip.category))
                                .foregroundColor(colorForTipCategory(tip.category))
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(tip.category.rawValue)
                                    .font(.caption)
                                    .foregroundColor(colorForTipCategory(tip.category))
                                    .fontWeight(.semibold)

                                Text(tip.text)
                                    .font(.body)
                                    .foregroundColor(.primary)
                            }

                            Spacer()
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private var fileHierarchySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("File Hierarchy")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                TextField("Search", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }

            let categories = viewModel.filteredCategories

            ForEach(categories) { category in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { viewModel.isExpanded(category.name) },
                        set: { _ in viewModel.toggleSection(category.name) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(category.items) { file in
                            FileTreeView(file: file)
                        }
                    }
                    .padding(.leading)
                } label: {
                    HStack {
                        Circle()
                            .fill(category.color)
                            .frame(width: 12, height: 12)

                        Text(category.name)
                            .font(.headline)

                        Button {
                            selectedCategoryForInfo = category.name
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: Binding(
                            get: { selectedCategoryForInfo == category.name },
                            set: { if !$0 { selectedCategoryForInfo = nil } }
                        )) {
                            CategoryInfoPopoverView(categoryName: category.name)
                        }

                        Spacer()

                        Text(formatSize(category.totalSize))
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func percentage(_ size: Int64) -> Double {
        let total = Double(viewModel.analysis.totalSize)
        return total > 0 ? (Double(size) / total) * 100 : 0
    }

    private func iconForTipCategory(_ category: TipCategory) -> String {
        switch category {
        case .size:
            return "arrow.down.circle.fill"
        case .performance:
            return "speedometer"
        case .security:
            return "lock.shield.fill"
        case .compatibility:
            return "checkmark.shield.fill"
        case .optimization:
            return "wand.and.stars"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private func colorForTipCategory(_ category: TipCategory) -> Color {
        switch category {
        case .size:
            return .blue
        case .performance:
            return .green
        case .security:
            return .red
        case .compatibility:
            return .orange
        case .optimization:
            return .purple
        case .warning:
            return .yellow
        case .info:
            return .gray
        }
    }
}

/// Popover view showing permission details
struct PermissionsPopoverView: View {
    let permissions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.red)
                    .font(.title2)

                Text("Permissions")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Text("\(permissions.count)")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Permissions list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(permissions, id: \.self) { permission in
                        PermissionRow(permission: permission)

                        if permission != permissions.last {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
    }
}

/// Row displaying a single permission with description
struct PermissionRow: View {
    let permission: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconForPermission(permission))
                .foregroundColor(colorForPermission(permission))
                .frame(width: 20)
                .font(.body)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(for: permission))
                    .font(.body)
                    .fontWeight(.medium)

                Text(permission)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let description = descriptionForPermission(permission) {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func displayName(for permission: String) -> String {
        let name = permission.components(separatedBy: ".").last ?? permission
        return name.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func iconForPermission(_ permission: String) -> String {
        let lower = permission.lowercased()

        if lower.contains("camera") {
            return "camera.fill"
        } else if lower.contains("location") || lower.contains("gps") {
            return "location.fill"
        } else if lower.contains("microphone") || lower.contains("record_audio") {
            return "mic.fill"
        } else if lower.contains("contacts") {
            return "person.crop.circle.fill"
        } else if lower.contains("storage") || lower.contains("write_external") || lower.contains("read_external") {
            return "externaldrive.fill"
        } else if lower.contains("phone") || lower.contains("call") {
            return "phone.fill"
        } else if lower.contains("sms") || lower.contains("message") {
            return "message.fill"
        } else if lower.contains("calendar") {
            return "calendar"
        } else if lower.contains("internet") || lower.contains("network") {
            return "network"
        } else if lower.contains("bluetooth") {
            return "wave.3.right"
        } else if lower.contains("nfc") {
            return "wave.3.forward"
        } else if lower.contains("account") {
            return "person.crop.circle"
        } else {
            return "checkmark.shield.fill"
        }
    }

    private func colorForPermission(_ permission: String) -> Color {
        let lower = permission.lowercased()

        // Dangerous permissions in red
        if lower.contains("camera") || lower.contains("location") ||
           lower.contains("microphone") || lower.contains("record_audio") ||
           lower.contains("contacts") || lower.contains("phone") ||
           lower.contains("sms") || lower.contains("call_log") {
            return .red
        }
        // Storage permissions in orange
        else if lower.contains("storage") || lower.contains("write_external") ||
                lower.contains("read_external") {
            return .orange
        }
        // Normal permissions in gray
        else {
            return .gray
        }
    }

    private func descriptionForPermission(_ permission: String) -> String? {
        let lower = permission.lowercased()

        if lower.contains("internet") {
            return "Allows the app to access the Internet"
        } else if lower.contains("access_network_state") {
            return "Allows the app to view information about network connections"
        } else if lower.contains("access_wifi_state") {
            return "Allows the app to view information about Wi-Fi networks"
        } else if lower.contains("change_network_state") {
            return "Allows the app to change network connectivity state"
        } else if lower.contains("camera") {
            return "Allows the app to take pictures and videos with the camera"
        } else if lower.contains("access_fine_location") {
            return "Allows the app to get your precise location using GPS"
        } else if lower.contains("access_coarse_location") {
            return "Allows the app to get your approximate location"
        } else if lower.contains("record_audio") {
            return "Allows the app to record audio with the microphone"
        } else if lower.contains("read_contacts") {
            return "Allows the app to read your contacts"
        } else if lower.contains("write_contacts") {
            return "Allows the app to modify your contacts"
        } else if lower.contains("read_external_storage") {
            return "Allows the app to read from external storage"
        } else if lower.contains("write_external_storage") {
            return "Allows the app to write to external storage"
        } else if lower.contains("read_phone_state") {
            return "Allows the app to read phone status and identity"
        } else if lower.contains("call_phone") {
            return "Allows the app to initiate a phone call"
        } else if lower.contains("read_sms") {
            return "Allows the app to read SMS messages"
        } else if lower.contains("send_sms") {
            return "Allows the app to send SMS messages"
        } else if lower.contains("receive_boot_completed") {
            return "Allows the app to start when the device boots"
        } else if lower.contains("wake_lock") {
            return "Allows the app to prevent the device from sleeping"
        } else if lower.contains("vibrate") {
            return "Allows the app to control the vibrator"
        } else if lower.contains("bluetooth") {
            return "Allows the app to connect to paired Bluetooth devices"
        } else if lower.contains("nfc") {
            return "Allows the app to communicate with NFC tags and devices"
        } else if lower.contains("get_accounts") {
            return "Allows the app to get the list of accounts on the device"
        } else if lower.contains("use_credentials") {
            return "Allows the app to request authentication tokens"
        } else if lower.contains("manage_accounts") {
            return "Allows the app to perform operations like adding and removing accounts"
        } else if lower.contains("c2dm") || lower.contains("gcm") {
            return "Allows the app to receive push notifications"
        } else {
            return nil
        }
    }
}

/// Popover view showing category information
struct CategoryInfoPopoverView: View {
    let categoryName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: iconForCategory(categoryName))
                    .foregroundColor(colorForCategory(categoryName))
                    .font(.title2)

                Text(categoryName)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Divider()

            // Description
            VStack(alignment: .leading, spacing: 8) {
                Text("What is this?")
                    .font(.headline)

                Text(descriptionForCategory(categoryName))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let examples = examplesForCategory(categoryName) {
                    Text("Contains:")
                        .font(.headline)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(examples, id: \.self) { example in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(example)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if let impact = impactForCategory(categoryName) {
                    Text("Impact:")
                        .font(.headline)
                        .padding(.top, 4)

                    Text(impact)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func iconForCategory(_ name: String) -> String {
        switch name {
        case "DEX":
            return "cpu"
        case "Native Libraries":
            return "gearshape.2.fill"
        case "Resources":
            return "photo.on.rectangle.angled"
        case "Assets":
            return "doc.on.doc"
        case "Manifest & Metadata":
            return "doc.badge.gearshape"
        case "Other":
            return "folder"
        default:
            return "folder.fill"
        }
    }

    private func colorForCategory(_ name: String) -> Color {
        switch name {
        case "DEX":
            return .orange
        case "Native Libraries":
            return .blue
        case "Resources":
            return .yellow
        case "Assets":
            return .purple
        case "Manifest & Metadata":
            return .red
        case "Other":
            return .gray
        default:
            return .gray
        }
    }

    private func descriptionForCategory(_ name: String) -> String {
        switch name {
        case "DEX":
            return "DEX (Dalvik Executable) files contain compiled Java/Kotlin code that runs on Android's runtime. These are the core executable files of your Android app."
        case "Native Libraries":
            return "Native libraries (.so files) are compiled C/C++ code that provides platform-specific functionality and performance-critical operations. They are organized by CPU architecture (ABI)."
        case "Resources":
            return "Resources include UI layouts, images, strings, styles, and other assets compiled by Android's resource system. These are processed and optimized at build time."
        case "Assets":
            return "Assets are raw files that are packaged with your APK without processing. They can include fonts, configuration files, databases, or any other data your app needs."
        case "Manifest & Metadata":
            return "This includes the AndroidManifest.xml (app configuration) and META-INF directory (signatures, certificates, and version information) used for app identification and security."
        case "Other":
            return "Files that don't fit into standard Android categories. These might include configuration files, documentation, or app-specific data."
        default:
            return "This category groups related files in your APK."
        }
    }

    private func examplesForCategory(_ name: String) -> [String]? {
        switch name {
        case "DEX":
            return [
                "classes.dex - Main application code",
                "classes2.dex - Additional code (multidex)",
                "classes3.dex - More code if needed"
            ]
        case "Native Libraries":
            return [
                "lib/arm64-v8a/ - 64-bit ARM libraries",
                "lib/armeabi-v7a/ - 32-bit ARM libraries",
                "lib/x86/ - Intel 32-bit libraries",
                "lib/x86_64/ - Intel 64-bit libraries"
            ]
        case "Resources":
            return [
                "res/drawable/ - Images and graphics",
                "res/layout/ - UI layouts (XML)",
                "res/values/ - Strings, colors, dimensions",
                "resources.arsc - Compiled resource table"
            ]
        case "Assets":
            return [
                "assets/fonts/ - Custom fonts",
                "assets/config/ - Configuration files",
                "assets/data/ - Databases or data files"
            ]
        case "Manifest & Metadata":
            return [
                "AndroidManifest.xml - App configuration",
                "META-INF/MANIFEST.MF - Package manifest",
                "META-INF/CERT.RSA - APK signature"
            ]
        default:
            return nil
        }
    }

    private func impactForCategory(_ name: String) -> String? {
        switch name {
        case "DEX":
            return "Large DEX files increase app size and can slow startup time. Enable R8/ProGuard to reduce size and improve performance."
        case "Native Libraries":
            return "Including multiple ABIs increases APK size. Consider using App Bundles to deliver architecture-specific APKs and reduce download size by 40-60%."
        case "Resources":
            return "Unoptimized resources are a common source of bloat. Use WebP for images, remove unused resources, and ensure proper density variants."
        case "Assets":
            return "Assets are not compressed or optimized. Consider compressing large files and removing unnecessary data to reduce APK size."
        case "Manifest & Metadata":
            return "These files are essential for app installation and security. They have minimal impact on size but are critical for proper app function."
        default:
            return nil
        }
    }
}
