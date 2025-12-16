import SwiftUI
import PeripheryKit
import SourceGraph

struct DeadCodeFilterView: View {
    @Binding var selectedKinds: Set<String>
    @Binding var selectedAccessibilities: Set<Accessibility>

    let allKinds: [String] = Array(Set(Declaration.Kind.allCases.map { $0.displayName }.filter { !$0.isEmpty })).sorted()
    let allAccessibilities: [Accessibility] = Accessibility.allCases.sorted { $0.rawValue < $1.rawValue }

    let columns = [GridItem(.adaptive(minimum: 150))]

    var body: some View {
        VStack(spacing: 0) {
            Text("Filters")
                .font(.title2)
                .bold()
                .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Kinds Section
                    VStack(alignment: .leading) {
                        Text("Declaration Kinds")
                            .font(.headline)
                        HStack {
                            Button("Select All") { selectedKinds = Set(allKinds) }
                            Button("Deselect All") { selectedKinds.removeAll() }
                        }
                        .padding(.bottom, 8)

                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(allKinds, id: \.self) { kind in
                                Toggle(kind, isOn: Binding(
                                    get: { selectedKinds.contains(kind) },
                                    set: { isOn in
                                        if isOn {
                                            selectedKinds.insert(kind)
                                        } else {
                                            selectedKinds.remove(kind)
                                        }
                                    }
                                ))
                                .toggleStyle(.button)
                            }
                        }
                    }

                    Divider().padding(.vertical)

                    // Accessibilities Section
                    VStack(alignment: .leading) {
                        Text("Accessibilities")
                            .font(.headline)
                        HStack {
                            Button("Select All") { selectedAccessibilities = Set(allAccessibilities) }
                            Button("Deselect All") { selectedAccessibilities.removeAll() }
                        }
                        .padding(.bottom, 8)

                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(allAccessibilities, id: \.self) { accessibility in
                                Toggle(accessibility.rawValue, isOn: Binding(
                                    get: { selectedAccessibilities.contains(accessibility) },
                                    set: { isOn in
                                        if isOn {
                                            selectedAccessibilities.insert(accessibility)
                                        } else {
                                            selectedAccessibilities.remove(accessibility)
                                        }
                                    }
                                ))
                                .toggleStyle(.button)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
    }
}