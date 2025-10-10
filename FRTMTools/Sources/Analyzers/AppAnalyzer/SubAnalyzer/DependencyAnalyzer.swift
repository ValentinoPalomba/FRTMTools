import Foundation
import CryptoKit

public class DependencyAnalyzer: @unchecked Sendable {

    // MARK: - State Management

    private struct AnalysisContext {
        var nodes: [String: DependencyNode] = [:]
        var edges: Set<EdgeKey> = []
        var visitedBinaries: Set<String> = []
        var canonicalNameIndex: [String: String] = [:] // canonicalName → nodeId

        struct EdgeKey: Hashable {
            let fromId: String
            let toId: String
            let type: DependencyEdgeType
        }

        mutating func addNode(_ node: DependencyNode, canonicalName: String? = nil) {
            nodes[node.id] = node
            if let canonical = canonicalName {
                canonicalNameIndex[canonical] = node.id
            }
        }

        mutating func addEdge(from: String, to: String, type: DependencyEdgeType) {
            edges.insert(EdgeKey(fromId: from, toId: to, type: type))
        }

        func toDependencyGraph() -> DependencyGraph {
            let nodeSet = Set(nodes.values)
            let edgeSet = Set(edges.map { DependencyEdge(fromId: $0.fromId, toId: $0.toId, type: $0.type) })
            return DependencyGraph(nodes: nodeSet, edges: edgeSet)
        }
    }

    // MARK: - Public API

    func analyzeDependencies(rootFile: FileInfo, layout: AppBundleLayout, plist: [String: Any]?) -> DependencyGraph {
        var context = AnalysisContext()

        // Nodo principale app
        let mainAppId = "main_app"
        let mainAppName = plist?["CFBundleExecutable"] as? String ?? layout.appURL.deletingPathExtension().lastPathComponent
        let mainAppNode = DependencyNode(
            id: mainAppId,
            name: mainAppName,
            type: .mainApp,
            path: layout.appURL.path,
            size: rootFile.size
        )
        context.addNode(mainAppNode)

        // Scansione binari IPA
        scanAllBinaries(in: rootFile, mainAppId: mainAppId, rootURL: layout.resourcesRoot, context: &context)

        // Analisi ricorsiva dipendenze binarie
        for node in context.nodes.values {
            analyzeBinaryDependencies(for: node, rootURL: layout.resourcesRoot, context: &context)
        }

        return context.toDependencyGraph()
    }

    // MARK: - Scan Binaries

    private func scanAllBinaries(in fileInfo: FileInfo, mainAppId: String, rootURL: URL, context: inout AnalysisContext) {
        guard let subItems = fileInfo.subItems else { return }

        for item in subItems {
            let relativePath = item.path ?? item.name

            switch item.type {
            case .framework:
                let canonical = canonicalName(from: relativePath)
                let nodeId = "framework_\(relativePath.stableHash)"
                if context.nodes[nodeId] == nil {
                    let node = DependencyNode(
                        id: nodeId,
                        name: item.name,
                        type: .framework,
                        path: relativePath,
                        size: item.size
                    )
                    context.addNode(node, canonicalName: canonical)
                    context.addEdge(from: mainAppId, to: nodeId, type: .embeds)
                }

            default:
                break
            }

            if item.name.hasSuffix(".appex") {
                let canonical = canonicalName(from: relativePath)
                let nodeId = "extension_\(relativePath.stableHash)"
                if context.nodes[nodeId] == nil {
                    let node = DependencyNode(
                        id: nodeId,
                        name: item.name,
                        type: .appExtension,
                        path: relativePath,
                        size: item.size
                    )
                    context.addNode(node, canonicalName: canonical)
                    context.addEdge(from: mainAppId, to: nodeId, type: .embeds)
                }
            }

            scanAllBinaries(in: item, mainAppId: mainAppId, rootURL: rootURL, context: &context)
        }
    }

    // MARK: - Analyze Binary Dependencies

    private func analyzeBinaryDependencies(for node: DependencyNode, rootURL: URL, context: inout AnalysisContext) {
        guard !context.visitedBinaries.contains(node.id) else { return }
        context.visitedBinaries.insert(node.id)

        guard let binaryURL = findExecutableURL(for: node, rootURL: rootURL) else {
            print("⚠️ Could not find executable for node: \(node.name) (path: \(node.path))")
            return
        }

        print("🔍 Analyzing binary: \(binaryURL.lastPathComponent) for node: \(node.name)")

        // Usa file temporaneo per output
        let tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: tempFileURL)
        }

        do {
            // Se il file non esiste ancora, crealo
            FileManager.default.createFile(atPath: tempFileURL.path, contents: nil, attributes: nil)

            let fileHandle = FileHandle(forWritingAtPath: tempFileURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
            process.arguments = ["-L", binaryURL.path]
            process.standardOutput = fileHandle
            process.standardError = fileHandle

            try process.run()
            process.waitUntilExit()

            // Chiudi il file handle per forzare il flush
            try? fileHandle?.close()

            let outputData = try Data(contentsOf: tempFileURL)
            guard let output = String(data: outputData, encoding: .utf8) else { return }

            let lines = output.components(separatedBy: "\n").dropFirst()
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                let components = trimmed.components(separatedBy: " (")
                guard let libPath = components.first?.trimmingCharacters(in: .whitespaces), !libPath.isEmpty else { continue }

                // Filtra librerie di sistema usando la nuova funzione
                if isSystemLibrary(libPath) { continue }

                if let targetNodeId = resolveLibraryPath(libPath, context: &context) {
                    context.addEdge(from: node.id, to: targetNodeId, type: .links)
                    if let targetNode = context.nodes[targetNodeId] {
                        analyzeBinaryDependencies(for: targetNode, rootURL: rootURL, context: &context)
                    }
                }
            }
        } catch {
            print("⚠️ Error analyzing \(binaryURL.path): \(error)")
        }
    }

    private func findExecutableURL(for node: DependencyNode, rootURL: URL) -> URL? {
        // Converti path relativo in assoluto
        let absolutePath = rootURL.appendingPathComponent(node.path)

        switch node.type {
        case .mainApp: return nil
        case .framework: return findExecutableInFramework(path: absolutePath.path, name: node.name)
        case .bundle: return findExecutableInBundle(path: absolutePath.path, name: node.name)
        case .appExtension: return findExecutableInAppExtension(path: absolutePath.path, name: node.name)
        case .dynamicLibrary:
            return FileManager.default.fileExists(atPath: absolutePath.path) ? absolutePath : nil
        case .plugin: return nil
        }
    }

    // MARK: - Resolve Library Path

    private func resolveLibraryPath(_ libPath: String, context: inout AnalysisContext) -> String? {
        // Estrai il canonical name dalla libreria
        let canonical = canonicalName(from: libPath)

        // Cerca prima nell'indice usando il canonical name
        if let existingNodeId = context.canonicalNameIndex[canonical] {
            return existingNodeId
        }

        // Fallback: cerca nei nodi esistenti con matching più flessibile
        // Questo gestisce casi dove il nodo è stato creato senza registrare il canonical name
        let cleanedPath: String
        if libPath.hasPrefix("@rpath/") || libPath.hasPrefix("@executable_path/") || libPath.hasPrefix("@loader_path/") {
            cleanedPath = libPath
                .replacingOccurrences(of: "@rpath/", with: "")
                .replacingOccurrences(of: "@executable_path/", with: "")
                .replacingOccurrences(of: "@loader_path/", with: "")
        } else {
            cleanedPath = libPath
        }

        // Cerca tra i nodi esistenti confrontando canonical names
        for (nodeId, node) in context.nodes {
            let nodeCanonical = canonicalName(from: node.path)
            if nodeCanonical == canonical {
                // Registra nell'indice per future lookup
                context.canonicalNameIndex[canonical] = nodeId
                return nodeId
            }
        }

        // Se non trovato, crea un nuovo nodo per la libreria esterna
        let nodeId = "dylib_\(canonical.stableHash)"
        if context.nodes[nodeId] == nil {
            let libName = URL(fileURLWithPath: libPath).lastPathComponent
            let node = DependencyNode(
                id: nodeId,
                name: libName,
                type: .dynamicLibrary,
                path: libPath
            )
            context.addNode(node, canonicalName: canonical)
        }
        return nodeId
    }

    // MARK: - Executable Finders (framework, bundle, appex)

    private func findExecutableInFramework(path: String, name: String) -> URL? {
        let frameworkURL = URL(fileURLWithPath: path)
        let frameworkName = name.replacingOccurrences(of: ".framework", with: "")

        let candidates = [
            frameworkURL.appendingPathComponent(frameworkName),
            frameworkURL.appendingPathComponent("Versions/A/\(frameworkName)"),
            frameworkURL.appendingPathComponent("Versions/Current/\(frameworkName)")
        ]

        for candidate in candidates {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), !isDir.boolValue {
                return candidate
            }
        }

        // Fallback: cerca **il primo file binario eseguibile** nel framework
        if let files = try? FileManager.default.contentsOfDirectory(atPath: frameworkURL.path) {
            for file in files {
                let candidate = frameworkURL.appendingPathComponent("/"+file)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), !isDir.boolValue {
                    // Escludi cartelle standard
                    if !file.hasSuffix(".framework") && !file.hasSuffix(".bundle") && !file.hasSuffix(".appex") {
                        return candidate
                    }
                }
            }
        }

        return nil
    }


    private func findExecutableInBundle(path: String, name: String) -> URL? {
        let bundleURL = URL(fileURLWithPath: path)
        let infoPlistURL = bundleURL.appendingPathComponent("Info.plist")
        if let plistData = try? Data(contentsOf: infoPlistURL),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
           let executableName = plist["CFBundleExecutable"] as? String {

            let executableURL = bundleURL.appendingPathComponent(executableName)
            if FileManager.default.fileExists(atPath: executableURL.path) { return executableURL }
        }
        let fallback = bundleURL.appendingPathComponent(name.replacingOccurrences(of: ".bundle", with: ""))
        if FileManager.default.fileExists(atPath: fallback.path) { return fallback }
        return nil
    }

    private func findExecutableInAppExtension(path: String, name: String) -> URL? {
        let appexURL = URL(fileURLWithPath: path)
        let infoPlistURL = appexURL.appendingPathComponent("Info.plist")
        if let plistData = try? Data(contentsOf: infoPlistURL),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
           let executableName = plist["CFBundleExecutable"] as? String {

            let executableURL = appexURL.appendingPathComponent(executableName)
            if FileManager.default.fileExists(atPath: executableURL.path) { return executableURL }
        }
        let fallback = appexURL.appendingPathComponent(name.replacingOccurrences(of: ".appex", with: ""))
        if FileManager.default.fileExists(atPath: fallback.path) { return fallback }
        return nil
    }
}

// MARK: - Helper Functions

private extension DependencyAnalyzer {
    /// Estrae il nome canonico da un path di libreria/framework
    /// Esempi:
    /// - "@rpath/AccessibilityCommon.framework/AccessibilityCommon" → "AccessibilityCommon"
    /// - "Frameworks/MyLib.framework/MyLib" → "MyLib"
    /// - "/usr/lib/libz.1.dylib" → "libz.1.dylib"
    /// - "MyFramework.framework" → "MyFramework"
    func canonicalName(from path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let lastComponent = url.lastPathComponent

        // Se il path finisce con .framework, estrai il nome del framework
        if path.hasSuffix(".framework") {
            return lastComponent.replacingOccurrences(of: ".framework", with: "")
        }

        // Se il path è tipo "SomeFramework.framework/SomeFramework", prendi l'ultimo componente
        if path.contains(".framework/") {
            return lastComponent
        }

        // Per dylib, bundle, appex, usa il nome completo del file
        return lastComponent
    }

    /// Verifica se una libreria è di sistema e dovrebbe essere filtrata
    func isSystemLibrary(_ libPath: String) -> Bool {
        if libPath.hasPrefix("/System/") { return true }
        if libPath.hasPrefix("/usr/lib/") { return true }

        // Filtra librerie Swift standard
        if libPath.contains("/swift/libswift") { return true }
        if libPath.contains("libswift_") { return true }

        // Filtra solo se è una libreria di sistema, non custom
        let fileName = URL(fileURLWithPath: libPath).lastPathComponent
        if fileName.hasPrefix("libswift") && libPath.hasPrefix("@rpath/") {
            return true
        }

        return false
    }
}

// MARK: - Stable Hash Extension

private extension String {
    var stableHash: String {
        let data = Data(self.utf8)
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
