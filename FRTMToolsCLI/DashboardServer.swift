import Foundation

final class DashboardServer {
    struct Configuration: Sendable {
        let host: String
        let port: UInt16
        let openBrowser: Bool
        let dataDirectoryOverride: URL?
    }

    private let configuration: Configuration
    private let store: DashboardStore
    private var server: HTTPServer?

    init(configuration: Configuration) {
        self.configuration = configuration
        self.store = DashboardStore(dataDirectoryOverride: configuration.dataDirectoryOverride)
    }

    func start() async throws -> URL {
        try await store.ensureDirectories()
        let httpServer = try HTTPServer(host: configuration.host, port: configuration.port) { [weak self] request, body in
            guard let self else { return HTTPResponse.text("Server unavailable", statusCode: 500) }
            return await self.route(request: request, body: body)
        }
        try await httpServer.start()
        server = httpServer

        guard let port = httpServer.boundPort else {
            throw NSError(domain: "DashboardServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server did not bind to a port"])
        }
        let url = URL(string: "http://\(configuration.host):\(port)/")!
        if configuration.openBrowser {
            openBrowser(url)
        }
        return url
    }

    func stop() {
        server?.stop()
        server = nil
    }

    private func route(request: HTTPRequest, body: HTTPBody) async -> HTTPResponse {
        do {
            switch (request.method, request.path) {
            case ("GET", "/"):
                let runs = try await store.listRuns()
                return .html(DashboardPages.index(runs: runs))

            case ("GET", let path) where path.hasPrefix("/runs/"):
                let idString = String(path.dropFirst("/runs/".count))
                guard let id = UUID(uuidString: idString) else {
                    return .html(DashboardPages.errorPage(title: "Invalid run", message: "Malformed run id."), statusCode: 400)
                }
                let run = try await store.run(id: id)
                if run.status != .complete {
                    return .html(DashboardPages.runStatus(run: run))
                }
                return try await runDashboardHTML(for: run)

            case ("GET", "/compare"):
                guard
                    let beforeRaw = request.query["before"],
                    let afterRaw = request.query["after"],
                    let beforeId = UUID(uuidString: beforeRaw),
                    let afterId = UUID(uuidString: afterRaw)
                else {
                    return .html(DashboardPages.errorPage(title: "Compare", message: "Expected 'before' and 'after' run ids."), statusCode: 400)
                }
                return try await compareDashboardHTML(beforeId: beforeId, afterId: afterId)

            case ("GET", "/api/runs"):
                let runs = try await store.listRuns()
                return .json(encodeJSON(runs))

            case ("GET", let path) where path.hasPrefix("/api/runs/"):
                let suffix = String(path.dropFirst("/api/runs/".count))
                if suffix.hasSuffix("/delete") {
                    return .text("Not Found", statusCode: 404)
                }
                guard let id = UUID(uuidString: suffix) else {
                    return .text("Invalid id", statusCode: 400)
                }
                let run = try await store.run(id: id)
                return .json(encodeJSON(run))

            case ("POST", "/api/runs"):
                return try await handleCreateRun(request: request, body: body)

            case ("POST", let path) where path.hasPrefix("/api/runs/") && path.hasSuffix("/delete"):
                let idString = String(path.dropFirst("/api/runs/".count).dropLast("/delete".count))
                guard let id = UUID(uuidString: idString) else {
                    return .text("Invalid id", statusCode: 400)
                }
                try await store.deleteRun(id: id)
                return .json(encodeJSON(["ok": true]))

            default:
                return .text("Not Found", statusCode: 404)
            }
        } catch DashboardStoreError.notFound {
            return .text("Not Found", statusCode: 404)
        } catch {
            return .html(DashboardPages.errorPage(title: "Server Error", message: error.localizedDescription), statusCode: 500)
        }
    }

    private func handleCreateRun(request: HTTPRequest, body: HTTPBody) async throws -> HTTPResponse {
        let contentType = request.headers["content-type"]?.lowercased() ?? ""
        guard contentType.starts(with: "application/octet-stream") else {
            return .text("Expected application/octet-stream", statusCode: 415)
        }
        guard let filename = request.query["filename"], !filename.isEmpty else {
            return .text("Missing filename", statusCode: 400)
        }

        let ext = (filename as NSString).pathExtension.lowercased()
        let platform: DashboardPlatform
        switch ext {
        case "ipa", "app":
            platform = .ipa
        case "apk", "aab", "abb":
            platform = .apk
        default:
            return .text("Unsupported file extension: \(ext)", statusCode: 415)
        }

        let run = try await store.createRun(originalFileName: filename, platform: platform, fileExtension: ext)
        let destinationURL = await store.uploadedFileURL(for: run)

        switch body {
        case .file(let tempURL, _):
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        case .data(let data):
            try data.write(to: destinationURL, options: .atomic)
        case .empty:
            return .text("Missing body", statusCode: 400)
        }

        _ = try await store.updateRun(run.id) { $0.status = .queued }
        Task.detached { [store] in
            do {
                _ = try await store.updateRun(run.id) { run in
                    run.status = .running
                    run.errorMessage = nil
                }
                try await Self.performAnalysis(store: store, runId: run.id)
            } catch {
                _ = try? await store.updateRun(run.id) { run in
                    run.status = .failed
                    run.errorMessage = error.localizedDescription
                }
            }
        }

        let payload = encodeJSON(["id": run.id.uuidString])
        return .json(payload, statusCode: 202)
    }

    private static func performAnalysis(store: DashboardStore, runId: UUID) async throws {
        let run = try await store.run(id: runId)
        let inputURL = await store.uploadedFileURL(for: run)
        let analysisRelative = await store.analysisRelativePath(for: runId)
        let analysisURL = await store.analysisFileURL(for: runId)

        switch run.platform {
        case .ipa:
            let analyzer = IPAAnalyzer()
            guard let analysis = try await analyzer.analyze(at: inputURL) else {
                throw NSError(domain: "DashboardServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to analyze IPA."])
            }
            let data = try JSONEncoder().encode(analysis)
            try data.write(to: analysisURL, options: .atomic)
        case .apk:
            let analyzer = APKAnalyzer()
            guard let analysis = try await analyzer.analyze(at: inputURL) else {
                throw NSError(domain: "DashboardServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to analyze APK/AAB."])
            }
            let data = try JSONEncoder().encode(analysis)
            try data.write(to: analysisURL, options: .atomic)
        }

        _ = try await store.updateRun(runId) { run in
            run.status = .complete
            run.analysisRelativePath = analysisRelative
            run.errorMessage = nil
        }
    }

    private func runDashboardHTML(for run: DashboardRun) async throws -> HTTPResponse {
        guard let analysisURL = await store.analysisURL(for: run) else {
            return .html(DashboardPages.errorPage(title: "Missing analysis", message: "No analysis stored for this run."), statusCode: 500)
        }
        let data = try Data(contentsOf: analysisURL)
        let html: String
        switch run.platform {
        case .ipa:
            let analysis = try JSONDecoder().decode(IPAAnalysis.self, from: data)
            html = AppDashboardHTMLBuilder(platform: .ipa(analysis)).build()
        case .apk:
            let analysis = try JSONDecoder().decode(APKAnalysis.self, from: data)
            html = AppDashboardHTMLBuilder(platform: .apk(analysis)).build()
        }
        return .html(html)
    }

    private func compareDashboardHTML(beforeId: UUID, afterId: UUID) async throws -> HTTPResponse {
        let before = try await store.run(id: beforeId)
        let after = try await store.run(id: afterId)
        guard before.status == .complete, after.status == .complete else {
            return .html(DashboardPages.errorPage(title: "Compare", message: "Both runs must be complete before comparing."), statusCode: 409)
        }
        guard before.platform == after.platform else {
            return .html(DashboardPages.errorPage(title: "Compare", message: "Runs must be from the same platform (IPA vs IPA or APK/AAB)."), statusCode: 409)
        }
        guard let beforeURL = await store.analysisURL(for: before), let afterURL = await store.analysisURL(for: after) else {
            return .html(DashboardPages.errorPage(title: "Compare", message: "Missing analysis data."), statusCode: 500)
        }
        let beforeData = try Data(contentsOf: beforeURL)
        let afterData = try Data(contentsOf: afterURL)

        let html: String
        switch before.platform {
        case .ipa:
            let beforeAnalysis = try JSONDecoder().decode(IPAAnalysis.self, from: beforeData)
            let afterAnalysis = try JSONDecoder().decode(IPAAnalysis.self, from: afterData)
            html = ComparisonDashboardHTMLBuilder(platform: .ipa(beforeAnalysis, afterAnalysis)).build()
        case .apk:
            let beforeAnalysis = try JSONDecoder().decode(APKAnalysis.self, from: beforeData)
            let afterAnalysis = try JSONDecoder().decode(APKAnalysis.self, from: afterData)
            html = ComparisonDashboardHTMLBuilder(platform: .apk(beforeAnalysis, afterAnalysis)).build()
        }
        return .html(html)
    }

    private func openBrowser(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try? process.run()
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }
}
