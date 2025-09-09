//
//  FileInfo.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//

import Foundation

struct FileInfo: Identifiable, Codable {
    let id: UUID
    let name: String
    let type: FileType
    let size: Int64
    let subItems: [FileInfo]?

    init(id: UUID = UUID(), name: String, type: FileType, size: Int64, subItems: [FileInfo]? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.size = size
        self.subItems = subItems
    }
}
