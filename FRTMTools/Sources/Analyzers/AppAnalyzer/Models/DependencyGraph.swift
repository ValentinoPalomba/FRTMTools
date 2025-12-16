//
//  DependencyGraph.swift
//  FRTMTools
//
//  Created by Claude Code
//

import Foundation

// MARK: - Dependency Graph Models

struct DependencyNode: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let type: DependencyNodeType
    let path: String
    var size: Int64?

    init(id: String = UUID().uuidString, name: String, type: DependencyNodeType, path: String, size: Int64? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.path = path
        self.size = size
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DependencyNode, rhs: DependencyNode) -> Bool {
        lhs.id == rhs.id
    }
}

enum DependencyNodeType: String, Codable, Sendable {
    case mainApp = "Main App"
    case framework = "Framework"
    case dynamicLibrary = "Dynamic Library"
    case bundle = "Bundle"
    case plugin = "Plugin"
    case appExtension = "App Extension"
}

struct DependencyEdge: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let fromId: String
    let toId: String
    let type: DependencyEdgeType

    init(id: String = UUID().uuidString, fromId: String, toId: String, type: DependencyEdgeType) {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.type = type
    }
}

enum DependencyEdgeType: String, Codable, Sendable {
    case links = "Links"
    case embeds = "Embeds"
    case loads = "Loads"
}

struct DependencyGraph: Codable, Sendable {
    let nodes: Set<DependencyNode>
    let edges: Set<DependencyEdge>

    var stats: DependencyStats {
        DependencyStats(
            totalNodes: nodes.count,
            frameworkCount: nodes.filter { $0.type == .framework }.count,
            bundleCount: nodes.filter { $0.type == .bundle }.count,
            extensionCount: nodes.filter { $0.type == .appExtension }.count,
            totalSize: nodes.compactMap { $0.size }.reduce(0, +)
        )
    }
}

struct DependencyStats {
    let totalNodes: Int
    let frameworkCount: Int
    let bundleCount: Int
    let extensionCount: Int
    let totalSize: Int64
}


