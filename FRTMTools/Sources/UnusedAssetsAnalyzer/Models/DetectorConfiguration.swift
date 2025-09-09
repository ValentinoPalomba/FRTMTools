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
            // UIKit patterns
            #"UIImage\(named:\s*["\']([^"']+)["\']"#,
            #"UIImage\(named:\s*["\']([^"']+)["\'],\s*in:"#,
            #"UIImage\.init\(named:\s*["\']([^"']+)["\']"#,
            
            // SwiftUI patterns
            #"Image\(["\']([^"']+)["\']\)"#,
            #"Image\.init\(["\']([^"']+)["\']\)"#,
            
            // Bundle.main.path(forResource:...)
            #"\.path\(forResource:\s*["\']([^"']+)["\'],\s*ofType:\s*["\']([^"']+)["\']"#,
            // String literals che potrebbero essere nomi di immagini
            #"["\']([a-zA-Z_][a-zA-Z0-9_-]*\.(?:png|jpg|jpeg|gif|svg|pdf|heic|webp))["\']"#,
            
            // Asset catalog references (senza estensioni)
            #"["\']([a-zA-Z_][a-zA-Z0-9_-]*)["\']"#,
            
            // Interface Builder
            #"image\s*=\s*["\']([^"']+)["\']"#,
            #"imageName\s*=\s*["\']([^"']+)["\']"#,
            
            // Background images
            #"backgroundImage\s*=\s*["\']([^"']+)["\']"#,
            #"setBackgroundImage\([^,]*["\']([^"']+)["\']"#,
            
            // Button images
            #"setImage\([^,]*["\']([^"']+)["\']"#,
            
            // Constants e variables che potrebbero contenere nomi di immagini
            #"let\s+\w+\s*=\s*["\']([a-zA-Z_][a-zA-Z0-9_-]*)["\']"#,
            #"var\s+\w+\s*=\s*["\']([a-zA-Z_][a-zA-Z0-9_-]*)["\']"#,
        ]
    }
    static var defaultConfiguration: DetectorConfiguration {
        return DetectorConfiguration()
    }
}
