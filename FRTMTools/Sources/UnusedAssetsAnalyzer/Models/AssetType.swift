//
//  AssetType.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//

import Foundation

enum AssetType: String, Codable, CaseIterable {
    case png = "png"
    case jpg = "jpg"
    case jpeg = "jpeg"
    case gif = "gif"
    case svg = "svg"
    case pdf = "pdf"
    case heic = "heic"
    case webp = "webp"
    case imageSet = "imageset"
    
    var extensions: [String] {
        switch self {
        case .jpg:
            return ["jpg", "jpeg"]
        case .jpeg:
            return ["jpg", "jpeg"]
        default:
            return [self.rawValue]
        }
    }
}

// Corrected AssetType extension
extension AssetType {
    var iconName: String {
        switch self {
            case .png, .jpg, .jpeg, .gif, .heic, .webp, .svg, .imageSet: return "photo"
        case .pdf: return "doc.text.fill"
        }
    }
}
