//
//  LoaderView.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//


import SwiftUI

/// LoaderView: elegante loader stile Apple per macOS
/// Usage:
/// - Indeterminate: LoaderView(style: .indeterminate, title: "Analyzing…")
/// - Determinate: LoaderView(style: .determinate(progress: bindingDouble), title: "Uploading…")
public struct LoaderView: View {
    public enum Style: Equatable {
        case indeterminate
        case determinate(progress: Double) // 0.0...1.0
    }

    // Public API
    public var style: Style
    public var title: String?
    public var subtitle: String?
    public var showsCancel: Bool = false
    public var cancelAction: (() -> Void)? = nil

    // Visual tuning
    private let cardWidth: CGFloat = 420
    private let cardHeight: CGFloat = 160
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1
    @State private var sparklesPhase: Double = 0
    @Environment(\.theme) private var theme

    public init(style: Style = .indeterminate,
                title: String? = nil,
                subtitle: String? = nil,
                showsCancel: Bool = false,
                cancelAction: (() -> Void)? = nil) {
        self.style = style
        self.title = title
        self.subtitle = subtitle
        self.showsCancel = showsCancel
        self.cancelAction = cancelAction
    }

    public var body: some View {
        ZStack {
            // blurred vignette behind
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                .ignoresSafeArea()
                .opacity(0.60)

            content
                .frame(width: cardWidth, height: cardHeight)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(theme.palette.border.opacity(theme.colorScheme == .dark ? 0.22 : 0.50), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 10)
                .padding(24)
                .onAppear {
                    withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        pulse = 1.04
                    }
                    withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                        sparklesPhase = 0.5
                    }
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? "Loading")
        .accessibilityHint(subtitle ?? "")
    }

    private var content: some View {
        HStack(spacing: 18) {
            ZStack {
                // soft background ring
                Circle()
                    .stroke(lineWidth: 8)
                    .opacity(0.06)
                    .frame(width: 86, height: 86)

                // main ring
                switch style {
                case .indeterminate:
                    IndeterminateRing(size: 86)
                        .scaleEffect(pulse)
                        .rotationEffect(.degrees(rotation))
                case .determinate(let progress):
                    DeterminateRing(progress: progress, size: 86)
                }

                // subtle centered icon
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [theme.palette.accent, theme.palette.accent.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(0.9)
            }
            .frame(width: 110)

            VStack(alignment: .center, spacing: 6) {
                if let title {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    // small description based on mode
                    Text(modeDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    if case .determinate(let p) = style {
                        Text("\(Int((p * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if showsCancel, let cancelAction {
                        Button(role: .cancel) {
                            cancelAction()
                        } label: {
                            Text("Cancel")
                                .font(.callout.weight(.medium))
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }

                    Spacer()
                }
            }
            .padding(.vertical, 6)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var modeDescription: String {
        switch style {
        case .indeterminate:
            return "Preparing and analyzing files…"
        case .determinate:
            return "Working…"
        }
    }
}

// MARK: - Indeterminate Ring
private struct IndeterminateRing: View {
    let size: CGFloat
    @State private var trimEnd: CGFloat = 0.2
    @State private var trimStart: CGFloat = 0.0
    @State private var forward = true
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Circle()
                .trim(from: trimStart, to: trimEnd)
                .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
                .foregroundStyle(AngularGradient(gradient: Gradient(colors: [theme.palette.accent.opacity(1), theme.palette.accent.opacity(0.25), theme.palette.accent.opacity(1)]), center: .center))
                .onAppear {
                    animate()
                }
        }
    }

    private func animate() {
        let base = Animation.easeInOut(duration: 1.1)
        withAnimation(base.repeatForever(autoreverses: true)) {
            trimEnd = 0.85
        }
        withAnimation(base.delay(0.2).repeatForever(autoreverses: true)) {
            trimStart = 0.6
        }
    }
}

// MARK: - Determinate Ring
private struct DeterminateRing: View {
    var progress: Double // 0...1
    let size: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 8)
                .opacity(0.06)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: CGFloat(max(0.001, min(1, progress))))
                .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
                .animation(.easeInOut(duration: 0.35), value: progress)
                .foregroundStyle(LinearGradient(
                    colors: [theme.palette.accent, theme.palette.accent.opacity(0.65)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
                )
        }
    }
}

// MARK: - Sparkles overlay
struct SparklesOverlay: View {
    var phase: Double // 0..1
    var count = 6
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let angle = (Double(i) / Double(count)) * 2 * Double.pi + phase * 2 * Double.pi
                    let r = 12.0 + sin(phase * 2 * Double.pi + Double(i)) * 4.0
                    Circle()
                        .frame(width: 6, height: 6)
                        .opacity(0.6 - Double(i) * 0.06)
                        .offset(x: CGFloat(cos(angle) * r), y: CGFloat(sin(angle) * r))
                        .scaleEffect(0.9 + CGFloat(sin(phase * 2 * .pi + Double(i)) * 0.12))
                        .blur(radius: 0.25)
                        .foregroundStyle(LinearGradient(colors: [theme.palette.accent.opacity(0.9), theme.palette.accent.opacity(0.15)], startPoint: .top, endPoint: .bottom))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - VisualEffectBlur for macOS (wrapper)
fileprivate struct VisualEffectBlur: NSViewRepresentable {
    typealias NSViewType = NSVisualEffectView

    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Preview
struct LoaderView_Previews: PreviewProvider {
    static var previews: some View {
        let lightTheme = Theme.fallback(colorScheme: .light)
        let darkTheme = Theme.fallback(colorScheme: .dark)

        Group {
            ZStack {
                lightTheme.palette.background
                    .ignoresSafeArea()
                LoaderView(style: .indeterminate, title: "Analyzing IPA", subtitle: "This can take a few seconds…", showsCancel: true) {
                    print("Cancel tapped")
                }
            }
            .previewDisplayName("Indeterminate")
            .environment(\.theme, lightTheme)

            ZStack {
                darkTheme.palette.background
                    .ignoresSafeArea()
                LoaderView(style: .determinate(progress: 0.42), title: "Uploading", subtitle: "Preparing data…", showsCancel: true)
            }
            .previewDisplayName("Determinate")
            .environment(\.theme, darkTheme)
        }
        .frame(width: 600, height: 300)
    }
}

import SwiftUI

struct LoaderOverlayModifier<LoaderContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let loaderContent: () -> LoaderContent

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        // Dark semi-transparent backdrop
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .transition(.opacity)
                        
                        // Loader content
                        loaderContent()
                            .transition(.scale.combined(with: .opacity))
                    }
                    .animation(.easeInOut(duration: 0.25), value: isPresented)
                }
                
                
            }
    }
}

extension View {
    func loaderOverlay<LoaderContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> LoaderContent
    ) -> some View {
        self.modifier(LoaderOverlayModifier(isPresented: isPresented, loaderContent: content))
    }
}
