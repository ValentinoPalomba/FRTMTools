import SwiftUI

@MainActor
final class BuildLogViewModel: ObservableObject {
    struct BuildReportEntry: Identifiable, Hashable {
        let id: UUID
        let name: String
        let createdAt: Date
        let report: BuildReport
    }

    enum BuildLogError: LocalizedError, Identifiable {
        case parsingFailed(String)
        case invalidInput(String)

        var id: String { errorDescription ?? "BuildLogError" }

        var errorDescription: String? {
            switch self {
            case .parsingFailed(let message):
                return message
            case .invalidInput(let message):
                return message
            }
        }
    }

    @Published var reports: [BuildReportEntry] = []
    @Published var selectedReportID: UUID?
    @Published var isLoading = false
    @Published var error: BuildLogError?

    private let runner = XCLogParserRunner()
    private let builder = BuildModelBuilder()
    private let insightEngine = BuildInsightEngine()
    private let reportBuilder = BuildReportBuilder()

    private static func makeAIFixGenerator() -> AIFixGenerator {
    #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return AppleFoundationModelsFixGenerator()
        }
    #endif
        return NoopAIFixGenerator()
    }


    var selectedReport: BuildReportEntry? {
        guard let selectedReportID else { return reports.first }
        return reports.first { $0.id == selectedReportID }
    }

    func importBuildInput() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["xcactivitylog", "xcodeproj", "xcworkspace"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            analyzeBuildInput(at: url)
        }
    }

    func analyzeBuildInput(at url: URL) {
        isLoading = true
        error = nil

        Task {
            do {
                let aiFixGenerator = Self.makeAIFixGenerator()
                let options = try resolveOptions(for: url)
                let result = try await runner.parseJSON(options: options)
                let graph = builder.buildGraph(from: result.steps)
                let insights = insightEngine.generateInsights(from: graph)
                var report = reportBuilder.buildReport(from: graph, insights: insights)
                if aiFixGenerator.isAvailable {
                    report = report.withAIFixes("Generating AI recommendations...")
                }

                let entry = BuildReportEntry(
                    id: UUID(),
                    name: url.lastPathComponent,
                    createdAt: Date(),
                    report: report
                )

                reports.insert(entry, at: 0)
                selectedReportID = entry.id
                isLoading = false

                if aiFixGenerator.isAvailable {
                    let currentEntryID = entry.id
                    Task { @MainActor in
                        let aiFixes = await aiFixGenerator.generateFixes(from: report)
                        if let index = reports.firstIndex(where: { $0.id == currentEntryID }) {
                            let fallback = "AI recommendations unavailable."
                            let updatedReport = reports[index].report.withAIFixes(aiFixes ?? fallback)
                            let updatedEntry = BuildReportEntry(
                                id: reports[index].id,
                                name: reports[index].name,
                                createdAt: reports[index].createdAt,
                                report: updatedReport
                            )
                            reports[index] = updatedEntry
                        }
                    }
                }

            } catch {
                isLoading = false
                if let buildError = error as? BuildLogError {
                    self.error = buildError
                } else {
                    self.error = .parsingFailed(error.localizedDescription)
                }
            }
        }
    }

    func deleteReport(_ entry: BuildReportEntry) {
        reports.removeAll { $0.id == entry.id }
        if selectedReportID == entry.id {
            selectedReportID = reports.first?.id
        }
    }

    private func resolveOptions(for url: URL) throws -> XCLogParserOptions {
        let ext = url.pathExtension.lowercased()
        if ext == "xcactivitylog" {
            return XCLogParserOptions(fileURL: url)
        }
        if ext == "xcworkspace" {
            return XCLogParserOptions(workspaceURL: url)
        }
        if ext == "xcodeproj" {
            return XCLogParserOptions(xcodeprojURL: url)
        }
        if url.hasDirectoryPath {
            return try resolveProjectFromFolder(url)
        }
        throw BuildLogError.invalidInput("Unsupported input. Select an .xcactivitylog, .xcworkspace, .xcodeproj, or a folder containing one.")
    }

    private func resolveProjectFromFolder(_ folderURL: URL) throws -> XCLogParserOptions {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        let workspaces = contents.filter { $0.pathExtension == "xcworkspace" }
        let projects = contents.filter { $0.pathExtension == "xcodeproj" }

        if workspaces.count == 1 {
            return XCLogParserOptions(workspaceURL: workspaces[0])
        }
        if workspaces.count > 1 {
            throw BuildLogError.invalidInput("Multiple .xcworkspace files found in \(folderURL.lastPathComponent). Please select the workspace directly.")
        }
        if projects.count == 1 {
            return XCLogParserOptions(xcodeprojURL: projects[0])
        }
        if projects.count > 1 {
            throw BuildLogError.invalidInput("Multiple .xcodeproj files found in \(folderURL.lastPathComponent). Please select the project directly.")
        }
        throw BuildLogError.invalidInput("No .xcworkspace or .xcodeproj found in \(folderURL.lastPathComponent).")
    }
}
