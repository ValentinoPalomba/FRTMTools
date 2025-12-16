import Foundation

extension String {
    var htmlEscaped: String {
        var escaped = self
        let replacements: [(String, String)] = [
            ("&", "&amp;"),
            ("<", "&lt;"),
            (">", "&gt;"),
            ("\"", "&quot;"),
            ("'", "&#39;")
        ]
        for (target, replacement) in replacements {
            escaped = escaped.replacingOccurrences(of: target, with: replacement)
        }
        return escaped
    }

    var htmlAttributeEscaped: String {
        var escaped = self
        let replacements: [(String, String)] = [
            ("&", "&amp;"),
            ("\"", "&quot;"),
            ("'", "&#39;"),
            ("<", "&lt;"),
            (">", "&gt;")
        ]
        for (target, replacement) in replacements {
            escaped = escaped.replacingOccurrences(of: target, with: replacement)
        }
        return escaped
    }
}
