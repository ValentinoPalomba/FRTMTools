//
//  Analyzer.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//

import Foundation

protocol Analyzer<T> : Sendable {
    associatedtype T
    func analyze(at url: URL) async throws -> T?
}
