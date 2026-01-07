import SwiftUI

struct DependencyGraphOnDemandSection: View {
    let graph: DependencyGraph
    @Environment(\.theme) private var theme

    @State private var renderToken = UUID()
    @State private var state: GraphRenderingState = .idle

    private enum GraphRenderingState: Equatable {
        case idle
        case preparing
        case visible

        var iconName: String {
            switch self {
            case .idle: return "bolt.horizontal.circle"
            case .preparing: return "clock.arrow.2.circlepath"
            case .visible: return "rectangle.connected.to.line.below"
            }
        }

        var accentColor: Color {
            switch self {
            case .idle: return .accentColor
            case .preparing: return .orange
            case .visible: return .green
            }
        }

        var description: String {
            switch self {
            case .idle:
                return "Genera il grafo solo quando ti serve per mantenere la schermata leggera."
            case .preparing:
                return "Stiamo preparando il layout, rimani su questa schermata."
            case .visible:
                return "Il grafo è attivo: puoi esplorarlo, rigenerarlo o nasconderlo."
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            Divider()
            content
            footer
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.palette.border)
        )
        .shadow(color: theme.palette.shadow.opacity(theme.colorScheme == .dark ? 0.25 : 0.08), radius: 6, x: 0, y: 3)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                state.accentColor.opacity(0.25),
                                state.accentColor.opacity(0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: state.iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("Dependency Graph")
                    .font(.title3.bold())
                Text(state.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge
        }
    }

    private var content: some View {
        Group {
            switch state {
            case .idle:
                placeholder()
            case .preparing:
                placeholder(showProgress: true)
            case .visible:
                graphView
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Il rendering del grafo può diventare pesante su IPA molto grandi. Usalo solo quando necessario.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.accentColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(state.accentColor.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(state.accentColor.opacity(0.4))
        )
    }

    private var statusLabel: String {
        switch state {
        case .idle: return "On‑Demand"
        case .preparing: return "Preparazione"
        case .visible: return "Attivo"
        }
    }

    private func placeholder(showProgress: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(showProgress ? "Sto preparando il grafo..." : "Grafo su richiesta")
                    .font(.headline)
                Text("Premi il pulsante per generare le dipendenze quando sei pronto.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if showProgress {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Calcolo nodi e layout…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                CTAButton(title: "Genera grafo", systemImage: "play.circle.fill") {
                    prepareGraph()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.12),
                            Color.accentColor.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.3))
        )
    }

    private var graphView: some View {
        VStack(spacing: 16) {
            DependencyGraphView(graph: graph)
                .id(renderToken)
                .frame(height: 600)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.palette.border)
                )

            HStack(spacing: 12) {
                CTAButton(title: "Rigenera layout", systemImage: "arrow.triangle.2.circlepath") {
                    reloadLayout()
                }

                Button {
                    hideGraph()
                } label: {
                    Label("Nascondi grafico", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private func prepareGraph() {
        guard state == .idle else { return }
        state = .preparing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            renderToken = UUID()
            state = .visible
        }
    }

    private func hideGraph() {
        withAnimation(.easeInOut(duration: 0.25)) {
            state = .idle
        }
    }

    private func reloadLayout() {
        renderToken = UUID()
    }
}

private struct CTAButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
