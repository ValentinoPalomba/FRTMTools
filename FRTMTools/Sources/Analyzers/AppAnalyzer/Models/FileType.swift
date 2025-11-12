//
//  FileType.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//

import Foundation

enum FileType: String, Codable {
    case file
    case directory
    case app
    case framework
    case bundle
    case assets
    case binary
    case plist
    case lproj

    // Android APK specific types
    case dex          // Dalvik Executable
    case so           // Native shared library
    case xml          // Android XML resource
    case arsc         // Compiled resources
    case apk          // APK file
}