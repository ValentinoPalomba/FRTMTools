//
//  CarAnalyzer.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 01/10/25.
//


import Foundation
#if AppDesktop
import CartoolKit
#endif
import AppKit


class CarAnalyzer: @unchecked Sendable {
    func analyzeCarFile(at url: URL, relativePath: String) -> FileInfo {
        var subItems: [FileInfo]?
        
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/assetutil")
            process.arguments = ["--info", url.path]
            
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
            FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
            let fileHandle = try FileHandle(forWritingTo: tmpURL)
            
            process.standardOutput = fileHandle
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            fileHandle.closeFile()
            
            guard process.terminationStatus == 0 else {
                let errorData = try? (process.standardError as? Pipe)?.fileHandleForReading.readToEnd()
                let errorMsg = errorData.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                throw NSError(domain: "CarAnalyzer", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
            
            let data = try Data(contentsOf: tmpURL)
            try? FileManager.default.removeItem(at: tmpURL)
            
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw NSError(domain: "CarAnalyzer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
            }
            
            let allImagesData = extractAllImagesData(at: url)
            
            var seenRenditions = [Int: Set<String>]()
            subItems = jsonArray.compactMap { item in
                guard
                    let identifier = item["NameIdentifier"] as? Int,
                    let renditionName = item["RenditionName"] as? String,
                    let size = item["SizeOnDisk"] as? Int,
                    let internalName = item["Name"] as? String
                else { return nil }
                
                var set = seenRenditions[identifier] ?? Set<String>()
                if set.contains(renditionName) {
                    return nil // già aggiunto, skip
                }
                set.insert(renditionName)
                seenRenditions[identifier] = set
                
                var fileInfo = FileInfo(
                    path: "\(relativePath)/\(renditionName)",
                    name: renditionName,
                    type: .assets,
                    size: Int64(size),
                    subItems: nil
                )
                
                fileInfo.internalImageData = allImagesData
                    .first { $0.imageName == renditionName }?.imageData
                fileInfo.internalName = internalName
                return fileInfo
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
    
    
    struct ImageData: Hashable {
        let imageName: String
        let imageData: Data
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(imageName)
        }
    }
    
    #if AppDesktop
    func extractAllImagesData(at url: URL) -> [ImageData] {
        do {
            let reader: Reader<LazyRendition> = try Reader(.init(url))
            let renditions = try reader.read()
            
            let images = renditions.compactMap { lazyRendition in
                if let image = lazyRendition.unsafeCreatedNSImage, let imageData = image.toData() {
                    return ImageData(
                        imageName: lazyRendition.fileName,
                        imageData: imageData)
                }
                return nil
            }
            
            return images
        } catch {
            return []
        }
    }
    #else
    func extractAllImagesData(at url: URL) -> [ImageData] {
        // CartoolKit is unavailable; skip image extraction.
        return []
    }
    #endif
}


extension NSImage {
    func toData(format: NSBitmapImageRep.FileType = .png, compressionFactor: Float = 1.0) -> Data? {
        guard
            let tiffData = self.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }
        
        let properties: [NSBitmapImageRep.PropertyKey: Any]
        if format == .jpeg {
            properties = [.compressionFactor: compressionFactor]
        } else {
            properties = [:]
        }
        
        return bitmap.representation(using: format, properties: properties)
    }
}


extension Data {
    func toNSImage() -> NSImage? {
        return NSImage(data: self)
    }
}
