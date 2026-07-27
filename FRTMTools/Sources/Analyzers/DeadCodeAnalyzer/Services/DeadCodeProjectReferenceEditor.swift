import Foundation
import XcodeProj

struct DeadCodeProjectMetadataEdit: Sendable {
    let fileURL: URL
    let originalContents: String
    let updatedContents: String
}

enum DeadCodeProjectReferenceEditor {
    static func makeEdits(
        removing sourceFileURLs: [URL],
        projectRoot: URL
    ) throws -> [DeadCodeProjectMetadataEdit] {
        let sourcePaths = Set(
            sourceFileURLs.map {
                $0.resolvingSymlinksInPath().standardizedFileURL.path
            }
        )
        guard !sourcePaths.isEmpty else { return [] }

        let sourceFileNames = Set(sourceFileURLs.map(\.lastPathComponent))
        return try xcodeProjectURLs(under: projectRoot).compactMap {
            projectURL throws -> DeadCodeProjectMetadataEdit? in
            let pbxprojURL = projectURL.appendingPathComponent("project.pbxproj")
            guard let originalContents = try? String(
                contentsOf: pbxprojURL,
                encoding: .utf8
            ),
            sourceFileNames.contains(where: originalContents.contains) else {
                return nil
            }

            let project = try XcodeProj(pathString: projectURL.path)
            guard let rootProject = project.pbxproj.rootObject else {
                return nil
            }
            let sourceRoot = projectURL.deletingLastPathComponent()
                .appendingPathComponent(rootProject.projectDirPath)
                .standardizedFileURL
            let matchingReferences = try fileReferences(in: rootProject.mainGroup)
                .filter { reference in
                    guard let fullPath = try reference.fullPath(
                        sourceRoot: sourceRoot.path
                    ) else {
                        return false
                    }
                    return sourcePaths.contains(
                        URL(fileURLWithPath: fullPath)
                            .resolvingSymlinksInPath()
                            .standardizedFileURL.path
                    )
                }

            guard !matchingReferences.isEmpty else { return nil }

            let referenceIDs = Set(matchingReferences.map(\.uuid))
            let buildFileIDs = Set(
                rootProject.targets.flatMap(\.buildPhases)
                    .flatMap { $0.files ?? [] }
                    .filter { buildFile in
                        guard let fileID = buildFile.file?.uuid else { return false }
                        return referenceIDs.contains(fileID)
                    }
                    .map(\.uuid)
            )
            let updatedContents = removingProjectLines(
                from: originalContents,
                objectIDs: referenceIDs.union(buildFileIDs)
            )

            guard updatedContents != originalContents else {
                throw DeadCodeRemovalError.projectReferenceUpdateFailed(
                    "Could not remove the matching references from \(projectURL.lastPathComponent)."
                )
            }

            _ = try PBXProj(data: Data(updatedContents.utf8))
            return DeadCodeProjectMetadataEdit(
                fileURL: pbxprojURL,
                originalContents: originalContents,
                updatedContents: updatedContents
            )
        }
    }

    private static func xcodeProjectURLs(under projectRoot: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            throw DeadCodeRemovalError.projectReferenceUpdateFailed(
                "Could not inspect Xcode projects under \(projectRoot.path)."
            )
        }

        var projectURLs: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "xcodeproj" {
                projectURLs.append(url.standardizedFileURL)
                enumerator.skipDescendants()
            } else if ["build", "deriveddata"].contains(url.lastPathComponent.lowercased()) {
                enumerator.skipDescendants()
            }
        }
        return projectURLs.sorted { $0.path < $1.path }
    }

    private static func fileReferences(
        in group: PBXGroup
    ) throws -> [PBXFileReference] {
        try group.children.flatMap { child -> [PBXFileReference] in
            if let fileReference = child as? PBXFileReference {
                return [fileReference]
            }
            if let childGroup = child as? PBXGroup {
                return try fileReferences(in: childGroup)
            }
            return []
        }
    }

    private static func removingProjectLines(
        from contents: String,
        objectIDs: Set<String>
    ) -> String {
        let retainedLines = contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                !objectIDs.contains { line.contains($0) }
            }
        return retainedLines.joined(separator: "\n")
    }
}
