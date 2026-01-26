import SwiftUI
import UniformTypeIdentifiers

struct StartupTimeAnalysisView: View {
    @Bindable var viewModel: IPAViewModel
    let analysis: IPAAnalysis

    @State private var showingFilePicker = false
    @State private var selectedLogFiles: [URL] = []
    @State private var showingDeviceSelector = false
    @State private var deviceUDID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("🚀 Startup Time")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.isStartupTimeLoading {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle())
                    Text(viewModel.startupTimeProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else if let startupTime = analysis.startupTime {
                VStack(alignment: .leading, spacing: 10) {
                    // Average startup time
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(startupTime.formattedAverage)
                            .font(.title)
                            .bold()
                            .foregroundStyle(.primary)
                        Text("avg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Min/Max if available
                    if let minTime = startupTime.minTime, let maxTime = startupTime.maxTime {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("• Min")
                                Spacer()
                                Text(formatTime(minTime))
                            }
                            HStack {
                                Text("• Max")
                                Spacer()
                                Text(formatTime(maxTime))
                            }
                            HStack {
                                Text("• Measurements")
                                Spacer()
                                Text("\(startupTime.measurements)")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    // Warnings
                    if !startupTime.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(startupTime.warnings.prefix(2), id: \.self) { warning in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("⚠️")
                                        .font(.caption2)
                                    Text(warning)
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    // Re-analyze buttons
                    HStack(spacing: 8) {
                        Button(action: {
                            showingDeviceSelector = true
                        }) {
                            Label("Install on Device", systemImage: "iphone.and.arrow.forward")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(action: {
                            showingFilePicker = true
                        }) {
                            Label("Import New Logs", systemImage: "doc.text")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Measure app startup time")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button(action: {
                            showingDeviceSelector = true
                        }) {
                            Label("Install on Device", systemImage: "iphone.and.arrow.forward")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button(action: {
                            showingFilePicker = true
                        }) {
                            Label("Import Logs", systemImage: "doc.text")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Text("Tip: Install on simulator/device to auto-measure, or import logs from Console.app")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .dsSurface(.surface, cornerRadius: 16, border: true, shadow: true)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.text, .plainText, .log],
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result)
        }
        .alert(item: $viewModel.startupTimeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showingDeviceSelector) {
            DeviceSelectionSheet(
                deviceUDID: $deviceUDID,
                onInstall: {
                    showingDeviceSelector = false
                    viewModel.installAndMeasureStartupTime(deviceUDID: deviceUDID, launchCount: 0)
                }
            )
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            selectedLogFiles = urls
            viewModel.analyzeStartupTime(from: urls)
        case .failure(let error):
            viewModel.startupTimeAlert = IPAViewModel.AlertContent(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private func formatTime(_ time: Double) -> String {
        if time < 1.0 {
            let ms = Int((time * 1000).rounded())
            return "\(ms) ms"
        }
        let rounded = (time * 100).rounded() / 100
        return "\(rounded) s"
    }
}

// MARK: - Device Selection Sheet

struct DeviceSelectionSheet: View {
    @Binding var deviceUDID: String
    let onInstall: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var availableSimulators: [(name: String, udid: String)] = []
    @State private var availableDevices: [(name: String, udid: String)] = []
    @State private var isLoadingSimulators = false
    @State private var isLoadingDevices = false
    @State private var deviceType: DeviceType = .simulator

    enum DeviceType {
        case simulator
        case physicalDevice
        case custom
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Install App on Device/Simulator")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                // Simulator/Device selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target Device")
                        .font(.headline)

                    Picker("Target", selection: $deviceType) {
                        Text("Simulator").tag(DeviceType.simulator)
                        Text("Physical Device").tag(DeviceType.physicalDevice)
                        Text("Custom UDID").tag(DeviceType.custom)
                    }
                    .pickerStyle(.segmented)

                    switch deviceType {
                    case .simulator:
                        if isLoadingSimulators {
                            ProgressView()
                                .progressViewStyle(.linear)
                        } else if availableSimulators.isEmpty {
                            Text("No simulators found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Simulator", selection: $deviceUDID) {
                                ForEach(availableSimulators, id: \.udid) { sim in
                                    Text(sim.name).tag(sim.udid)
                                }
                            }
                            .labelsHidden()
                        }

                    case .physicalDevice:
                        if isLoadingDevices {
                            ProgressView()
                                .progressViewStyle(.linear)
                        } else if availableDevices.isEmpty {
                            Text("No physical devices connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Device", selection: $deviceUDID) {
                                ForEach(availableDevices, id: \.udid) { device in
                                    Text(device.name).tag(device.udid)
                                }
                            }
                            .labelsHidden()
                        }

                    case .custom:
                        TextField("Device UDID", text: $deviceUDID)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Divider()

                if deviceType == .physicalDevice || deviceType == .custom {
                    Text("⚠️ Note: For physical devices, you'll need to manually launch the app and import logs.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.vertical, 8)
                } else {
                    Text("💡 Tip: After installation, manually launch the app and import logs to measure startup time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .padding()

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Install") {
                    onInstall()
                }
                .buttonStyle(.borderedProminent)
                .disabled(deviceUDID.isEmpty)
            }
            .padding(.bottom)
        }
        .frame(width: 500, height: 450)
        .onAppear {
            loadAvailableSimulators()
            loadAvailableDevices()
        }
    }

    private func loadAvailableSimulators() {
        isLoadingSimulators = true
        Task {
            do {
                let simulators = try await getAvailableSimulators()
                await MainActor.run {
                    self.availableSimulators = simulators
                    if let first = simulators.first {
                        self.deviceUDID = first.udid
                    }
                    self.isLoadingSimulators = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingSimulators = false
                }
            }
        }
    }

    private func getAvailableSimulators() async throws -> [(name: String, udid: String)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "available", "iPhone"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        var simulators: [(name: String, udid: String)] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Parse lines like: "iPhone 15 (12345678-1234-1234-1234-123456789012) (Shutdown)"
            let pattern = "^\\s+(.+?)\\s+\\(([0-9A-F-]+)\\)\\s+\\("
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let nameRange = Range(match.range(at: 1), in: line),
               let udidRange = Range(match.range(at: 2), in: line) {
                let name = String(line[nameRange])
                let udid = String(line[udidRange])
                simulators.append((name: name, udid: udid))
            }
        }

        return simulators
    }

    private func loadAvailableDevices() {
        isLoadingDevices = true
        Task {
            do {
                let devices = try await getAvailableDevices()
                await MainActor.run {
                    self.availableDevices = devices
                    // If simulator list is empty and we have devices, switch to physical device mode
                    if self.availableSimulators.isEmpty && !devices.isEmpty {
                        self.deviceType = .physicalDevice
                        if let first = devices.first {
                            self.deviceUDID = first.udid
                        }
                    }
                    self.isLoadingDevices = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingDevices = false
                }
            }
        }
    }

    private func getAvailableDevices() async throws -> [(name: String, udid: String)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["devicectl", "list", "devices"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        var devices: [(name: String, udid: String)] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Parse devicectl output - format varies but typically contains device name and UDID
            // Example: "iPhone (00008110-001234567890ABCD)"
            // or: "00008110-001234567890ABCD iPhone"

            // Try pattern 1: "Name (UDID)"
            let pattern1 = "(.+?)\\s+\\(([0-9A-F-]+)\\)"
            if let regex = try? NSRegularExpression(pattern: pattern1),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let nameRange = Range(match.range(at: 1), in: line),
               let udidRange = Range(match.range(at: 2), in: line) {
                let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
                let udid = String(line[udidRange])
                devices.append((name: name, udid: udid))
                continue
            }

            // Try pattern 2: "UDID Name"
            let pattern2 = "([0-9A-F-]{8,})\\s+(.+)"
            if let regex = try? NSRegularExpression(pattern: pattern2),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let udidRange = Range(match.range(at: 1), in: line),
               let nameRange = Range(match.range(at: 2), in: line) {
                let udid = String(line[udidRange])
                let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
                // Only add if it looks like a valid device UDID (contains dashes)
                if udid.contains("-") {
                    devices.append((name: name, udid: udid))
                }
            }
        }

        return devices
    }
}

// Custom UTType for .log files
extension UTType {
    static var log: UTType {
        UTType(filenameExtension: "log") ?? .plainText
    }
}
