import SwiftUI

struct ProcessListView: View {
    @State private var processes: [ProcessItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\ProcessItem.architecture)]
    @State private var selection: ProcessItem.ID?
    @State private var statusFilter: Architecture?
    @AppStorage(Preferences.listViewMode) private var viewMode = ListViewMode.table
    @AppStorage(Preferences.refreshProcesses) private var refreshProcesses = false
    @State private var expandedGroups: Set<Architecture> = Set(Architecture.allCases)
    @State private var processPendingQuit: ProcessItem?
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
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button {
                    Task { await loadProcesses() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
                .help("Rescan running processes")
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
        .confirmationDialog(
            "Quit \(processPendingQuit?.name ?? "Process")?",
            isPresented: Binding(
                get: { processPendingQuit != nil },
                set: { if !$0 { processPendingQuit = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let process = processPendingQuit {
                Button("Quit", role: .destructive) {
                    quit(process)
                }
                Button("Cancel", role: .cancel) {
                    processPendingQuit = nil
                }
            }
        } message: {
            if let process = processPendingQuit {
                Text("This sends a terminate signal to \(process.name) (PID \(process.id)). Unsaved work in that process may be lost.")
            }
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
        .contextMenu(forSelectionType: ProcessItem.ID.self) { selectedIDs in
            if let id = selectedIDs.first, let process = processes.first(where: { $0.id == id }) {
                Button("Reveal in Finder") {
                    FileActions.revealInFinder(path: process.path)
                }
                Button("Copy Path") {
                    FileActions.copyToPasteboard(process.path)
                }
                Divider()
                Button("Quit Process…", role: .destructive) {
                    processPendingQuit = process
                }
            }
        }
    }

    private var groupedView: some View {
        List {
            ForEach(groupedProcesses, id: \.architecture) { group in
                DisclosureGroup(isExpanded: expandedBinding(for: group.architecture)) {
                    ForEach(group.items) { process in
                        ProcessRow(process: process) {
                            processPendingQuit = process
                        }
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

    private func quit(_ process: ProcessItem) {
        processPendingQuit = nil
        do {
            try ProcessScanner.terminate(pid: process.id)
            Task {
                try? await Task.sleep(for: .seconds(1))
                await loadProcesses()
            }
        } catch {
            quitErrorMessage = "Couldn't quit \(process.name): \(error.localizedDescription)"
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
    ProcessListView()
}
