import LogKitUI
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case apps = "Installed Apps"
    case processes = "Running Processes"
    case log = "Log"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .apps: return "square.grid.2x2"
        case .processes: return "cpu"
        case .log: return "doc.text.magnifyingglass"
        }
    }
}

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.page) {
                Section {
                    ForEach([SidebarItem.apps, .processes]) { item in
                        Label(item.rawValue, systemImage: item.symbolName).tag(item)
                    }
                }
                Section("App") {
                    Label(SidebarItem.log.rawValue, systemImage: SidebarItem.log.symbolName).tag(SidebarItem.log)
                }
            }
            .navigationSplitViewColumnWidth(200)
            .navigationTitle("SiliconScope")
        } detail: {
            switch model.page {
            case .apps:
                AppListView(model: model)
            case .processes:
                ProcessListView()
            case .log:
                LogViewer(model: model.log, options: .init(
                    emptyMessage: "Scans and Apple Silicon version checks are logged here.",
                    sourceColor: { source in
                        switch source {
                        case "Homebrew": .orange
                        case "Update Feed": .teal
                        case "App Store": .blue
                        default: .indigo
                        }
                    }))
                    .navigationTitle("Log")
            case .none:
                ContentUnavailableView("Select a Category", systemImage: "sidebar.left")
            }
        }
    }
}

#Preview {
    ContentView(model: AppModel())
}
