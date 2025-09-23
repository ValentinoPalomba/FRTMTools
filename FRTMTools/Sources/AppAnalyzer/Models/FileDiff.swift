//
//  FileDiff.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//


import Foundation

struct FileDiff: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let size1: Int64
    let size2: Int64
}
