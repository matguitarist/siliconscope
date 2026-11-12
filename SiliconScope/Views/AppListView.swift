import SwiftUI

enum ListViewMode: String, CaseIterable, Identifiable {
    case table = "Table"
    case grouped = "Grouped"
    var id: String { rawValue }
}

struct AppListView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\AppItem.architecture)]
    @State private var selection: AppItem.ID?
    @State private var architectureFilter: Architecture?
    @State private var showOnlyNativeAvailable = false
    @AppStorage(Preferences.listViewMode) private var viewMode = ListViewMode.table
    @AppStorage(Preferences.showCrossOverLaunchers) private var showCrossOverLaunchers = true
    @State private var expandedGroups: Set<Architecture> = Set(Architecture.allCases)
    /// Apps waiting for the person to confirm their update.
    @State private var pendingUpdates: [AppItem] = []

    private var apps: [AppItem] {
        showCrossOverLaunchers ? model.apps : model.apps.filter { !$0.isCrossOverLauncher }
    }

    private var filteredApps: [AppItem] {
        var base = apps
        if let architectureFilter {
            base = base.filter { $0.architecture == architectureFilter }
        }
        if showOnlyNativeAvailable {
            base = base.filter { nativeVerdict(of: $0) == .nativeAvailable }
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
    /// Intel apps a Mac version could exist for (not CrossOver's Windows launchers).
    private var checkableCount: Int { apps.filter { $0.architecture == .intel && !$0.isCrossOverLauncher }.count }
    private var universalCount: Int { apps.filter { $0.architecture == .universal }.count }
    private var appleSiliconCount: Int { apps.filter { $0.architecture == .appleSilicon }.count }

    private func nativeVerdict(of app: AppItem) -> NativeCheck.Verdict? {
        if case .done(let check) = model.check(for: app) { check.verdict } else { nil }
    }

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
                    Task { await model.checkNativeVersions() }
                } label: {
                    Label("Check for Apple Silicon Versions", systemImage: "arrow.down.app")
                }
                .disabled(model.isScanningApps || model.isCheckingNative || checkableCount == 0)
                .help(checkableCount == 0
                      ? "No Intel-only Mac apps to check"
                      : "Look for Apple Silicon versions of the \(checkableCount) Intel-only Mac apps in Homebrew, their update feeds and the App Store")
            }
            ToolbarItem {
                Button {
                    Task { await model.scanApps() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanningApps)
                .help("Rescan /Applications")
            }
        }
        .task {
            await model.scanAppsIfNeeded()
        }
        .confirmationDialog(confirmationTitle, isPresented: Binding(
            get: { !pendingUpdates.isEmpty },
            set: { if !$0 { pendingUpdates = [] } }
        ), titleVisibility: .visible) {
            Button(pendingUpdates.count == 1 ? "Update" : "Update All") {
                let apps = pendingUpdates
                pendingUpdates = []
                Task { for app in apps { await model.update(app) } }
            }
            Button("Cancel", role: .cancel) { pendingUpdates = [] }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationTitle: String {
        if pendingUpdates.count == 1, let app = pendingUpdates.first {
            let version = model.check(for: app).flatMap { if case .done(let c) = $0 { c.latestVersion } else { nil } }
            return "Update \(app.name)\(version.map { " to \($0)" } ?? "")?"
        }
        return "Update \(pendingUpdates.count) Apps?"
    }

    private var confirmationMessage: String {
        let running = pendingUpdates.filter { app in
            NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.path == app.path }
        }
        var message = pendingUpdates.count == 1
            ? (pendingUpdates.first.flatMap { app in model.updateMethod(for: app)?.confirmation(for: app) } ?? "")
            : "\(pendingUpdates.map(\.name).formatted(.list(type: .and))) are installed one after another. Each old copy is replaced."
        if !running.isEmpty {
            message += "\n\n\(running.map(\.name).formatted(.list(type: .and))) will quit first."
        }
        return message
    }

    /// App Store updates open the store right away; the others ask first.
    private func requestUpdate(_ app: AppItem) {
        if case .appStore = model.updateMethod(for: app) {
            Task { await model.update(app) }
        } else {
            pendingUpdates = [app]
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanningApps && apps.isEmpty {
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
                    AppIconView(path: app.path)
                    Text(app.name)
                }
            }
            .width(min: 180, ideal: 240)

            TableColumn("Architecture", value: \.architecture) { app in
                ArchitectureBadge(architecture: app.architecture)
            }
            .width(130)

            TableColumn("Apple Silicon Version") { app in
                if app.architecture == .intel {
                    HStack(spacing: 8) {
                        NativeCheckLabel(state: model.check(for: app))
                        Spacer(minLength: 0)
                        UpdateControl(app: app) { requestUpdate(app) }
                    }
                }
            }
            .width(min: 190, ideal: 230)

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
                AppActions(app: app) { requestUpdate(app) }
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
                        AppRow(app: app) { requestUpdate(app) }
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
            if model.nativeAvailableCount > 0 || showOnlyNativeAvailable {
                SummaryChip(count: model.nativeAvailableCount, label: "Native Version Available", tint: .green,
                            isSelected: showOnlyNativeAvailable) {
                    showOnlyNativeAvailable.toggle()
                }
                .help("Intel-only apps with a version that runs natively on Apple Silicon")
            }
            if architectureFilter != nil || showOnlyNativeAvailable {
                Button("Clear Filter") {
                    architectureFilter = nil
                    showOnlyNativeAvailable = false
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if model.updatableApps.count > 1 {
                Button("Update All (\(model.updatableApps.count))…") {
                    pendingUpdates = model.updatableApps
                }
                .disabled(model.isUpdating)
                .help("Install every Apple Silicon version and update found, one after another")
            }
            if model.isScanningApps && !apps.isEmpty {
                ProgressView().controlSize(.small)
            }
            if !apps.isEmpty {
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
}

/// The actions on one app, shared by the table's and the grouped list's context menus.
struct AppActions: View {
    @Environment(AppModel.self) private var model
    let app: AppItem
    let onUpdate: () -> Void

    var body: some View {
        Button("Open") {
            NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
        }
        Button("Reveal in Finder") {
            FileActions.revealInFinder(path: app.path)
        }
        Button("Copy Path") {
            FileActions.copyToPasteboard(app.path)
        }
        if app.architecture == .intel && !app.isCrossOverLauncher {
            Divider()
            if let method = model.updateMethod(for: app) {
                Button(method.buttonTitle == "Update" ? "Update…" : "Open in App Store", action: onUpdate)
                    .disabled({ if case .running = model.updateState(for: app) { true } else { false } }())
            }
            if case .failed(_, let command?) = model.updateState(for: app) {
                Button("Finish Update in Terminal") {
                    model.clearUpdateFailure(app)
                    FileActions.runInTerminal(command)
                }
            }
            Button("Check for Apple Silicon Version") {
                Task { await model.checkNativeVersions(only: [app]) }
            }
            .disabled(model.check(for: app) == .checking)
            if case .done(let check) = model.check(for: app), let url = check.url {
                Button(check.source == .appStore ? "Open in App Store" : "Open Download Page") {
                    NSWorkspace.shared.open(url)
                }
            }
            if case .done(let check) = model.check(for: app), check.source == .homebrew,
               check.verdict == .nativeAvailable, let token = check.homebrewToken {
                Button("Copy Homebrew Install Command") {
                    FileActions.copyToPasteboard("brew install --cask \(token)")
                }
            }
        }
    }
}

#Preview {
    AppListView()
        .environment(AppModel())
}
