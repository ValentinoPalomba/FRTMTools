import SwiftUI

struct AndroidPermissionsPopover: View {
    let permissions: [String]

    private var orderedPermissions: [String] {
        permissions.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.red)
                    .font(.title2)

                Text("Permissions")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Text("\(orderedPermissions.count)")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(orderedPermissions.enumerated()), id: \.offset) { index, permission in
                        AndroidPermissionRow(permission: permission)

                        if index < orderedPermissions.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 340, minHeight: 340)
    }
}

private struct AndroidPermissionRow: View {
    let permission: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: permission))
                .foregroundColor(color(for: permission))
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

                if let description = description(for: permission) {
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
        return name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func icon(for permission: String) -> String {
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

    private func color(for permission: String) -> Color {
        let lower = permission.lowercased()

        if lower.contains("camera") || lower.contains("location") ||
            lower.contains("microphone") || lower.contains("record_audio") ||
            lower.contains("contacts") || lower.contains("phone") ||
            lower.contains("sms") || lower.contains("call_log") {
            return .red
        } else if lower.contains("storage") || lower.contains("write_external") ||
                    lower.contains("read_external") {
            return .orange
        } else {
            return .gray
        }
    }

    private func description(for permission: String) -> String? {
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

struct AndroidCategoryInfo {
    let name: String
    let iconName: String
    let color: Color
    let description: String
    let examples: [String]?
    let impact: String?

    static func info(for rawName: String) -> AndroidCategoryInfo? {
        let normalized = rawName.lowercased()

        switch normalized {
        case "dex", "dex files":
            return AndroidCategoryInfo(
                name: "DEX Files",
                iconName: "cpu",
                color: .orange,
                description: "DEX (Dalvik Executable) files contain compiled Java/Kotlin code that runs on Android's runtime. These are the core executable files of your Android app.",
                examples: [
                    "classes.dex - Main application code",
                    "classes2.dex - Additional code (multidex)",
                    "classes3.dex - More code if needed"
                ],
                impact: "Large DEX files increase app size and can slow startup time. Enable R8/ProGuard to reduce size and improve performance."
            )
        case "native libraries", "native libs":
            return AndroidCategoryInfo(
                name: "Native Libraries",
                iconName: "gearshape.2.fill",
                color: .blue,
                description: "Native libraries (.so files) are compiled C/C++ code that provides platform-specific functionality and performance-critical operations. They are organized by CPU architecture (ABI).",
                examples: [
                    "lib/arm64-v8a/ - 64-bit ARM libraries",
                    "lib/armeabi-v7a/ - 32-bit ARM libraries",
                    "lib/x86/ and lib/x86_64/ - Intel builds"
                ],
                impact: "Including multiple ABIs increases APK size. Consider using App Bundles to deliver architecture-specific APKs and reduce download size."
            )
        case "resources":
            return AndroidCategoryInfo(
                name: "Resources",
                iconName: "photo.on.rectangle.angled",
                color: .green,
                description: "Resources include UI layouts, images, strings, styles, and other assets compiled by Android's resource system. These are processed and optimized at build time.",
                examples: [
                    "res/drawable/ - Images and graphics",
                    "res/layout/ - UI layouts (XML)",
                    "res/values/ - Strings, colors, dimensions",
                    "resources.arsc - Compiled resource table"
                ],
                impact: "Unoptimized resources are a common source of bloat. Use WebP for images, remove unused resources, and ensure proper density variants."
            )
        case "assets":
            return AndroidCategoryInfo(
                name: "Assets",
                iconName: "doc.on.doc",
                color: .purple,
                description: "Assets are raw files packaged with your APK without processing. They can include fonts, configuration files, databases, or any other data your app needs.",
                examples: [
                    "assets/fonts/ - Custom fonts",
                    "assets/config/ - Configuration files",
                    "assets/data/ - Databases or data files"
                ],
                impact: "Assets are not compressed or optimized. Consider compressing large files and removing unnecessary data to reduce APK size."
            )
        case "manifest & metadata", "manifest", "meta":
            return AndroidCategoryInfo(
                name: "Manifest & Metadata",
                iconName: "doc.badge.gearshape",
                color: .red,
                description: "This includes the AndroidManifest.xml (app configuration) and META-INF directory (signatures, certificates, and version information) used for app identification and security.",
                examples: [
                    "AndroidManifest.xml - App configuration",
                    "META-INF/MANIFEST.MF - Package manifest",
                    "META-INF/CERT.RSA - APK signature"
                ],
                impact: "These files are essential for app installation and security. They have minimal impact on size but are critical for proper app function."
            )
        case "other":
            return AndroidCategoryInfo(
                name: "Other",
                iconName: "folder",
                color: .gray,
                description: "Files that don't fit into standard Android categories. These might include configuration files, documentation, or app-specific data.",
                examples: nil,
                impact: nil
            )
        default:
            return nil
        }
    }
}

struct AndroidCategoryInfoPopover: View {
    let info: AndroidCategoryInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: info.iconName)
                    .foregroundColor(info.color)
                    .font(.title2)

                Text(info.name)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("What is this?")
                    .font(.headline)

                Text(info.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let examples = info.examples, !examples.isEmpty {
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

                if let impact = info.impact {
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
    }
}

struct AndroidFeaturesPopover: View {
    let requiredFeatures: [String]
    let optionalFeatures: [String]

    private var orderedRequired: [String] { requiredFeatures.sorted() }
    private var orderedOptional: [String] { optionalFeatures.sorted() }
    private var totalCount: Int { orderedRequired.count + orderedOptional.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "puzzlepiece.extension")
                    .foregroundColor(.accentColor)
                    .font(.title2)

                Text("Hardware Features")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Text("\(totalCount)")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if orderedRequired.isEmpty, orderedOptional.isEmpty {
                        Text("No feature declarations reported by aapt.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        if !orderedRequired.isEmpty {
                            featureSection(title: "Required", features: orderedRequired, isRequired: true)
                        }
                        if !orderedOptional.isEmpty {
                            featureSection(title: "Optional", features: orderedOptional, isRequired: false)
                        }
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func featureSection(title: String, features: [String], isRequired: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 8)

            ForEach(features, id: \.self) { feature in
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: icon(for: feature))
                        .foregroundColor(isRequired ? .red : .secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(isRequired ? "Required" : "Optional")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    private func icon(for feature: String) -> String {
        let lower = feature.lowercased()
        if lower.contains("camera") {
            return "camera"
        } else if lower.contains("location") || lower.contains("gps") {
            return "location"
        } else if lower.contains("bluetooth") {
            return "wave.3.right"
        } else if lower.contains("microphone") || lower.contains("audio") {
            return "mic"
        } else if lower.contains("sensors") || lower.contains("sensor") {
            return "dot.circle.and.hand.point.up.left.fill"
        } else if lower.contains("nfc") {
            return "wave.3.forward"
        } else if lower.contains("touchscreen") {
            return "hand.tap"
        } else if lower.contains("wifi") || lower.contains("network") {
            return "wifi"
        } else if lower.contains("telephony") || lower.contains("phone") {
            return "phone"
        } else if lower.contains("usb") {
            return "cable.connector"
        } else if lower.contains("vr") {
            return "visionpro"
        } else {
            return "puzzlepiece.fill"
        }
    }
}
