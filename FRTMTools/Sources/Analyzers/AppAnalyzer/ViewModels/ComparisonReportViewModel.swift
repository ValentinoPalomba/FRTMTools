import Foundation

struct ComparisonReportViewModel {
    let first: IPAAnalysis
    let second: IPAAnalysis
    let result: ComparisonResult

    func reportItems(for language: ReportLanguage) -> [String] {
        var items: [String] = []

        // Overall size comparison
        let totalSizeBefore = first.totalSize
        let totalSizeAfter = second.totalSize
        let totalSizeDiff = totalSizeAfter - totalSizeBefore

        if totalSizeDiff > 0 {
            let english = "Total size increased by \(ByteCountFormatter.string(fromByteCount: totalSizeDiff, countStyle: .file)) (from \(ByteCountFormatter.string(fromByteCount: totalSizeBefore, countStyle: .file)) to \(ByteCountFormatter.string(fromByteCount: totalSizeAfter, countStyle: .file)))"
            let italian = "La dimensione totale è aumentata di \(ByteCountFormatter.string(fromByteCount: totalSizeDiff, countStyle: .file)) (da \(ByteCountFormatter.string(fromByteCount: totalSizeBefore, countStyle: .file)) a \(ByteCountFormatter.string(fromByteCount: totalSizeAfter, countStyle: .file)))."
            items.append(localized(english: english, italian: italian, language: language))
        } else if totalSizeDiff < 0 {
            let english = "Total size decreased by \(ByteCountFormatter.string(fromByteCount: abs(totalSizeDiff), countStyle: .file)) (from \(ByteCountFormatter.string(fromByteCount: totalSizeBefore, countStyle: .file)) to \(ByteCountFormatter.string(fromByteCount: totalSizeAfter, countStyle: .file)))"
            let italian = "La dimensione totale è diminuita di \(ByteCountFormatter.string(fromByteCount: abs(totalSizeDiff), countStyle: .file)) (da \(ByteCountFormatter.string(fromByteCount: totalSizeBefore, countStyle: .file)) a \(ByteCountFormatter.string(fromByteCount: totalSizeAfter, countStyle: .file)))."
            items.append(localized(english: english, italian: italian, language: language))
        } else {
            let english = "Total size remained unchanged at \(ByteCountFormatter.string(fromByteCount: totalSizeBefore, countStyle: .file))"
            let italian = "La dimensione totale è rimasta invariata a \(ByteCountFormatter.string(fromByteCount: totalSizeBefore, countStyle: .file))."
            items.append(localized(english: english, italian: italian, language: language))
        }

        // Category-specific changes
        for category in result.categories {
            let diff = category.size2 - category.size1

            if diff == 0 {
                continue // Skip unchanged categories
            }

            let categoryName = localizedCategoryName(for: category.name, language: language)
            let absDiff = abs(diff)

            if diff > 0 {
                let english = "\(categoryName) increased by \(ByteCountFormatter.string(fromByteCount: absDiff, countStyle: .file))"
                let italian = "\(categoryName) è aumentata di \(ByteCountFormatter.string(fromByteCount: absDiff, countStyle: .file))"
                items.append(localized(english: english, italian: italian, language: language))
            } else {
                let english = "\(categoryName) decreased by \(ByteCountFormatter.string(fromByteCount: absDiff, countStyle: .file))"
                let italian = "\(categoryName) è diminuita di \(ByteCountFormatter.string(fromByteCount: absDiff, countStyle: .file))"
                items.append(localized(english: english, italian: italian, language: language))
            }
        }

        // Image-specific analysis
        let imageExtensions: Set<String> = [".png", ".jpg", ".jpeg", ".gif", ".heic", ".heif", ".webp", ".svg", ".pdf", ".tiff"]

        let addedImages = result.addedFiles.filter { file in
            imageExtensions.contains { file.name.lowercased().hasSuffix($0) }
        }

        let removedImages = result.removedFiles.filter { file in
            imageExtensions.contains { file.name.lowercased().hasSuffix($0) }
        }

        if !addedImages.isEmpty {
            let totalSize = addedImages.reduce(0) { $0 + $1.size2 }
            let english = "\(addedImages.count) image\(addedImages.count == 1 ? "" : "s") added for a total of \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))"
            let italianCount = addedImages.count == 1 ? "immagine" : "immagini"
            let italian = "\(addedImages.count) \(italianCount) aggiunt\(addedImages.count == 1 ? "a" : "e") per un totale di \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))"
            items.append(localized(english: english, italian: italian, language: language))
        }

        if !removedImages.isEmpty {
            let totalSize = removedImages.reduce(0) { $0 + $1.size1 }
            let english = "\(removedImages.count) image\(removedImages.count == 1 ? "" : "s") removed, saving \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))"
            let italianCount = removedImages.count == 1 ? "immagine" : "immagini"
            let italianVerb = removedImages.count == 1 ? "rimossa" : "rimosse"
            let italian = "\(removedImages.count) \(italianCount) \(italianVerb) con un risparmio di \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))"
            items.append(localized(english: english, italian: italian, language: language))
        }

        // Framework analysis
        let firstFrameworks = collectFrameworkSummaries(from: first.rootFile)
        let secondFrameworks = collectFrameworkSummaries(from: second.rootFile)
        let addedFrameworks = secondFrameworks.keys.filter { firstFrameworks[$0] == nil }.sorted()
        let removedFrameworks = firstFrameworks.keys.filter { secondFrameworks[$0] == nil }.sorted()

        if !addedFrameworks.isEmpty {
            let nameList = addedFrameworks.joined(separator: ", ")
            let english = "\(addedFrameworks.count) framework\(addedFrameworks.count == 1 ? "" : "s") added: \(nameList)"
            let italianPrefix = addedFrameworks.count == 1 ? "Aggiunto" : "Aggiunti"
            let italian = "\(italianPrefix) \(addedFrameworks.count) framework: \(nameList)"
            items.append(localized(english: english, italian: italian, language: language))
        }

        if !removedFrameworks.isEmpty {
            let nameList = removedFrameworks.joined(separator: ", ")
            let english = "\(removedFrameworks.count) framework\(removedFrameworks.count == 1 ? "" : "s") removed: \(nameList)"
            let italianPrefix = removedFrameworks.count == 1 ? "Rimosso" : "Rimossi"
            let italian = "\(italianPrefix) \(removedFrameworks.count) framework: \(nameList)"
            items.append(localized(english: english, italian: italian, language: language))
        }

        let heavyFrameworkThreshold: Int64 = 10 * 1024 * 1024
        let heavyFrameworks = addedFrameworks.compactMap { name -> (String, Int64)? in
            guard let size = secondFrameworks[name], size >= heavyFrameworkThreshold else { return nil }
            return (name, size)
        }

        for heavy in heavyFrameworks {
            let formattedSize = ByteCountFormatter.string(fromByteCount: heavy.1, countStyle: .file)
            let english = "New framework \(heavy.0) weighs \(formattedSize)"
            let italian = "Il nuovo framework \(heavy.0) ha un peso di \(formattedSize)"
            items.append(localized(english: english, italian: italian, language: language))
        }

        let growthThreshold: Int64 = 5 * 1024 * 1024
        let grownFrameworks = secondFrameworks.compactMap { (name, size2) -> (String, Int64, Int64)? in
            guard let size1 = firstFrameworks[name] else { return nil }
            let diff = size2 - size1
            guard diff >= growthThreshold else { return nil }
            return (name, diff, size2)
        }

        for (name, increase, finalSize) in grownFrameworks.sorted(by: { $0.0 < $1.0 }) {
            let increaseText = ByteCountFormatter.string(fromByteCount: increase, countStyle: .file)
            let finalSizeText = ByteCountFormatter.string(fromByteCount: finalSize, countStyle: .file)
            let english = "Framework \(name) grew by \(increaseText) and now weighs \(finalSizeText)"
            let italian = "Il framework \(name) è cresciuto di \(increaseText) e pesa adesso \(finalSizeText)"
            items.append(localized(english: english, italian: italian, language: language))
        }

        // File counts summary
        if !result.addedFiles.isEmpty {
            let nonImageAdded = result.addedFiles.count - addedImages.count
            let nonFrameworkAdded = result.addedFiles.filter { !$0.name.contains(".framework/") }.count
            if nonImageAdded > 0 && nonFrameworkAdded > 0 {
                let english = "\(result.addedFiles.count) file\(result.addedFiles.count == 1 ? "" : "s") added in total"
                let italianPrefix = result.addedFiles.count == 1 ? "Aggiunto" : "Aggiunti"
                let italian = "\(italianPrefix) in totale \(result.addedFiles.count) file"
                items.append(localized(english: english, italian: italian, language: language))
            }
        }

        if !result.removedFiles.isEmpty {
            let nonImageRemoved = result.removedFiles.count - removedImages.count
            let nonFrameworkRemoved = result.removedFiles.filter { !$0.name.contains(".framework/") }.count
            if nonImageRemoved > 0 && nonFrameworkRemoved > 0 {
                let english = "\(result.removedFiles.count) file\(result.removedFiles.count == 1 ? "" : "s") removed in total"
                let italianPrefix = result.removedFiles.count == 1 ? "Rimosso" : "Rimossi"
                let italian = "\(italianPrefix) in totale \(result.removedFiles.count) file"
                items.append(localized(english: english, italian: italian, language: language))
            }
        }

        if !result.modifiedFiles.isEmpty {
            let totalSizeIncrease = result.modifiedFiles.reduce(0) { sum, file in
                sum + (file.size2 - file.size1)
            }

            if totalSizeIncrease > 0 {
                let english = "\(result.modifiedFiles.count) file\(result.modifiedFiles.count == 1 ? "" : "s") modified with a net increase of \(ByteCountFormatter.string(fromByteCount: totalSizeIncrease, countStyle: .file))"
                let italian = "Modificati \(result.modifiedFiles.count) file con un aumento netto di \(ByteCountFormatter.string(fromByteCount: totalSizeIncrease, countStyle: .file))"
                items.append(localized(english: english, italian: italian, language: language))
            } else if totalSizeIncrease < 0 {
                let english = "\(result.modifiedFiles.count) file\(result.modifiedFiles.count == 1 ? "" : "s") modified with a net decrease of \(ByteCountFormatter.string(fromByteCount: abs(totalSizeIncrease), countStyle: .file))"
                let italian = "Modificati \(result.modifiedFiles.count) file con una diminuzione netta di \(ByteCountFormatter.string(fromByteCount: abs(totalSizeIncrease), countStyle: .file))"
                items.append(localized(english: english, italian: italian, language: language))
            } else {
                let english = "\(result.modifiedFiles.count) file\(result.modifiedFiles.count == 1 ? "" : "s") modified with no net size change"
                let italian = "Modificati \(result.modifiedFiles.count) file senza variazioni di dimensione"
                items.append(localized(english: english, italian: italian, language: language))
            }
        }

        return items
    }

    private func collectFrameworkSummaries(from file: FileInfo) -> [String: Int64] {
        var summaries: [String: Int64] = [:]

        if file.type == .framework {
            let name = file.name.replacingOccurrences(of: ".framework", with: "")
            if !name.isEmpty {
                summaries[name] = max(summaries[name] ?? 0, file.size)
            }
        }

        if let children = file.subItems {
            for child in children {
                let childSummaries = collectFrameworkSummaries(from: child)
                for (key, value) in childSummaries {
                    summaries[key] = max(summaries[key] ?? 0, value)
                }
            }
        }

        return summaries
    }

    private func localizedCategoryName(for originalName: String, language: ReportLanguage) -> String {
        if originalName == CategoryType.binary.rawValue {
            return language == .english ? "Main app binary" : "Binario principale dell'app"
        }
        return originalName
    }

    private func localized(english: String, italian: String, language: ReportLanguage) -> String {
        language == .english ? english : italian
    }
}
