import SwiftUI

struct DeadCodeDependencyTreeView: View {
    let viewModel: DeadCodeViewModel

    @State private var selectedCluster: DeadCodeDependencyCluster?
    @State private var clusterRemovalPreview: DeadCodeClusterRemovalPreview?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let activity = viewModel.removalActivity {
                DeadCodeRemovalProgressBanner(activity: activity)
            }

            if let message = viewModel.lastRemovalMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.green.opacity(0.1), in: .rect(cornerRadius: 8))
                    .accessibilityLabel("Removal succeeded. \(message)")
            }

            if viewModel.dependencyClusters.isEmpty {
                ContentUnavailableView(
                    "No Matching Clusters",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Adjust the declaration or cluster filters.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                clusterTable
            }
        }
        .sheet(item: $selectedCluster) { cluster in
            DeadCodeClusterDetailSheet(
                cluster: cluster,
                viewModel: viewModel
            )
        }
        .sheet(item: $clusterRemovalPreview) { preview in
            DeadCodeClusterRemovalSheet(
                preview: preview,
                validatesBuild: preview.kind.requiresBuildValidation
                    ? .constant(true)
                    : buildValidationBinding,
                remove: {
                    viewModel.removeCluster(using: preview)
                }
            )
        }
        .onChange(of: viewModel.selectedAnalysisID) {
            selectedCluster = nil
            clusterRemovalPreview = nil
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Dependency Clusters")
                    .font(.title3.bold())
                Text("Compact overview. Open a row only when you need its declaration graph.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.requiresRemovalSafetyRescan {
                Label("Rescan required for safe removal", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .help(
                        "This analysis predates dependency-closure validation. Run a new scan before removing code."
                    )
            } else if viewModel.safeRemovalCandidateCount > 0 {
                Button {
                    requestAllSafeCandidatesRemoval()
                } label: {
                    if viewModel.isPreparingSafeCandidates {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Preparing Preview…")
                        }
                    } else {
                        Label(
                            "Remove All Safe Candidates",
                            systemImage: "trash.slash"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isRemovalInProgress)
                .help(
                    "Validate, preview, and remove up to \(viewModel.safeRemovalCandidateCount) safe findings, then rebuild"
                )
            }

            Label(
                "\(viewModel.dependencyClusters.count) visible",
                systemImage: "square.grid.2x2"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }

    private var clusterTable: some View {
        Table(viewModel.dependencyClusters) {
            TableColumn("Cluster") { cluster in
                Button {
                    selectedCluster = cluster
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: cluster.isLinked ? "point.3.connected.trianglepath.dotted" : "circle")
                            .foregroundStyle(cluster.isLinked ? .orange : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clusterTitle(cluster))
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(cluster.results.first?.name ?? "Unknown declaration")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Open cluster details")
            }
            .width(min: 220, ideal: 320)

            TableColumn("Findings") { cluster in
                Text(cluster.results.count, format: .number)
                    .monospacedDigit()
            }
            .width(70)

            TableColumn("Files") { cluster in
                Text(cluster.fileCount, format: .number)
                    .monospacedDigit()
            }
            .width(55)

            TableColumn("Status") { cluster in
                Label(
                    clusterStatusTitle(cluster),
                    systemImage: clusterStatusImage(cluster)
                )
                .font(.caption)
                .foregroundStyle(
                    cluster.isPotentiallyFullyRemovable
                        ? AnyShapeStyle(.green)
                        : AnyShapeStyle(.secondary)
                )
            }
            .width(min: 105, ideal: 120)

            TableColumn("") { cluster in
                HStack(spacing: 10) {
                    if viewModel.removingClusterID == cluster.id {
                        ProgressView()
                            .controlSize(.small)
                    } else if cluster.isPotentiallyFullyRemovable {
                        Button {
                            requestClusterRemoval(cluster)
                        } label: {
                            Label("Remove Entire Cluster", systemImage: "trash")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .disabled(isRemovalInProgress)
                        .help("Preview and remove the entire cluster")
                    }

                    Button {
                        selectedCluster = cluster
                    } label: {
                        Label("Show Details", systemImage: "arrow.up.right.square")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
            .width(70)
        }
        .frame(height: min(520, max(260, CGFloat(viewModel.dependencyClusters.count * 30 + 42))))
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .dsSurface(.surface, cornerRadius: 12, border: true, shadow: false)
    }

    private var isRemovalInProgress: Bool {
        viewModel.removingClusterID != nil ||
            viewModel.removingFilePath != nil ||
            viewModel.removingGraphID != nil ||
            viewModel.isPreparingSafeCandidates
    }

    private var buildValidationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.validatesBuildAfterRemoval },
            set: { viewModel.validatesBuildAfterRemoval = $0 }
        )
    }

    private func clusterTitle(_ cluster: DeadCodeDependencyCluster) -> String {
        cluster.isLinked
            ? "\(cluster.results.count) linked declarations"
            : "Isolated declaration"
    }

    private func clusterStatusTitle(_ cluster: DeadCodeDependencyCluster) -> String {
        if cluster.retainedReferenceCount > 0 {
            return "Blocked"
        }
        return cluster.isPotentiallyFullyRemovable ? "Candidate" : "Review"
    }

    private func clusterStatusImage(_ cluster: DeadCodeDependencyCluster) -> String {
        if cluster.retainedReferenceCount > 0 {
            return "link.badge.plus"
        }
        return cluster.isPotentiallyFullyRemovable
            ? "checkmark.shield"
            : "exclamationmark.triangle"
    }

    private func requestClusterRemoval(_ cluster: DeadCodeDependencyCluster) {
        do {
            clusterRemovalPreview = try viewModel.clusterRemovalPreview(for: cluster)
        } catch {
            viewModel.error = error
        }
    }

    private func requestAllSafeCandidatesRemoval() {
        Task {
            do {
                clusterRemovalPreview = try await viewModel.allSafeCandidatesRemovalPreview()
            } catch {
                viewModel.error = error
            }
        }
    }
}

private struct DeadCodeClusterDetailSheet: View {
    let cluster: DeadCodeDependencyCluster
    let viewModel: DeadCodeViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var clusterRemovalPreview: DeadCodeClusterRemovalPreview?
    @State private var declarationRemovalPreview: DeadCodeDeclarationRemovalPreview?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Findings", value: "\(cluster.results.count)")
                    LabeledContent("Source files", value: "\(cluster.fileCount)")
                    LabeledContent("References", value: "\(cluster.linkedDeclarationCount)")
                    LabeledContent(
                        "Retained references",
                        value: "\(cluster.retainedReferenceCount)"
                    )
                }

                if cluster.retainedReferenceCount > 0 {
                    Section("Why Removal Is Blocked") {
                        Text(
                            "This closure is still referenced by declarations that Periphery did not mark as removable. FRTMTools will not modify it."
                        )
                        .foregroundStyle(.secondary)

                        ForEach(
                            Array(
                                Set(cluster.results.flatMap(\.externalReferenceLocations))
                            ).sorted(),
                            id: \.self
                        ) { location in
                            Button(location) {
                                DeadCodeSourceNavigator.open(location: location)
                            }
                            .buttonStyle(.plain)
                            .font(.caption.monospaced())
                        }
                    }
                }

                Section("Declaration Graph") {
                    OutlineGroup(cluster.roots, children: \.children) { node in
                        declarationRow(node.result)
                    }
                }
            }
            .navigationTitle(cluster.isLinked ? "Dependency Cluster" : "Isolated Declaration")
            .frame(minWidth: 700, minHeight: 500)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                if cluster.isPotentiallyFullyRemovable {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Remove Entire Cluster", systemImage: "trash", role: .destructive) {
                            requestClusterRemoval()
                        }
                        .disabled(viewModel.removalActivity != nil)
                    }
                }
            }
        }
        .sheet(item: $clusterRemovalPreview) { preview in
            DeadCodeClusterRemovalSheet(
                preview: preview,
                validatesBuild: preview.kind.requiresBuildValidation
                    ? .constant(true)
                    : buildValidationBinding,
                remove: {
                    viewModel.removeCluster(using: preview)
                    dismiss()
                }
            )
        }
        .sheet(item: $declarationRemovalPreview) { preview in
            DeadCodeDeclarationRemovalSheet(
                preview: preview,
                validatesBuild: buildValidationBinding,
                remove: {
                    viewModel.removeDeclaration(using: preview)
                }
            )
        }
    }

    private func declarationRow(
        _ result: SerializableDeadCodeResult
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                DeadCodeSourceNavigator.open(location: result.location)
            } label: {
                HStack(spacing: 10) {
                    Text(result.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name ?? "Unknown declaration")
                            .lineLimit(1)
                        Text("\(URL(fileURLWithPath: result.filePath).lastPathComponent) · \(result.kind)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !result.externalReferenceLocations.isEmpty {
                            Text(
                                "Blocked by \(result.externalReferenceLocations.count) retained reference" +
                                    "\(result.externalReferenceLocations.count == 1 ? "" : "s")"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if viewModel.allowsSurgicalRemoval(for: result) {
                Button {
                    do {
                        declarationRemovalPreview = try viewModel.declarationRemovalPreview(for: result)
                    } catch {
                        viewModel.error = error
                    }
                } label: {
                    Label("Remove Declaration", systemImage: "scissors")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .disabled(viewModel.removalActivity != nil)
            } else {
                Label(result.remediation.title, systemImage: result.remediation.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func requestClusterRemoval() {
        do {
            clusterRemovalPreview = try viewModel.clusterRemovalPreview(for: cluster)
        } catch {
            viewModel.error = error
        }
    }

    private var buildValidationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.validatesBuildAfterRemoval },
            set: { viewModel.validatesBuildAfterRemoval = $0 }
        )
    }
}

private struct DeadCodeClusterRemovalSheet: View {
    let preview: DeadCodeClusterRemovalPreview
    @Binding var validatesBuild: Bool
    let remove: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: headerSystemImage)
                        .font(.title)
                        .foregroundStyle(.orange)
                        .frame(width: 38)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(headerTitle)
                            .font(.title3.weight(.semibold))
                        Text(headerDescription)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    DeadCodeRemovalMetric(
                        value: "\(preview.declarationCount)",
                        label: "Findings",
                        systemImage: "curlybraces"
                    )
                    DeadCodeRemovalMetric(
                        value: "\(preview.affectedFileCount)",
                        label: "Files",
                        systemImage: "doc.on.doc"
                    )
                    DeadCodeRemovalMetric(
                        value: "\(preview.sourceEdits.count)",
                        label: "Surgical edits",
                        systemImage: "scissors"
                    )
                    DeadCodeRemovalMetric(
                        value: "\(preview.removedFileURLs.count)",
                        label: "Whole files",
                        systemImage: "trash"
                    )
                }

                if preview.skippedCandidateCount > 0 {
                    Label(
                        "\(preview.skippedCandidateCount) potential candidate" +
                            "\(preview.skippedCandidateCount == 1 ? " was" : "s were") excluded because " +
                            "\(preview.skippedCandidateCount == 1 ? "it did" : "they did") not pass the final surgical checks.",
                        systemImage: "checkmark.shield"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 8))
                }

                DeadCodeBuildValidationCard(
                    validatesBuild: $validatesBuild,
                    scheme: preview.scheme,
                    isRequired: preview.kind.requiresBuildValidation
                )

                if preview.kind == .allSafeCandidates {
                    DeadCodeBulkFileSummary(preview: preview)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(preview.diffSections.enumerated()), id: \.offset) { _, diff in
                                Text(diff)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(12)
                    }
                    .background(.black.opacity(0.82), in: .rect(cornerRadius: 10))
                    .foregroundStyle(.white)
                }
            }
            .padding(20)
            .frame(minWidth: 760, minHeight: 520)
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        confirmationTitle,
                        role: .destructive
                    ) {
                        remove()
                        dismiss()
                    }
                }
            }
        }
    }

    private var headerSystemImage: String {
        switch preview.kind {
        case .dependencyCluster: "point.3.connected.trianglepath.dotted"
        case .allSafeCandidates: "trash.square.fill"
        }
    }

    private var headerTitle: String {
        switch preview.kind {
        case .dependencyCluster:
            "Remove the complete dependency cluster?"
        case .allSafeCandidates:
            "Remove all \(preview.declarationCount) validated safe candidates?"
        }
    }

    private var headerDescription: String {
        switch preview.kind {
        case .dependencyCluster:
            "Review the exact source changes and choose whether FRTMTools should validate them with Xcode."
        case .allSafeCandidates:
            "The listed declarations, whole files, and matching Xcode project references will be removed in one operation. The saved scheme is then rebuilt; if it fails, every source and project file is restored."
        }
    }

    private var navigationTitle: String {
        switch preview.kind {
        case .dependencyCluster: "Cluster Removal"
        case .allSafeCandidates: "Safe Candidates Removal"
        }
    }

    private var confirmationTitle: String {
        switch preview.kind {
        case .dependencyCluster:
            validatesBuild ? "Remove and Validate" : "Remove Without Build"
        case .allSafeCandidates:
            "Remove All and Rebuild"
        }
    }
}

private struct DeadCodeBulkFileSummary: View {
    let preview: DeadCodeClusterRemovalPreview

    var body: some View {
        List {
            if !preview.sourceEdits.isEmpty {
                Section("Surgical edits · \(preview.sourceEdits.count)") {
                    ForEach(preview.sourceEdits, id: \.fileURL) { edit in
                        Label(edit.fileURL.lastPathComponent, systemImage: "scissors")
                            .help(edit.fileURL.path)
                    }
                }
            }

            if !preview.removedFileURLs.isEmpty {
                Section("Whole files · \(preview.removedFileURLs.count)") {
                    ForEach(preview.removedFileURLs, id: \.self) { fileURL in
                        Label(fileURL.lastPathComponent, systemImage: "trash")
                            .help(fileURL.path)
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if preview.sourceEdits.isEmpty && preview.removedFileURLs.isEmpty {
                ContentUnavailableView(
                    "No Planned Changes",
                    systemImage: "checkmark.shield"
                )
            }
        }
    }
}

private struct DeadCodeDeclarationRemovalSheet: View {
    let preview: DeadCodeDeclarationRemovalPreview
    @Binding var validatesBuild: Bool
    let remove: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "scissors")
                        .font(.title)
                        .foregroundStyle(.orange)
                        .frame(width: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(preview.declarationName)
                            .font(.title3.weight(.semibold))
                        Text(
                            "\(preview.declarationKind) · \(preview.fileURL.lastPathComponent) · " +
                            "\(preview.removedGraphIDs.count) linked finding\(preview.removedGraphIDs.count == 1 ? "" : "s")"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                DeadCodeBuildValidationCard(
                    validatesBuild: $validatesBuild,
                    scheme: preview.scheme,
                    isRequired: false
                )

                ScrollView([.horizontal, .vertical]) {
                    Text(preview.diff)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(.black.opacity(0.82), in: .rect(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .padding(20)
            .frame(minWidth: 680, minHeight: 440)
            .navigationTitle("Declaration Removal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        validatesBuild ? "Remove and Validate" : "Remove Without Build",
                        role: .destructive
                    ) {
                        remove()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DeadCodeBuildValidationCard: View {
    @Binding var validatesBuild: Bool
    let scheme: String
    let isRequired: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $validatesBuild) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rebuild after removal")
                            .fontWeight(.medium)
                        Text("Scheme: \(scheme)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .toggleStyle(.switch)
                .disabled(isRequired)

                Label(
                    isRequired
                        ? "Build validation is required for bulk removal. If it fails, every removed file is restored automatically."
                        : validatesBuild
                        ? "Changes are kept only if the test build succeeds. On failure, every affected source is restored automatically."
                        : "Faster, but the change is not compiled. FRTMTools keeps the edited sources and you should rebuild manually.",
                    systemImage: validatesBuild ? "checkmark.shield" : "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(validatesBuild ? Color.secondary : Color.orange)
            }
            .padding(4)
        } label: {
            Label("Build Validation", systemImage: "hammer")
        }
    }
}

private struct DeadCodeRemovalMetric: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
    }
}

private struct DeadCodeRemovalProgressBanner: View {
    let activity: DeadCodeRemovalActivity

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.statusTitle)
                    .font(.callout.weight(.semibold))
                Text(activity.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if activity.stage == .rebuilding {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Label(
                        "Xcode · \(elapsedTime(at: timeline.date))",
                        systemImage: "hammer.fill"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
                    .monospacedDigit()
                }
            }
        }
        .padding(12)
        .background(.blue.opacity(0.09), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.blue.opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.statusTitle) \(activity.statusDetail)")
    }

    private func elapsedTime(at date: Date) -> String {
        let elapsed = max(0, Int(date.timeIntervalSince(activity.stageStartedAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return minutes > 0
            ? "\(minutes)m \(seconds)s"
            : "\(seconds)s"
    }
}

enum DeadCodeSourceNavigator {
    static func open(location: String) {
        let components = location.split(separator: ":")
        guard components.count >= 2,
              let line = Int(components[components.count - 2]) else {
            return
        }

        let path = components.dropLast(2).joined(separator: ":")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xed")
        process.arguments = ["-l", "\(line)", path]
        try? process.run()
    }
}
