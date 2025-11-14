import Foundation

enum DexFileInspector {
    static func classDescriptors(from data: Data) -> [String] {
        guard data.count >= 0x44 else { return [] }

        func readUInt32(_ offset: Int) -> UInt32 {
            guard offset + 4 <= data.count else { return 0 }
            return data[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        }

        let stringIdsSize = Int(readUInt32(0x38))
        let stringIdsOff = Int(readUInt32(0x3C))
        let typeIdsSize = Int(readUInt32(0x40))
        let typeIdsOff = Int(readUInt32(0x44))

        guard stringIdsSize > 0,
              stringIdsOff > 0,
              typeIdsSize > 0,
              typeIdsOff > 0,
              stringIdsOff + stringIdsSize * 4 <= data.count,
              typeIdsOff + typeIdsSize * 4 <= data.count else {
            return []
        }

        var strings: [String] = Array(repeating: "", count: stringIdsSize)
        for idx in 0..<stringIdsSize {
            let offset = Int(readUInt32(stringIdsOff + idx * 4))
            guard offset < data.count else { continue }
            strings[idx] = readDexString(from: data, at: offset)
        }

        var descriptors: [String] = []
        for idx in 0..<typeIdsSize {
            let descriptorIdx = Int(readUInt32(typeIdsOff + idx * 4))
            guard descriptorIdx < strings.count else { continue }
            let descriptor = strings[descriptorIdx]
            guard descriptor.hasPrefix("L"), descriptor.hasSuffix(";") else { continue }
            let trimmed = descriptor.dropFirst().dropLast()
            if trimmed.isEmpty { continue }
            descriptors.append(trimmed.replacingOccurrences(of: "/", with: "."))
        }

        return descriptors
    }

    private static func readDexString(from data: Data, at offset: Int) -> String {
        var cursor = offset
        _ = readULEB128(data: data, cursor: &cursor) // UTF-16 length (unused)
        var bytes: [UInt8] = []
        while cursor < data.count {
            let byte = data[cursor]
            cursor += 1
            if byte == 0 { break }
            bytes.append(byte)
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private static func readULEB128(data: Data, cursor: inout Int) -> UInt32 {
        var result: UInt32 = 0
        var shift: UInt32 = 0
        while cursor < data.count {
            let byte = data[cursor]
            cursor += 1
            result |= UInt32(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                break
            }
            shift += 7
            if shift >= 35 { break }
        }
        return result
    }
}
