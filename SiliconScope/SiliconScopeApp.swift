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
                .frame(minWidth: 760, minHeight: 480)
                .onAppear { AppTheme.current.apply() }
        }
        .commands {
            AppCommands(model: model, appUpdater: appUpdater)
        }

        Window("SiliconScope Help", id: HelpView.windowID) {
            HelpView()
        }
        .commandsRemoved()  // opened from the Help menu, not listed under Window

        Settings {
            SettingsView(model: model)
        }
    }
}
