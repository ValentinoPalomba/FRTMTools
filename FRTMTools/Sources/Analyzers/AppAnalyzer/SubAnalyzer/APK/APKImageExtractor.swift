import Foundation
import AppKit

final class APKImageExtractor: @unchecked Sendable {
    private let fm = FileManager.default
    private let imageExtensions: Set<String> = ["png", "webp", "jpg", "jpeg", "gif", "bmp", "svg"]

    struct ExtractionResult {
        let totalImages: Int
        let extractedImages: Int
        let destinationURL: URL
        let errors: [Error]
    }

    /// Extracts all images from the APK to a destination folder
    /// - Parameters:
    ///   - layout: The Android package layout containing the root URL
    ///   - destinationURL: Where to extract the images
    ///   - preserveStructure: If true, preserves directory structure; if false, flattens all images to destination root
    /// - Returns: Extraction result with statistics
    func extractImages(from layout: AndroidPackageLayout, to destinationURL: URL, preserveStructure: Bool = true) -> ExtractionResult {
        var totalImages = 0
        var extractedImages = 0
        var errors: [Error] = []

        // Ensure destination exists
        do {
            try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        } catch {
            errors.append(error)
            return ExtractionResult(totalImages: 0, extractedImages: 0, destinationURL: destinationURL, errors: errors)
        }

        // Find all image files
        guard let enumerator = fm.enumerator(
            at: layout.rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ExtractionResult(totalImages: 0, extractedImages: 0, destinationURL: destinationURL, errors: errors)
        }

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }

            // Check if it's a regular file
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            totalImages += 1

            // Determine destination path
            let destinationFileURL: URL
            if preserveStructure {
                // Preserve directory structure
                let relativePath = fileURL.path.replacingOccurrences(of: layout.rootURL.path, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                destinationFileURL = destinationURL.appendingPathComponent(relativePath)
            } else {
                // Flatten to destination root with unique name if needed
                var filename = fileURL.lastPathComponent
                var targetURL = destinationURL.appendingPathComponent(filename)
                var counter = 1

                // Handle name conflicts
                while fm.fileExists(atPath: targetURL.path) {
                    let nameWithoutExt = fileURL.deletingPathExtension().lastPathComponent
                    let ext = fileURL.pathExtension
                    filename = "\(nameWithoutExt)_\(counter).\(ext)"
                    targetURL = destinationURL.appendingPathComponent(filename)
                    counter += 1
                }
                destinationFileURL = targetURL
            }

            // Create parent directory if needed
            let parentDir = destinationFileURL.deletingLastPathComponent()
            do {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            } catch {
                errors.append(error)
                continue
            }

            // Copy the file
            do {
                try fm.copyItem(at: fileURL, to: destinationFileURL)
                extractedImages += 1
            } catch {
                errors.append(error)
            }
        }

        return ExtractionResult(
            totalImages: totalImages,
            extractedImages: extractedImages,
            destinationURL: destinationURL,
            errors: errors
        )
    }

    /// Finds all image files in the APK
    /// - Parameter layout: The Android package layout
    /// - Returns: Array of image file URLs
    func findAllImages(in layout: AndroidPackageLayout) -> [URL] {
        var imageFiles: [URL] = []

        guard let enumerator = fm.enumerator(
            at: layout.rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return imageFiles
        }

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }

            // Check if it's a regular file
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            imageFiles.append(fileURL)
        }

        return imageFiles
    }

    /// Gets the count of images in the APK
    /// - Parameter layout: The Android package layout
    /// - Returns: Number of image files found
    func imageCount(in layout: AndroidPackageLayout) -> Int {
        var count = 0

        guard let enumerator = fm.enumerator(
            at: layout.rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }

            // Check if it's a regular file
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            count += 1
        }

        return count
    }
}
