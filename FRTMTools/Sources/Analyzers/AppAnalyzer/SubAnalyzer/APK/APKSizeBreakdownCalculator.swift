import Foundation

struct APKSizeBreakdown {
    let totalBytes: Int64
    let dexBytes: Int64
    let nativeBytes: Int64
    let resourcesBytes: Int64
}

enum APKSizeBreakdownCalculator {
    static func calculate(from root: FileInfo, overridingTotalBytes: Int64? = nil) -> InstalledSizeMetrics {
        let breakdown = breakdownBytes(from: root)
        let totalBytes = overridingTotalBytes ?? breakdown.totalBytes
        let total = max(Int(totalBytes / 1_048_576), 1)
        let binaries = max(Int(breakdown.dexBytes / 1_048_576), 0)
        let frameworks = max(Int(breakdown.nativeBytes / 1_048_576), 0)
        let resources = max(Int(breakdown.resourcesBytes / 1_048_576), 0)
        return InstalledSizeMetrics(total: total, binaries: binaries, frameworks: frameworks, resources: resources)
    }

    static func breakdownBytes(from root: FileInfo) -> APKSizeBreakdown {
        let totalBytes = root.size
        let dexBytes = sumFiles(in: root) { $0.name.lowercased().hasSuffix(".dex") }
        let nativeBytes = sumFiles(in: root) { $0.name.lowercased().hasSuffix(".so") }
        let resourcesBytes = max(totalBytes - dexBytes - nativeBytes, 0)
        return APKSizeBreakdown(
            totalBytes: totalBytes,
            dexBytes: dexBytes,
            nativeBytes: nativeBytes,
            resourcesBytes: resourcesBytes
        )
    }

    private static func sumFiles(in file: FileInfo, where predicate: (FileInfo) -> Bool) -> Int64 {
        var total: Int64 = 0
        if predicate(file) {
            total += file.size
        }
        for sub in file.subItems ?? [] {
            total += sumFiles(in: sub, where: predicate)
        }
        return total
    }
}
