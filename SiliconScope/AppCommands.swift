import SwiftUI

/// The menu bar. Items act through the model and do nothing harmful when
/// pressed twice (a scan or check already running is not started again).
struct AppCommands: Commands {
    let model: AppModel
    let appUpdater: AppUpdater

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandGroup(after: .appInfo) {
            if appUpdater.isConfigured {
                Button("Check for Updates…") { appUpdater.checkForUpdates() }
            }
        }

        CommandGroup(before: .sidebar) {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                Button(item.rawValue) { model.page = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
        }

        CommandMenu("Apps") {
            Button("Rescan Apps") {
                model.page = .apps
                Task { await model.scanApps() }
            }
            .keyboardShortcut("r", modifiers: .command)

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
