//
//  ExpandableGraphView.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 29/09/25.
//

import SwiftUI

struct ExpandableGraphView: View {
    var analysis: IPAAnalysis
    @State private var isShowingDetail: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Treemap Overview")
                    .font(.title3).bold()
                Spacer()
                Button(action: { isShowingDetail.toggle() }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)

                }
                .buttonStyle(.plain)
            }

            TreemapAnalysisView(root: analysis.rootFile)
                .frame(height: 300)

            TreemapLegendView()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .padding()
        .sheet(isPresented: $isShowingDetail) {
            ExpandedDetailView(analysis: analysis, isShowingDetail: $isShowingDetail)
        }
    }
}

private struct ExpandedDetailView: View {
    var analysis: IPAAnalysis
    @Binding var isShowingDetail: Bool

    var body: some View {
            VStack {
                HStack {
                    Text("Treemap Detail")
                        .font(.title2).bold()
                    Spacer()
                    Button(action: { isShowingDetail = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                
                TreemapAnalysisView(root: analysis.rootFile)
                
                TreemapLegendView()
                    .padding()
            }
            .padding()
            .frame(minWidth: 1200, minHeight: 800)
            .background(Color(NSColor.controlBackgroundColor))
    }
}

