import SwiftUI
import PeripheryKit
import SourceGraph

struct DeadCodeFilterView: View {
    @Binding var selectedKinds: Set<String>
    @Binding var selectedAccessibilities: Set<Accessibility>
    @Binding var minimumClusterSize: Int
    @Binding var includesIsolatedClusters: Bool
    @Binding var showsOnlyFullyRemovableClusters: Bool
    @Binding var showsOnlyMultiFileClusters: Bool

    private let allKinds: [String] = Array(Set(Declaration.Kind.allCases.map { $0.displayName }.filter { !$0.isEmpty })).sorted()
    private let allAccessibilities: [Accessibility] = Accessibility.allCases.sorted { $0.rawValue < $1.rawValue }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Stepper(
                        "Minimum findings: \(minimumClusterSize)",
                        value: $minimumClusterSize,
                        in: 1...100
                    )
                    Toggle("Include isolated declarations", isOn: $includesIsolatedClusters)
                    Toggle("Deletion candidates only", isOn: $showsOnlyFullyRemovableClusters)
                    Toggle("Multi-file clusters only", isOn: $showsOnlyMultiFileClusters)
                } header: {
                    HStack {
                        Text("Clusters")
                        Spacer()
                        Button("Reset", systemImage: "arrow.counterclockwise") {
                            resetClusterFilters()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Reset cluster filters")
                    }
                } footer: {
                    Text("Declaration filters keep a complete cluster visible when at least one of its findings matches.")
                }

                Section {
                    ForEach(allKinds, id: \.self) { kind in
                        Toggle(kind, isOn: kindBinding(kind))
                    }
                } header: {
                    filterHeader(
                        title: "Declaration Kinds",
                        selectAll: { selectedKinds = Set(allKinds) },
                        clear: { selectedKinds.removeAll() }
                    )
                }

                Section {
                    ForEach(allAccessibilities, id: \.self) { accessibility in
                        Toggle(accessibility.rawValue, isOn: accessibilityBinding(accessibility))
                    }
                } header: {
                    filterHeader(
                        title: "Accessibilities",
                        selectAll: { selectedAccessibilities = Set(allAccessibilities) },
                        clear: { selectedAccessibilities.removeAll() }
                    )
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("Filters")
    }

    private func resetClusterFilters() {
        minimumClusterSize = 1
        includesIsolatedClusters = true
        showsOnlyFullyRemovableClusters = false
        showsOnlyMultiFileClusters = false
    }

    private func kindBinding(_ kind: String) -> Binding<Bool> {
        Binding(
            get: { selectedKinds.contains(kind) },
            set: { isSelected in
                if isSelected {
                    selectedKinds.insert(kind)
                } else {
                    selectedKinds.remove(kind)
                }
            }
        )
    }

    private func accessibilityBinding(_ accessibility: Accessibility) -> Binding<Bool> {
        Binding(
            get: { selectedAccessibilities.contains(accessibility) },
            set: { isSelected in
                if isSelected {
                    selectedAccessibilities.insert(accessibility)
                } else {
                    selectedAccessibilities.remove(accessibility)
                }
            }
        )
    }

    private func filterHeader(
        title: String,
        selectAll: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Menu("Selection", systemImage: "checklist") {
                Button("Select All", action: selectAll)
                Button("Clear", action: clear)
            }
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
            .help("Change \(title.lowercased()) selection")
        }
    }
}
