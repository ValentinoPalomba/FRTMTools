//
//  FileType.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//

import Foundation

enum FileType: String, Codable, Sendable {
    case file
    case directory
    case app
    case framework
    case bundle
    case assets
    case binary
    case plist
    case lproj
}