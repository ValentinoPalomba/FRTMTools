//
//  ComparisonViewModel.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 16/09/25.
//

import Foundation

struct ComparisonViewModel<Analysis: AppAnalysis> {
    let analysis1: Analysis
    let analysis2: Analysis

    var fileDiffs: [FileDiff] {
        var diffs: [FileDiff] = []
        
        let allFiles1 = Dictionary(uniqueKeysWithValues: flatten(file: analysis1.rootFile).map { ($0.name, $0.size) })
        let allFiles2 = Dictionary(uniqueKeysWithValues: flatten(file: analysis2.rootFile).map { ($0.name, $0.size) })
        
        let allKeys = Set(allFiles1.keys).union(allFiles2.keys)
        
        for key in allKeys.sorted() {
            let size1 = allFiles1[key] ?? 0
            let size2 = allFiles2[key] ?? 0
            if size1 != size2 {
                diffs.append(FileDiff(name: key, size1: size1, size2: size2))
            }
        }
        
        return diffs
    }
    
    private func flatten(file: FileInfo) -> [FileInfo] {
        var files: [FileInfo] = []
        if let subItems = file.subItems {
            for subItem in subItems {
                files.append(contentsOf: flatten(file: subItem))
            }
        } else {
            files.append(file)
        }
        return files
    }
}
