import SwiftUI

/// The app's own menus. Items act through the model and do nothing harmful when
/// pressed twice (a scan or check already running is not started again).
/// Check for Updates…, Help and the pages (⌘1–⌘3) are the shared AppCommands.swift.
struct AppMenus: Commands {
    let model: AppModel
    @AppStorage(Preferences.listViewMode) private var viewMode = ListViewMode.table

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandGroup(before: .sidebar) {
            Button("Refresh") { model.refreshCurrentPage() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.canRefreshCurrentPage)
            Divider()
            Toggle("As Table", isOn: Binding(get: { viewMode == .table }, set: { if $0 { viewMode = .table } }))
                .keyboardShortcut("1", modifiers: [.command, .control])
            Toggle("As Groups", isOn: Binding(get: { viewMode == .grouped }, set: { if $0 { viewMode = .grouped } }))
                .keyboardShortcut("2", modifiers: [.command, .control])
            Divider()
        }

        CommandMenu("Apps") {
            Button("Rescan Apps") {
                model.page = .apps
                Task { await model.scanApps() }
            }
            .disabled(model.isScanningApps)

            Button("Check for Apple Silicon Versions") {
                model.page = .apps
                Task {
                    await model.scanAppsIfNeeded()
                    await model.checkNativeVersions()
                }
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
        }
    }
}
