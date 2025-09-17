import Foundation

struct SecurityScanner {
    
    private struct Rule {
        let name: String
        let pattern: String
    }
    
    private let rules: [Rule] = [
        Rule(
            name: "Generic API Key",
            pattern: #"(api_key|apiKey|secret|token|password)['"]?\s*[:=]\s*['"]([a-zA-Z0-9-_\.]{20,})['"]"#
        ),
        Rule(
            name: "AWS Access Key ID",
            pattern: #"AKIA[0-9A-Z]{16}"#
        ),
        Rule(
            name: "JSON Web Token (JWT)",
            pattern: #"eyJ[a-zA-Z0-9-_]+\.[a-zA-Z0-9-_]+\.[a-zA-Z0-9-_]+"#
        ),
        Rule(
            name: "Private Key",
            pattern: #"-----(BEGIN|END) (RSA|EC|OPENSSH) PRIVATE KEY-----"#
        )
    ]

    func scan(directory: URL) async -> SecurityScanResult {
        var findings: [SecurityFinding] = []
        
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return SecurityScanResult(projectPath: directory.path, findings: [])
        }
        
        while let next = enumerator.nextObject() {
            guard let fileURL = next as? URL else { continue }
            do {
                let isRegularFile = try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile ?? false
                if !isRegularFile { continue }

                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines)
                
                for (index, line) in lines.enumerated() {
                    for rule in rules {
                        if line.range(of: rule.pattern, options: .regularExpression) != nil {
                            let finding = SecurityFinding(
                                filePath: fileURL.path.replacingOccurrences(of: directory.path, with: ""),
                                lineNumber: index + 1,
                                content: line.trimmingCharacters(in: .whitespacesAndNewlines),
                                ruleName: rule.name
                            )
                            findings.append(finding)
                        }
                    }
                }
            } catch {
                // Ignore files that can't be read
                continue
            }
        }
        
        return SecurityScanResult(projectPath: directory.path, findings: findings)
    }
}

