//
//  FileInfo.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//

import Foundation
import AppKit
struct FileInfo: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let type: FileType
    let path: String?
    let fullPath: String?
    var size: Int64
    var subItems: [FileInfo]?
    var internalName: String? //only used for assets extracted from asset.car
    var internalImageData: Data?

    init(id: UUID = UUID(), path: String? = nil, fullPath: String? = nil, name: String, type: FileType, size: Int64, subItems: [FileInfo]? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.fullPath = fullPath
        self.type = type
        self.size = size
        self.subItems = subItems
    }

    var sizeText: String {
        let itemCount: Int
        if let subItems = subItems {
            itemCount = subItems.filter { $0.type == .framework }.count
        } else {
            itemCount = 0
        }
        return SizeTextFormatter.formatSize(size, categoryName: name, itemCount: itemCount)
    }
}
