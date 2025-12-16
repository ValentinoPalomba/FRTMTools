import Foundation

struct SizeTextFormatter {
    /// Returns a formatted size string with count for Frameworks category
    static func formatSize(_ size: Int64, categoryName: String, itemCount: Int) -> String {
        let sizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)

        // Show count only for Frameworks category
        if categoryName == "Frameworks" && itemCount > 0 {
            return "\(itemCount) - \(sizeString)"
        }

        return sizeString
    }
}
