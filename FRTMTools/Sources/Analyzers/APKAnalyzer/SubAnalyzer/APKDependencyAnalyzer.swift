//
//  DependencyAnalyzer.swift
//  FRTMTools
//
//

import Foundation

/// Analyzes native library dependencies in APK
class APKDependencyAnalyzer {

    /// Analyzes dependencies in an APK
    /// - Parameter rootFile: Root file hierarchy from APK analysis
    /// - Returns: DependencyGraph showing native library relationships
    static func analyzeDependencies(in rootFile: FileInfo, packageName: String?) async -> DependencyGraph {
        var nodes: Set<DependencyNode> = []
        var edges: Set<DependencyEdge> = []

        // Create main app node
        let appNodeId = "app"
        nodes.insert(DependencyNode(
            id: appNodeId,
            name: packageName ?? "App",
            type: .mainApp,
            path: ""
        ))

        // Find all native libraries
        let nativeLibs = findNativeLibraries(in: rootFile)

        // Create nodes for each native library
        for lib in nativeLibs {
            let nodeId = "lib_\(lib.name)"
            nodes.insert(DependencyNode(
                id: nodeId,
                name: lib.name,
                type: .dynamicLibrary,
                path: lib.fullPath ?? "",
                size: lib.size
            ))

            // Create edge from app to library
            edges.insert(DependencyEdge(
                id: "\(appNodeId)_\(nodeId)",
                fromId: appNodeId,
                toId: nodeId,
                type: .loads
            ))

            // Analyze dependencies of this library
            if let dependencies = await analyzeLibraryDependencies(at: lib.fullPath) {
                for dep in dependencies {
                    // Filter out system libraries
                    if isSystemLibrary(dep) {
                        continue
                    }

                    // Check if this dependency exists in our libs
                    if let depLib = nativeLibs.first(where: { $0.name == dep || $0.name == "lib\(dep).so" }) {
                        let depNodeId = "lib_\(depLib.name)"

                        // Create edge from lib to dependency
                        let edgeId = "\(nodeId)_\(depNodeId)"
                        edges.insert(DependencyEdge(
                            id: edgeId,
                            fromId: nodeId,
                            toId: depNodeId,
                            type: .links
                        ))
                    }
                }
            }
        }

        return DependencyGraph(nodes: nodes, edges: edges)
    }

    /// Finds all native libraries in file hierarchy
    private static func findNativeLibraries(in file: FileInfo) -> [FileInfo] {
        var libraries: [FileInfo] = []

        if file.type == .so || file.name.hasSuffix(".so") {
            libraries.append(file)
        }

        if let subItems = file.subItems {
            for subItem in subItems {
                libraries.append(contentsOf: findNativeLibraries(in: subItem))
            }
        }

        return libraries
    }

    /// Analyzes dependencies of a native library using otool/readelf
    private static func analyzeLibraryDependencies(at path: String?) async -> [String]? {
        guard let path = path else { return nil }

        // Try to use otool (macOS) or readelf (Linux) to analyze dependencies
        // On macOS, we can use otool -L
        let process = Process()

        #if os(macOS)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        process.arguments = ["-L", path]
        #else
        // On Linux, would use readelf
        return nil
        #endif

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            // Parse output to extract library names
            let lines = output.components(separatedBy: .newlines)
            var dependencies: [String] = []

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains(".so") || trimmed.contains(".dylib") {
                    // Extract library name
                    if let libName = extractLibraryName(from: trimmed) {
                        dependencies.append(libName)
                    }
                }
            }

            return dependencies
        } catch {
            return nil
        }
    }

    /// Extracts library name from otool output line
    private static func extractLibraryName(from line: String) -> String? {
        // Example: "    libfoo.so (compatibility version...)"
        let components = line.components(separatedBy: " ")
        for component in components {
            if component.contains(".so") || component.contains(".dylib") {
                // Extract just the filename
                if let lastPart = component.split(separator: "/").last {
                    return String(lastPart)
                }
                return component
            }
        }
        return nil
    }

    /// Checks if a library is a system library
    private static func isSystemLibrary(_ name: String) -> Bool {
        let systemPrefixes = [
            "libc.",
            "libm.",
            "libdl.",
            "liblog.",
            "libz.",
            "libandroid.",
            "libEGL.",
            "libGLESv",
            "libOpenSLES.",
            "libjnigraphics."
        ]

        return systemPrefixes.contains { name.hasPrefix($0) }
    }
}
