//
//  DetectorConfiguration.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//

import Foundation
// MARK: - Configurazione
struct DetectorConfiguration {
    var sourcePaths: [String] = []
    var excludedPaths: [String] = []
    var excludedFileExtensions: [String] = []
    var supportedImageTypes: [AssetType] = AssetType.allCases
    var caseSensitive: Bool = false
    var includeAppIconVariants: Bool = false
    var includeLaunchImages: Bool = false
    var customPatterns: [String] = []
    
    static var defaultSearchPatterns: [String] {
        return [
            #"UIImage\(named:\s*["']([^"']+)["']\)"#,
            #"UIImage\(named:\s*["']([^"']+)["'],\s*in:"#,
            #"Image\(["']([^"']+)["']\)"#,
            #"named:\s*["']([^"']+)["']"#,
            #"imageLiteralResourceName:\s*["']([^"']+)["']"#,
            #"setImage\([^,]*,\s*forState:"#,
            #"image\s*=\s*["']([^"']+)["']"#,
            #"backgroundImage\s*=\s*["']([^"']+)["']"#
        ]
    }
    
    static var defaultConfiguration: DetectorConfiguration {
        return DetectorConfiguration()
    }
}
