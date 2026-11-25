import SwiftUI

@main
struct SiliconScopeApp: App {
    @State private var model = AppModel()
    private let appUpdater = AppUpdater.shared

    init() {
        Preferences.register()
    }

    var body: some Scene {
        Window("SiliconScope", id: "main") {
            ContentView(model: model)
                .whatsNew(app: "SiliconScope", repository: "matguitarist/siliconscope")
                .frame(minWidth: 760, minHeight: 480)
                .noInitialFocus()
        }
        .commands {
            StandardCommands(app: "SiliconScope", repository: "matguitarist/siliconscope",
                             updates: AppUpdates(isAvailable: appUpdater.isConfigured) { appUpdater.checkForUpdates() },
                             help: .window(HelpView.windowID), log: .page { model.page = .log }) {
                HelpCommands()
            }
            PageCommands(pages: SidebarItem.allCases, title: \.rawValue) { model.page = $0 }
            AppMenus(model: model)
        }

        Window("SiliconScope Help", id: HelpView.windowID) {
            HelpView()
                .noInitialFocus()
        }
        .commandsRemoved()  // opened from the Help menu, not listed under Window

        Settings {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)  // each tab sizes the window to its form
    }
}
