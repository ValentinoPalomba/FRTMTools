//
//  URL+Extensions.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 01/10/25.
//

import Foundation

extension URL {
    func allocatedSize() -> Int64 {
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: self, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let size = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
                total += Int64(size ?? 0)
            }
        }
        let size = try? self.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
        total += Int64(size ?? 0)
        return total
    }
}
