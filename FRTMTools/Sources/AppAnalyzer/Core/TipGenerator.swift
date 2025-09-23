import Foundation

class TipGenerator {
    static func generateTips(for analysis: IPAAnalysis) -> [Tip] {
        var tips: [Tip] = []
        let allFiles = flatten(file: analysis.rootFile)

        // Tip for large binary
        if let binary = allFiles.first(where: { $0.type == .binary }) {
            if binary.size > 50 * 1024 * 1024 { // 50 MB
                tips.append(Tip(text: "The main binary is quite large (\(ByteCountFormatter.string(fromByteCount: binary.size, countStyle: .file))). Consider enabling Bitcode or using code size optimization flags.", category: .optimization))
            }
        }

        // Tip for many frameworks
        if let frameworks = analysis.rootFile.subItems?.first(where: { $0.name == "Frameworks" }) {
            if let frameworkItems = frameworks.subItems, frameworkItems.count > 20 {
                tips.append(Tip(text: "The app contains a large number of frameworks (\(frameworkItems.count)). This can impact startup time. Consider merging some frameworks or using static linking where appropriate.", category: .optimization))
            }
        }

        // Tip for large Assets.car
        if let assets = allFiles.first(where: { $0.name == "Assets.car" }) {
            if assets.size > 100 * 1024 * 1024 { // 100 MB
                tips.append(Tip(text: "The Assets.car file is very large. Ensure images are compressed and using efficient formats like HEIC.", category: .optimization))
            }
        }
        
        // Tip for stripped binary
        if !analysis.isStripped {
            tips.append(Tip(text: "The binary does not seem to be stripped of symbols. Stripping the binary can reduce its size and make it harder to reverse-engineer.", category: .warning))
        }

        // Tip for App Transport Security
        if analysis.allowsArbitraryLoads {
            tips.append(Tip(text: "The app allows arbitrary loads (NSAllowsArbitraryLoads is true). This is insecure and should be avoided. Specify domains instead.", category: .warning))
        }

        // Add a generic tip if no other tips are generated
        if tips.isEmpty {
            tips.append(Tip(text: "The analysis didn't reveal any immediate red flags. Good job!", category: .info))
        }

        return tips
    }
    
    private static func flatten(file: FileInfo) -> [FileInfo] {
        var files: [FileInfo] = []
        if let subItems = file.subItems {
            files.append(file) // also include directories
            for subItem in subItems {
                files.append(contentsOf: flatten(file: subItem))
            }
        } else {
            files.append(file)
        }
        return files
    }
}