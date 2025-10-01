//
//  CarAnalyzer.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 01/10/25.
//


import Foundation
import CartoolKit

class CarAnalyzer {
    func analyzeCarFile(at url: URL, relativePath: String) -> FileInfo {
        var subItems: [FileInfo]?
        
        do {
            let reader: Reader<LazyRendition> = try Reader(.init(url))
            let renditions = try reader.read()
            let filteredRenditions = renditions.reduce([LazyRendition]()) {
                partialResult,
                lazyRendition in
                let isInternal = lazyRendition.renditionClass == "CUIInternalLinkRendition"
                let isAlredyInWithDifferentRenditionClass = partialResult.contains(
                    where: {
                        $0.renditionClass != lazyRendition.renditionClass && $0.renditionName == lazyRendition.renditionName
                    }
                )
                
                if isInternal {
                    return partialResult
                }
                
                if isAlredyInWithDifferentRenditionClass {
                    return partialResult
                }
                
                return partialResult + [lazyRendition]
            }
            
            subItems = filteredRenditions.compactMap { rendition -> FileInfo? in
                let fileName = rendition.renditionName
                
                guard
                    rendition.renditionClass != "CUIInternalLinkRendition",
                    !rendition.isLinkingToPDF,
                    !rendition.isLinkingToSVG,
                    !fileName.isEmpty
                else {
                    return nil
                }
                
                let tmpURL = try? rendition.writeTo(.temporaryDirectory)
                let size = tmpURL.map { $0.allocatedSize() } ?? 0
                
                if size == 0 { return nil }
                
                return FileInfo(
                    path: "\(relativePath)/\(rendition.fileName)",
                    name: rendition.fileName,
                    type: .file,
                    size: size,
                    subItems: nil
                )
            }
        } catch {
            print("Error parsing .car file at '\(url.path)': \(error.localizedDescription)")
        }
        
        return FileInfo(
            path: relativePath,
            name: url.lastPathComponent,
            type: .assets,
            size: url.allocatedSize(),
            subItems: subItems
        )
    }
}

