//
//  Analyzer.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//

import Foundation

protocol Analyzer<T> {
    associatedtype T
    func analyze(at url: URL) async throws -> T?
}
