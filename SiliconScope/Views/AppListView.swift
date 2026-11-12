import SwiftUI

enum ListViewMode: String, CaseIterable, Identifiable {
    case table = "Table"
    case grouped = "Grouped"
    var id: String { rawValue }
}

struct AppListView: View {
    @State private var apps: [AppItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\AppItem.architecture)]
    @State private var selection: AppItem.ID?
    @State private var architectureFilter: Architecture?
    @State private var viewMode: ListViewMode = .table
    @State private var expandedGroups: Set<Architecture> = Set(Architecture.allCases)

    private var filteredApps: [AppItem] {
        var base = apps
        if let architectureFilter {
            base = base.filter { $0.architecture == architectureFilter }
        }
        if !searchText.isEmpty {
            base = base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return base.sorted(using: sortOrder)
    }

    private var groupedApps: [(architecture: Architecture, items: [AppItem])] {
        let groups = Dictionary(grouping: filteredApps, by: \.architecture)
        return Architecture.allCases.compactMap { architecture in
            guard let items = groups[architecture], !items.isEmpty else { return nil }
            let sorted = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return (architecture, sorted)
        }
    }

    private var intelCount: Int { apps.filter { $0.architecture == .intel }.count }
    private var universalCount: Int { apps.filter { $0.architecture == .universal }.count }
    private var appleSiliconCount: Int { apps.filter { $0.architecture == .appleSilicon }.count }

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            Divider()
            content
        }
        .navigationTitle("Installed Apps")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter apps")
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
                    Task { await loadApps() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
                .help("Rescan /Applications")
            }
        }
        .task {
            await loadApps()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Scanning Applications…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if apps.isEmpty {
            ContentUnavailableView("No Applications Found", systemImage: "app.dashed")
        } else if filteredApps.isEmpty {
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
        Table(filteredApps, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { app in
                HStack(spacing: 8) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(app.name)
                }
            }
            .width(min: 180, ideal: 260)

            TableColumn("Architecture", value: \.architecture) { app in
                ArchitectureBadge(architecture: app.architecture)
            }
            .width(150)

            TableColumn("Version", value: \.versionSortKey) { app in
                Text(app.version ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(80)

            TableColumn("Location", value: \.path) { app in
                Text(app.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .contextMenu(forSelectionType: AppItem.ID.self) { selectedIDs in
            if let id = selectedIDs.first, let app = apps.first(where: { $0.id == id }) {
                Button("Open") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
                }
                Button("Reveal in Finder") {
                    FileActions.revealInFinder(path: app.path)
                }
                Button("Copy Path") {
                    FileActions.copyToPasteboard(app.path)
                }
            }
        } primaryAction: { selectedIDs in
            guard let id = selectedIDs.first, let app = apps.first(where: { $0.id == id }) else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
        }
    }

    private var groupedView: some View {
        List {
            ForEach(groupedApps, id: \.architecture) { group in
                DisclosureGroup(isExpanded: expandedBinding(for: group.architecture)) {
                    ForEach(group.items) { app in
                        AppRow(app: app)
                    }
                } label: {
                    HStack {
                        ArchitectureBadge(architecture: group.architecture)
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
            SummaryChip(count: intelCount, label: "Intel Only", tint: .orange, isSelected: architectureFilter == .intel) {
                toggleFilter(.intel)
            }
            SummaryChip(count: universalCount, label: "Universal", tint: .blue, isSelected: architectureFilter == .universal) {
                toggleFilter(.universal)
            }
            SummaryChip(count: appleSiliconCount, label: "Apple Silicon", tint: .green, isSelected: architectureFilter == .appleSilicon) {
                toggleFilter(.appleSilicon)
            }
            if architectureFilter != nil {
                Button("Clear Filter") { architectureFilter = nil }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isLoading {
                Text("\(filteredApps.count) of \(apps.count) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func toggleFilter(_ architecture: Architecture) {
        architectureFilter = (architectureFilter == architecture) ? nil : architecture
    }

    private func loadApps() async {
        isLoading = true
        apps = await Task.detached(priority: .userInitiated) {
            AppScanner.scan()
        }.value
        isLoading = false
    }
}

#Preview {
    AppListView()
}
