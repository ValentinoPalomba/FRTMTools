//
//  BinaryCompositionOnDemandSection.swift
//  FRTMTools
//
//  Created by Claude Code
//

import SwiftUI

struct BinaryCompositionOnDemandSection: View {
    let binaryURL: URL
    let appBundleURL: URL?
    @Environment(\.theme) private var theme

    @State private var state: AnalysisState = .idle
    @State private var composition: BinaryComposition?
    @State private var errorMessage: String?

    private enum AnalysisState: Equatable {
        case idle
        case analyzing
        case completed
        case failed

        var iconName: String {
            switch self {
            case .idle: return "cube.transparent"
            case .analyzing: return "clock.arrow.2.circlepath"
            case .completed: return "checkmark.circle"
            case .failed: return "xmark.circle"
            }
        }

        var accentColor: Color {
            switch self {
            case .idle: return .accentColor
            case .analyzing: return .orange
            case .completed: return .green
            case .failed: return .red
            }
        }

        var description: String {
            switch self {
            case .idle:
                return "Analizza il binario principale per identificare librerie statiche e pacchetti SPM integrati."
            case .analyzing:
                return "Stiamo analizzando i simboli del binario, potrebbe richiedere qualche secondo."
            case .completed:
                return "Analisi completata. Puoi esplorare i moduli rilevati di seguito."
            case .failed:
                return "Si è verificato un errore durante l'analisi. Riprova."
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
                Text("Binary Composition")
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
            case .analyzing:
                placeholder(showProgress: true)
            case .completed:
                if let composition = composition {
                    BinaryCompositionView(composition: composition)
                }
            case .failed:
                failedView
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Questa analisi estrae simboli dal binario per stimare le dimensioni delle librerie integrate.")
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
        case .idle: return "On-Demand"
        case .analyzing: return "Analisi"
        case .completed: return "Completata"
        case .failed: return "Errore"
        }
    }

    private func placeholder(showProgress: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(showProgress ? "Analisi in corso..." : "Analisi su richiesta")
                    .font(.headline)
                Text("Premi il pulsante per analizzare la composizione del binario principale.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if showProgress {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Estrazione simboli e analisi moduli...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                CTAButton(title: "Avvia analisi", systemImage: "play.circle.fill") {
                    startAnalysis()
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

    private var failedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Analisi fallita")
                    .font(.headline)
                    .foregroundStyle(.red)
                if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            CTAButton(title: "Riprova", systemImage: "arrow.clockwise.circle.fill") {
                startAnalysis()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.12),
                            Color.red.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.red.opacity(0.3))
        )
    }

    private func startAnalysis() {
        guard state != .analyzing else { return }
        state = .analyzing
        errorMessage = nil

        Task {
            let analyzer = StaticLibraryAnalyzer()
            let result = await analyzer.analyze(binaryURL: binaryURL, appBundleURL: appBundleURL)

            await MainActor.run {
                if let result = result {
                    composition = result
                    state = .completed
                } else {
                    errorMessage = "Impossibile analizzare il binario. Verifica che il file esista e sia un binario Mach-O valido."
                    state = .failed
                }
            }
        }
    }
}

// MARK: - CTA Button

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
