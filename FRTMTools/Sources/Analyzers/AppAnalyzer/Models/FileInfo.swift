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
    let path: String?
    var size: Int64
    var subItems: [FileInfo]?

    init(id: UUID = UUID(), path: String? = nil, name: String, type: FileType, size: Int64, subItems: [FileInfo]? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.type = type
        self.size = size
        self.subItems = subItems
    }
}
