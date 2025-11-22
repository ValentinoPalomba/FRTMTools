import Foundation

struct APKObfuscationDetector {
    struct Result {
        let totalIdentifiers: Int
        let obfuscatedIdentifiers: Int
    }
    
    static func analyze(dexFiles: [FileInfo]) -> Result {
        var total = 0
        var obfuscated = 0
        
        for dex in dexFiles {
            guard let path = dex.fullPath,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            
            let classNames = DexFileInspector.classDescriptors(from: data)
            guard !classNames.isEmpty else { continue }
            
            for descriptor in classNames {
                let normalized = descriptor.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }
                total += 1
                if isObfuscatedDescriptor(normalized) {
                    obfuscated += 1
                }
            }
        }
        
        return Result(totalIdentifiers: total, obfuscatedIdentifiers: obfuscated)
    }
    
    private static func isObfuscatedDescriptor(_ descriptor: String) -> Bool {
        guard descriptor.contains(".") else { return false }
        let parts = descriptor.split(separator: ".")
        guard parts.count >= 2 else { return false }
        let shortParts = parts.filter { segment in
            segment.count <= 2 &&
            segment.range(of: "^[a-z\\d_]+$", options: .regularExpression) != nil
        }
        return shortParts.count >= max(2, parts.count - 1)
    }
}
