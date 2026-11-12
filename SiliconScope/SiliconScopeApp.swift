import SwiftUI

@main
struct SiliconScopeApp: App {
    @State private var model = AppModel()
    private let appUpdater = AppUpdater.shared

    var body: some Scene {
        Window("SiliconScope", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 480)
        }
        .commands {
            AppCommands(model: model, appUpdater: appUpdater)
        }
    }
}
