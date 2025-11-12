//
//  ABIAnalyzer.swift
//  FRTMTools
//
//

import Foundation

/// Analyzes Application Binary Interfaces (ABIs) in APK
class ABIAnalyzer {

    /// Generates ABI information from APK analysis
    /// - Parameter analysis: The APK analysis
    /// - Returns: Tuple containing ABI count and list
    static func analyzeABIs(from analysis: APKAnalysis) -> (count: Int, list: [String]) {
        guard let abis = analysis.supportedABIs else {
            return (0, [])
        }

        return (abis.count, abis)
    }

    /// Returns human-readable description of ABIs
    /// - Parameter abis: List of ABI identifiers
    /// - Returns: Formatted description string
    static func description(for abis: [String]) -> String {
        let descriptions = abis.map { abi -> String in
            switch abi {
            case "armeabi-v7a":
                return "ARMv7 (32-bit)"
            case "arm64-v8a":
                return "ARMv8 (64-bit)"
            case "x86":
                return "x86 (32-bit)"
            case "x86_64":
                return "x86-64 (64-bit)"
            default:
                return abi
            }
        }

        return descriptions.joined(separator: ", ")
    }
}
