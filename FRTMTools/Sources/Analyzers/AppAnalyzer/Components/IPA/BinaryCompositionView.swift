//
//  BinaryCompositionView.swift
//  FRTMTools
//
//  Created by Claude Code
//

import SwiftUI

struct BinaryCompositionView: View {
    let composition: BinaryComposition
    @Environment(\.theme) private var theme

    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            summarySection
            Divider()

            if !composition.analysisWarnings.isEmpty {
                warningsSection
            }

            segmentChart
            Divider()

            if !composition.staticModules.isEmpty {
                staticModulesSection
                Divider()
            }

            if !composition.spmPackages.isEmpty {
                spmPackagesSection
                Divider()
            }

            if !composition.systemFrameworks.isEmpty {
                systemFrameworksSection
            }
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                summaryItem(
                    title: "Binary Size",
                    value: byteFormatter.string(fromByteCount: composition.totalSize),
                    icon: "doc.fill"
                )

                summaryItem(
                    title: "Static Modules",
                    value: "\(composition.staticModuleCount)",
                    icon: "archivebox",
                    tint: .orange
                )

                summaryItem(
                    title: "SPM Packages",
                    value: "\(composition.spmPackageCount)",
                    icon: "shippingbox",
                    tint: .blue
                )

                summaryItem(
                    title: "System APIs",
                    value: "\(composition.systemFrameworks.count)",
                    icon: "gearshape.2",
                    tint: .gray
                )
            }

            HStack(spacing: 16) {
                if composition.isEncrypted {
                    statusBadge(text: "Encrypted", icon: "lock.fill", color: .orange)
                }
                if composition.isStripped {
                    statusBadge(text: "Stripped", icon: "scissors", color: .yellow)
                }
                if !composition.isEncrypted && !composition.isStripped {
                    statusBadge(text: "Decrypted", icon: "lock.open.fill", color: .green)
                }
            }
        }
    }

    private func summaryItem(title: String, value: String, icon: String, tint: Color = .accentColor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBadge(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.4))
        )
        .foregroundStyle(color)
    }

    // MARK: - Warnings Section

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(composition.analysisWarnings, id: \.self) { warning in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(warning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.yellow.opacity(0.1))
        )
    }

    // MARK: - Segment Chart

    private var segmentChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Segment Breakdown")
                .font(.headline)

            if composition.segments.isEmpty {
                Text("No segments found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                GeometryReader { geometry in
                    let totalSize = composition.segments.reduce(0) { $0 + $1.size }
                    HStack(spacing: 2) {
                        ForEach(composition.segments) { segment in
                            let proportion = totalSize > 0 ? CGFloat(segment.size) / CGFloat(totalSize) : 0
                            let width = max(proportion * geometry.size.width, 20)

                            VStack(spacing: 4) {
                                Rectangle()
                                    .fill(segmentColor(for: segment.name))
                                    .frame(width: width, height: 24)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                Text(segment.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(height: 50)

                // Legend
                FlowLayout(spacing: 12) {
                    ForEach(composition.segments) { segment in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(segmentColor(for: segment.name))
                                .frame(width: 8, height: 8)
                            Text("\(segment.name): \(byteFormatter.string(fromByteCount: segment.size))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func segmentColor(for name: String) -> Color {
        switch name {
        case "__TEXT": return .blue
        case "__DATA", "__DATA_CONST": return .green
        case "__LINKEDIT": return .orange
        case "__OBJC_CONST", "__OBJC_RO": return .purple
        default: return .gray
        }
    }

    // MARK: - Static Modules Section

    private var staticModulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "archivebox")
                    .foregroundStyle(.orange)
                Text("Static Modules")
                    .font(.headline)
                Spacer()
                Text("\(composition.staticModules.count) modules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let totalSize = composition.staticModules.reduce(0) { $0 + $1.estimatedSize }
            if totalSize > 0 {
                Text("Estimated Total: \(byteFormatter.string(fromByteCount: totalSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 6) {
                ForEach(composition.staticModules) { module in
                    StaticModuleRow(module: module, byteFormatter: byteFormatter)
                }
            }
        }
    }

    // MARK: - SPM Packages Section

    private var spmPackagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.blue)
                Text("SPM Packages")
                    .font(.headline)
                Spacer()
                Text("\(composition.spmPackages.count) packages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let totalSPMSize = composition.spmPackages.reduce(0) { $0 + $1.size }
            if totalSPMSize > 0 {
                Text("Total: \(byteFormatter.string(fromByteCount: totalSPMSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 6) {
                ForEach(composition.spmPackages) { pkg in
                    SPMPackageRow(package: pkg, byteFormatter: byteFormatter)
                }
            }
        }
    }

    // MARK: - System Frameworks Section

    private var systemFrameworksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gearshape.2")
                    .foregroundStyle(.gray)
                Text("System Frameworks")
                    .font(.headline)
                Spacer()
                Text("\(composition.systemFrameworks.count) frameworks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(composition.systemFrameworks, id: \.self) { framework in
                    Text(framework)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.gray.opacity(0.15))
                        )
                }
            }
        }
    }
}

// MARK: - SPM Package Row

private struct SPMPackageRow: View {
    let package: SPMPackageInfo
    let byteFormatter: ByteCountFormatter
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(package.name)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Text(package.size > 0 ? package.sizeText : "—")
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(package.size > 0 ? .primary : .secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.palette.surface.opacity(0.5))
        )
    }
}

// MARK: - Static Module Row

private struct StaticModuleRow: View {
    let module: StaticModuleInfo
    let byteFormatter: ByteCountFormatter
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox")
                .font(.body)
                .foregroundStyle(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(module.symbolCount) symbols")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(module.estimatedSize > 0 ? module.sizeText : "—")
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(module.estimatedSize > 0 ? .primary : .secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.palette.surface.opacity(0.5))
        )
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func flowLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}
