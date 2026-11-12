// The Help window (Help → SiliconScope Help): short, task-based topics.
// **bold** marks the names of buttons, menus and pages.

import SwiftUI

enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, architectures, installedApps, nativeVersions, processes, log, settings, privacy, shortcuts, troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .architectures: "Intel, Universal & Apple Silicon"
        case .installedApps: "Installed Apps"
        case .nativeVersions: "Finding Apple Silicon Versions"
        case .processes: "Running Processes"
        case .log: "Log"
        case .settings: "Settings"
        case .privacy: "Privacy"
        case .shortcuts: "Keyboard Shortcuts"
        case .troubleshooting: "Troubleshooting"
        }
    }

    var icon: String {
        switch self {
        case .gettingStarted: "flag"
        case .architectures: "cpu"
        case .installedApps: "square.grid.2x2"
        case .nativeVersions: "arrow.down.app"
        case .processes: "waveform.path.ecg"
        case .log: "doc.text.magnifyingglass"
        case .settings: "gearshape"
        case .privacy: "hand.raised"
        case .shortcuts: "keyboard"
        case .troubleshooting: "wrench.and.screwdriver"
        }
    }
}

struct HelpView: View {
    static let windowID = "help"
    @State private var selection: HelpTopic? = .gettingStarted

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.icon).tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let topic = selection ?? .gettingStarted
                    Label(topic.title, systemImage: topic.icon)
                        .font(.largeTitle.bold())
                        .padding(.bottom, 4)
                    content(for: topic)
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .id(selection)  // start each topic at the top
        }
        .navigationTitle("SiliconScope Help")
        .frame(minWidth: 720, minHeight: 480)
    }

    @ViewBuilder
    private func content(for topic: HelpTopic) -> some View {
        switch topic {
        case .gettingStarted:
            Paragraph("SiliconScope shows which of your apps are built for Apple Silicon and which still run through **Rosetta**, Apple's translator for Intel code.")
            Steps([
                "Open **Installed Apps**. SiliconScope scans /Applications and ~/Applications.",
                "Click **Intel Only** to see the apps that need Rosetta.",
                "Choose **Apps > Check for Apple Silicon Versions** (⇧⌘U) to find out which of them have a native version.",
                "Open **Running Processes** to see what is running through Rosetta right now.",
            ])
            Paragraph("Native apps start faster, use less battery, and keep working when Apple stops shipping Rosetta.")

        case .architectures:
            Term("Apple Silicon", color: .green, "Built only for Apple's chips (arm64). Runs natively.")
            Term("Universal", color: .blue, "Contains both an Intel and an Apple Silicon version. Your Mac runs the native one.")
            Term("Intel", color: .orange, "Built only for Intel chips (x86_64). Runs through Rosetta: it works, but slower and with more battery use.")
            Term("Unknown", color: .gray, "SiliconScope couldn't read the app's program, for example because the bundle is damaged or the program is a script.")
            Paragraph("SiliconScope reads this from the header of each app's program on disk; it doesn't open or run the apps.")
            Link("About Rosetta on Apple's website", destination: AppLinks.rosetta)

        case .installedApps:
            Paragraph("The chips at the top count each kind of app and filter the list: click one to show only those apps, click it again to show them all.")
            Paragraph("**Table** shows every app in sortable columns; **Grouped** puts them under Intel, Universal and Apple Silicon. The choice in **Settings > General** sets how lists open.")
            Paragraph("Double-click an app to open it. Right-click for **Reveal in Finder**, **Copy Path**, and, for Intel apps, **Check for Apple Silicon Version**.")
            Paragraph("**Windows App** marks the small launchers CrossOver makes for Windows programs. They always run through Wine and Rosetta, so they're never searched. Hide them in **Settings > Scanning**.")

        case .nativeVersions:
            Paragraph("**Apps > Check for Apple Silicon Versions** (⇧⌘U), or the toolbar button, looks up every Intel-only app in up to three places:")
            Term("Homebrew", color: .orange, "Homebrew's public list of Mac apps says, for each app's newest version, whether it still needs Rosetta and whether there is a separate Apple Silicon download.")
            Term("The app's update feed", color: .teal, "Apps that update themselves with Sparkle publish their versions. A feed can say a version is built for Apple Silicon.")
            Term("App Store", color: .blue, "For apps installed from the App Store: whether a newer version is out.")
            Paragraph("The **Apple Silicon Version** column then shows:")
            Term("Native", color: .green, "A version that runs natively exists. Right-click for **Open Download Page** or **Copy Homebrew Install Command**.")
            Term("Update", color: .blue, "A newer version is out, but its source doesn't say whether it's native. Updating is worth a try.")
            Term("Still Intel", color: .orange, "The newest version still needs Rosetta.")
            Term("Not Found", color: .gray, "None of the sources knows the app. Games and in-house tools are often in this case; check the developer's website.")
            Paragraph("Hold the pointer over a result for where it came from. Every result is also written to the **Log**.")

        case .processes:
            Paragraph("**Running Processes** asks macOS which processes it is translating with Rosetta right now. This is what is actually running, not what the app on disk contains: a universal app opened with **Open using Rosetta** shows up as Rosetta here.")
            Paragraph("Right-click a process to reveal it in Finder, copy its path, or **Quit Process…**. Quitting sends the same signal as quitting normally; unsaved work in that process may be lost.")
            Paragraph("Turn on **Refresh running processes every 5 seconds** in **Settings > Scanning** to keep the list current.")

        case .log:
            Paragraph("The **Log** page lists what SiliconScope did: each scan, the Intel-only apps it found, and every Apple Silicon version check with its source.")
            Paragraph("Click a level or a source to filter, search with the field in the toolbar, and use **Clear** (⌘K) to start fresh. The file stays in ~/Library/Logs/SiliconScope; **Help > Open Logs Folder** shows it.")

        case .settings:
            Term("General", color: .secondary, "Appearance, and whether lists open as a table or grouped.")
            Term("Scanning", color: .secondary, "Extra folders to scan (an external drive's Applications folder, say), CrossOver launchers, and refreshing processes.")
            Term("Apple Silicon Versions", color: .secondary, "Check after every scan, which sources to ask, and downloading Homebrew's list again.")
            Term("Updates", color: .secondary, "Updates of SiliconScope itself.")

        case .privacy:
            Paragraph("SiliconScope reads app bundles and the process list on your Mac. It sends nothing about your Mac anywhere.")
            Paragraph("Checking for Apple Silicon versions downloads Homebrew's public list (the same for everyone) and each app's own update feed. For apps from the App Store, it asks Apple's store about their app IDs. Each source can be turned off in **Settings > Apple Silicon Versions**.")

        case .shortcuts:
            Shortcut("⌘1, ⌘2, ⌘3", "Installed Apps, Running Processes, Log")
            Shortcut("⌘R", "Rescan apps")
            Shortcut("⇧⌘U", "Check for Apple Silicon versions")
            Shortcut("⌘F", "Filter the list")
            Shortcut("⌘K", "Clear the log (on the Log page)")
            Shortcut("⌘,", "Settings")
            Shortcut("⌘?", "This help")

        case .troubleshooting:
            Term("An app is missing", color: .secondary, "Only /Applications, ~/Applications and two folders inside them are scanned. Add the app's folder in **Settings > Scanning**.")
            Term("“Check Failed”", color: .secondary, "A source couldn't be reached: hold the pointer over the result, or look in the **Log**. Check your connection and try again.")
            Term("A result looks wrong", color: .secondary, "Homebrew's list can lag behind an app's own releases. Download it again in **Settings > Apple Silicon Versions**, and report the app with **Help > Report a Problem**.")
            Term("Quit Process fails", color: .secondary, "Processes that belong to macOS or another user can't be quit from SiliconScope.")
        }
    }
}

// MARK: - Building blocks

private struct Paragraph: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(.init(text)).fixedSize(horizontal: false, vertical: true)
    }
}

private struct Steps: View {
    let steps: [String]
    init(_ steps: [String]) { self.steps = steps }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                    Text(.init(step)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct Term: View {
    let name: String
    let color: Color
    let text: String
    init(_ name: String, color: Color, _ text: String) {
        self.name = name
        self.color = color
        self.text = text
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.headline).foregroundStyle(color == .secondary ? .primary : color)
            Text(.init(text)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Shortcut: View {
    let keys: String
    let action: String
    init(_ keys: String, _ action: String) {
        self.keys = keys
        self.action = action
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(keys).monospaced().frame(width: 120, alignment: .leading)
            Text(action)
        }
    }
}

/// The Help menu.
struct HelpCommands: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("SiliconScope Help") { openWindow(id: HelpView.windowID) }
            .keyboardShortcut("?", modifiers: .command)
        Divider()
        Button("Show Log") {
            openWindow(id: "main")
            model.page = .log
        }
        Button("Open Logs Folder") {
            if let url = AppLog.store.fileURL {
                NSWorkspace.shared.open(url.deletingLastPathComponent())
            }
        }
        Divider()
        Link("About Rosetta", destination: AppLinks.rosetta)
        Link("Browse Homebrew Apps", destination: AppLinks.homebrew)
        Divider()
        Link("Release Notes", destination: AppLinks.releases)
        Link("SiliconScope on GitHub", destination: AppLinks.repository)
        Link("Report a Problem or Suggest an Idea…", destination: AppLinks.newIssue)
    }
}
