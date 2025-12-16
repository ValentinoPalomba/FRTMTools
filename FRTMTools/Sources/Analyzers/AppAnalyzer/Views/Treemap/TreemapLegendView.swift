//
//  TreemapLegendView.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 29/09/25.
//

import SwiftUI
struct TreemapLegendView: View {
    var body: some View {
        HStack(spacing: 16) {
            LegendItem(color: .treemapAppBinary, name: "App/Binary")
            LegendItem(color: .treemapFramework, name: "Framework")
            LegendItem(color: .treemapBundle, name: "Bundle")
            LegendItem(color: .treemapAssets, name: "Assets")
            LegendItem(color: .treemapLproj, name: "Lproj")
            LegendItem(color: .treemapPlist, name: "Plist")
            LegendItem(color: .treemapDefault, name: "Other")
        }
        .padding(.top, 8)
    }
}

struct LegendItem: View {
    let color: Color
    let name: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(name)
                .font(.caption)
        }
    }
}
