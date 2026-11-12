import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case apps = "Installed Apps"
    case processes = "Running Processes"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .apps: return "square.grid.2x2"
        case .processes: return "cpu"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .apps

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.rawValue, systemImage: item.symbolName)
                        .tag(item)
                }
            }
            .navigationSplitViewColumnWidth(200)
            .navigationTitle("SiliconScope")
        } detail: {
            switch selection {
            case .apps:
                AppListView()
            case .processes:
                ProcessListView()
            case .none:
                ContentUnavailableView("Select a Category", systemImage: "sidebar.left")
            }
        }
    }
}

#Preview {
    ContentView()
}
