import AppKit
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @AppStorage("settingsTab") private var tab = "general"  // reopens on the last tab

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            ScanningSettings(model: model)
                .tabItem { Label("Scanning", systemImage: "magnifyingglass") }
                .tag("scanning")
            NativeVersionSettings(model: model)
                .tabItem { Label("Apple Silicon Versions", systemImage: "arrow.down.app") }
                .tag("native")
            UpdatesSettings()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
                .tag("updates")
        }
        .frame(width: 520)
        .noInitialFocus()
    }
}

private struct GeneralSettings: View {
    @AppStorage(Preferences.listViewMode) private var viewMode = ListViewMode.table

    var body: some View {
        Form {
            Section {
                Picker("Show lists as", selection: $viewMode) {
                    ForEach(ListViewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .help("How Installed Apps and Running Processes open. The toolbar switches it any time.")
            }
            Section("Log") {
                LabeledContent("Log file") {
                    Button("Show in Finder") {
                        if let url = AppLog.store.fileURL { FileActions.revealInFinder(path: url.path) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fitsContent()
    }
}

private struct ScanningSettings: View {
    let model: AppModel
    @AppStorage(Preferences.showCrossOverLaunchers) private var showCrossOverLaunchers = true
    @AppStorage(Preferences.refreshProcesses) private var refreshProcesses = false
    @State private var extraFolders = Preferences.extraFolders
    @State private var selectedFolder: String?

    var body: some View {
        Form {
            Section {
                ForEach(AppScanner.standardRoots, id: \.self) { folder in
                    Label((folder as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                        .foregroundStyle(.secondary)
                }
                ForEach(extraFolders, id: \.self) { folder in
                    HStack {
                        Label((folder as NSString).abbreviatingWithTildeInPath, systemImage: "folder.fill")
                        Spacer()
                        Button {
                            setFolders(extraFolders.filter { $0 != folder })
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Stop scanning this folder")
                    }
                }
                HStack {
                    Spacer()
                    Button("Add Folder…", action: addFolder)
                }
            } header: {
                Text("Folders to Scan")
            } footer: {
                Text("Apps are found up to two folders deep. System apps are left out: they're always native.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show CrossOver launchers for Windows programs", isOn: $showCrossOverLaunchers)
                    .help("CrossOver makes a small Intel app for each Windows program in a bottle. They never have a Mac version.")
                Toggle("Refresh running processes every 5 seconds", isOn: $refreshProcesses)
            }
        }
        .formStyle(.grouped)
        .fitsContent()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Scan Folder"
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.map(\.path).filter { !extraFolders.contains($0) && !AppScanner.standardRoots.contains($0) }
        setFolders(extraFolders + added)
    }

    private func setFolders(_ folders: [String]) {
        extraFolders = folders
        Preferences.extraFolders = folders
        Task { await model.scanApps() }
    }
}

private struct NativeVersionSettings: View {
    let model: AppModel
    @AppStorage(Preferences.checkAfterScan) private var checkAfterScan = false
    @AppStorage(Preferences.useHomebrew) private var useHomebrew = true
    @AppStorage(Preferences.useUpdateFeeds) private var useUpdateFeeds = true
    @AppStorage(Preferences.useAppStore) private var useAppStore = true
    @State private var cacheDate = NativeVersionChecker.caskCacheDate

    var body: some View {
        Form {
            Section {
                Toggle("Check after every scan", isOn: $checkAfterScan)
                    .help("Otherwise, choose Apps > Check for Apple Silicon Versions (⇧⌘U).")
            }
            Section {
                Toggle("Homebrew", isOn: $useHomebrew)
                    .help("Downloads Homebrew's public list of apps, about 20 MB, at most once a day.")
                Toggle("The app's own update feed", isOn: $useUpdateFeeds)
                    .help("Apps that update themselves with Sparkle publish a feed of their versions.")
                Toggle("App Store", isOn: $useAppStore)
                    .help("Only for apps installed from the App Store. Sends their app IDs to Apple.")
            } header: {
                Text("Where to Look")
            } footer: {
                Text("Nothing about your Mac is sent, except the IDs of App Store apps to Apple.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Homebrew List") {
                LabeledContent("Downloaded") {
                    HStack {
                        if let cacheDate {
                            Text(cacheDate, format: .relative(presentation: .named))
                        } else {
                            Text("Not yet").foregroundStyle(.secondary)
                        }
                        Button("Download Again") {
                            Task {
                                await NativeVersionChecker.shared.clearCaskCache()
                                cacheDate = nil
                                await model.checkNativeVersions()
                                cacheDate = NativeVersionChecker.caskCacheDate
                            }
                        }
                        .disabled(!useHomebrew || model.isCheckingNative)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fitsContent()
    }
}

private struct UpdatesSettings: View {
    @State private var updater = AppUpdater.shared

    var body: some View {
        Form {
            Section {
                if updater.isConfigured {
                    Toggle("Check for new versions of SiliconScope", isOn: $updater.automaticallyChecks)
                }
                LabeledContent("Version") {
                    HStack {
                        Text(verbatim: AppUpdater.versionString)
                        if updater.isConfigured {
                            Button("Check Now") { updater.checkForUpdates() }
                        }
                    }
                }
                LabeledContent("Release notes") {
                    Link("Open on GitHub", destination: AppLinks.releases)
                }
            }
        }
        .formStyle(.grouped)
        .fitsContent()
    }
}
