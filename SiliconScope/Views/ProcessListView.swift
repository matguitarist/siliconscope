import SwiftUI

struct ProcessListView: View {
    let model: AppModel
    @State private var processes: [ProcessItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\ProcessItem.architecture)]
    @State private var selection: Set<ProcessItem.ID> = []
    @State private var statusFilter: Architecture?
    @AppStorage(Preferences.listViewMode) private var viewMode = ListViewMode.table
    @AppStorage(Preferences.refreshProcesses) private var refreshProcesses = false
    @State private var expandedGroups: Set<Architecture> = Set(Architecture.allCases)
    /// Processes waiting for the person to confirm quitting them.
    @State private var processesPendingQuit: [ProcessItem] = []
    @State private var quitErrorMessage: String?

    private var filteredProcesses: [ProcessItem] {
        var base = processes
        if let statusFilter {
            base = base.filter { $0.architecture == statusFilter }
        }
        if !searchText.isEmpty {
            base = base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return base.sorted(using: sortOrder)
    }

    private var groupedProcesses: [(architecture: Architecture, items: [ProcessItem])] {
        let groups = Dictionary(grouping: filteredProcesses, by: \.architecture)
        return Architecture.allCases.compactMap { architecture in
            guard let items = groups[architecture], !items.isEmpty else { return nil }
            let sorted = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return (architecture, sorted)
        }
    }

    private var translatedCount: Int { processes.filter(\.isTranslated).count }
    private var nativeCount: Int { processes.filter { $0.architecture == .appleSilicon }.count }

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            Divider()
            content
        }
        .navigationTitle("Running Processes")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter processes")
        .toolbar {
            ToolbarItem {
                Picker("View", selection: $viewMode) {
                    ForEach(ListViewMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.symbolName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Show as a table (⌃⌘1) or grouped by architecture (⌃⌘2)")
            }
            ToolbarItem {
                Button {
                    Task { await loadProcesses() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
                .help("Rescan running processes (⌘R)")
            }
        }
        .task(id: refreshProcesses) {
            await loadProcesses()
            while refreshProcesses, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await loadProcesses(quietly: true)
            }
        }
        .onChange(of: model.processRefreshRequest) {
            Task { await loadProcesses() }
        }
        .confirmationDialog(
            quitTitle,
            isPresented: Binding(
                get: { !processesPendingQuit.isEmpty },
                set: { if !$0 { processesPendingQuit = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Quit", role: .destructive) {
                quit(processesPendingQuit)
            }
            Button("Cancel", role: .cancel) {
                processesPendingQuit = []
            }
        } message: {
            Text(quitMessage)
        }
        .alert(
            "Couldn't Quit Process",
            isPresented: Binding(
                get: { quitErrorMessage != nil },
                set: { if !$0 { quitErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { quitErrorMessage = nil }
        } message: {
            Text(quitErrorMessage ?? "")
        }
    }

    private var quitTitle: String {
        if processesPendingQuit.count == 1, let process = processesPendingQuit.first {
            return "Quit \(process.name)?"
        }
        return "Quit \(processesPendingQuit.count) Processes?"
    }

    private var quitMessage: String {
        if processesPendingQuit.count == 1, let process = processesPendingQuit.first {
            return "This sends a terminate signal to \(process.name) (PID \(process.id)). Unsaved work in that process may be lost."
        }
        return "This sends a terminate signal to \(processesPendingQuit.map(\.name).formatted(.list(type: .and))). Unsaved work in them may be lost."
    }

    /// The context menu for the clicked row, or for every selected row.
    @ViewBuilder
    private func actions(for ids: Set<ProcessItem.ID>) -> some View {
        let selected = processes.filter { ids.contains($0.id) }
        if !selected.isEmpty {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(selected.map { URL(fileURLWithPath: $0.path) })
            }
            Button(selected.count == 1 ? "Copy Path" : "Copy Paths") {
                FileActions.copyToPasteboard(selected.map(\.path).joined(separator: "\n"))
            }
            Divider()
            Button(selected.count == 1 ? "Quit Process…" : "Quit \(selected.count) Processes…", role: .destructive) {
                processesPendingQuit = selected
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Scanning Processes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if processes.isEmpty {
            ContentUnavailableView("No Processes Found", systemImage: "cpu")
        } else if filteredProcesses.isEmpty {
            ContentUnavailableView("No Matches", systemImage: "line.3.horizontal.decrease.circle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewMode {
            case .table:
                tableView
            case .grouped:
                groupedView
            }
        }
    }

    private var tableView: some View {
        Table(filteredProcesses, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { process in
                HStack(spacing: 8) {
                    Image(systemName: process.isAppBundle ? "app.badge" : "terminal")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(process.name)
                }
            }
            .width(min: 180, ideal: 260)

            TableColumn("Status", value: \.architecture) { process in
                ArchitectureBadge(
                    architecture: process.architecture,
                    overrideLabel: process.isTranslated ? "Rosetta" : nil
                )
            }
            .width(150)

            TableColumn("PID", value: \.id) { process in
                Text("\(process.id)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(60)

            TableColumn("Path", value: \.path) { process in
                Text(process.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .contextMenu(forSelectionType: ProcessItem.ID.self, menu: actions(for:))
    }

    private var groupedView: some View {
        List(selection: $selection) {
            ForEach(groupedProcesses, id: \.architecture) { group in
                DisclosureGroup(isExpanded: expandedBinding(for: group.architecture)) {
                    ForEach(group.items) { process in
                        ProcessRow(process: process)
                            .tag(process.id)
                    }
                } label: {
                    HStack {
                        ArchitectureBadge(
                            architecture: group.architecture,
                            overrideLabel: group.architecture == .intel ? "Running via Rosetta" : nil
                        )
                        Text("\(group.items.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .contextMenu(forSelectionType: ProcessItem.ID.self, menu: actions(for:))
    }

    private func expandedBinding(for architecture: Architecture) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(architecture) },
            set: { isExpanded in
                if isExpanded {
                    expandedGroups.insert(architecture)
                } else {
                    expandedGroups.remove(architecture)
                }
            }
        )
    }

    private var summaryHeader: some View {
        HStack(spacing: 12) {
            SummaryChip(count: translatedCount, label: "Running via Rosetta", tint: .orange, isSelected: statusFilter == .intel) {
                toggleFilter(.intel)
            }
            SummaryChip(count: nativeCount, label: "Native", tint: .green, isSelected: statusFilter == .appleSilicon) {
                toggleFilter(.appleSilicon)
            }
            if statusFilter != nil {
                Button("Clear Filter") { statusFilter = nil }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isLoading {
                Text("\(filteredProcesses.count) of \(processes.count) processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func toggleFilter(_ architecture: Architecture) {
        statusFilter = (statusFilter == architecture) ? nil : architecture
    }

    private func quit(_ targets: [ProcessItem]) {
        processesPendingQuit = []
        var failures: [String] = []
        for process in targets {
            do {
                try ProcessScanner.terminate(pid: process.id)
            } catch {
                failures.append("\(process.name): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            quitErrorMessage = "Couldn't quit " + failures.joined(separator: "\n")
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            await loadProcesses()
        }
    }

    /// `quietly` keeps the current list on screen instead of showing the spinner.
    private func loadProcesses(quietly: Bool = false) async {
        if !quietly { isLoading = true }
        processes = await Task.detached(priority: .userInitiated) {
            ProcessScanner.listProcesses()
        }.value
        isLoading = false
        if !quietly {
            let translated = processes.filter(\.isTranslated)
            AppLog.post(.info, "\(processes.count) processes running, \(translated.count) through Rosetta", source: "Processes")
        }
    }
}

#Preview {
    ProcessListView(model: AppModel())
}
