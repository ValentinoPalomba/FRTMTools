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

            subItems = renditions.compactMap { rendition -> FileInfo? in
                let fileName = rendition.renditionName
                
                guard
                    rendition.renditionClass != "CUIInternalLinkRendition",
                    !rendition.isLinkingToPDF,
                    !rendition.isLinkingToSVG,
                    !fileName.isEmpty,
                    (rendition.isPDF || rendition.isSVG || rendition.isVector)
                else {
                    return nil
                }
                
                guard rendition.renditionName
                    .components(separatedBy: ".").count > 1, rendition.fileName
                    .components(separatedBy: ".").count > 1 else { return nil }
                
                let tmpURL = try? rendition.writeTo(.temporaryDirectory)
                let size = tmpURL.map { $0.allocatedSize() } ?? 0
                
                if size == 0 { return nil }
                
                return FileInfo(
                    path: "\(relativePath)/\(fileName)",
                    name: fileName,
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

