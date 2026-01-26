//
//  ExpandableGraphView.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 29/09/25.
//

import SwiftUI

struct ExpandableGraphView<Analysis: AppAnalysis>: View {
    var analysis: Analysis
    @State private var isShowingDetail: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Treemap Overview")
                    .font(.title3).bold()
                Spacer()
                Button(action: { isShowingDetail.toggle() }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(theme.palette.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(theme.palette.border))
                        .shadow(color: theme.palette.shadow.opacity(theme.colorScheme == .dark ? 0.22 : 0.10), radius: 3, x: 0, y: 2)

                }
                .buttonStyle(.plain)
            }

            let baseURL: URL? = {
                let appURL = analysis.url
                let fm = FileManager.default
                var isDir: ObjCBool = false
                let contents = appURL.appendingPathComponent("Contents")
                if fm.fileExists(atPath: contents.path, isDirectory: &isDir), isDir.boolValue {
                    return contents // macOS bundle layout
                }
                // Fallback: use appURL even if it may not currently exist on disk
                return appURL
            }()

            TreemapAnalysisView(root: analysis.rootFile, baseURL: baseURL)
                .frame(height: 300)

            TreemapLegendView()
        }
        .padding()
        .dsSurface(.surface, cornerRadius: 16, border: true, shadow: false)
        .padding()
        .sheet(isPresented: $isShowingDetail) {
            ExpandedDetailView(analysis: analysis, isShowingDetail: $isShowingDetail)
        }
    }
}

private struct ExpandedDetailView<Analysis: AppAnalysis>: View {
    var analysis: Analysis
    @Binding var isShowingDetail: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let baseURL: URL? = {
            let appURL = analysis.url
            let fm = FileManager.default
            var isDir: ObjCBool = false
            let contents = appURL.appendingPathComponent("Contents")
            if fm.fileExists(atPath: contents.path, isDirectory: &isDir), isDir.boolValue {
                return contents // macOS bundle layout
            }
            // Fallback: use appURL even if it may not currently exist on disk
            return appURL
        }()

        return VStack {
            HStack {
                Text("Treemap Detail")
                    .font(.title2).bold()
                Spacer()
                Button(action: { isShowingDetail = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            TreemapAnalysisView(root: analysis.rootFile, baseURL: baseURL)
            
            TreemapLegendView()
                .padding()
        }
        .padding()
        .frame(minWidth: 1200, minHeight: 800)
        .background(theme.palette.background)
    }
}
