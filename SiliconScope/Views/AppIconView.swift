import AppKit
import SwiftUI

/// An app's Finder icon, loaded once per path on the main actor
/// (NSImage isn't Sendable, so it stays out of `AppItem`).
struct AppIconView: View {
    let path: String
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: IconCache.shared.icon(for: path))
            .resizable()
            .frame(width: size, height: size)
    }
}

@MainActor
final class IconCache {
    static let shared = IconCache()
    private var icons: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }
}

/// The result of a native-version check, as a small colored label.
struct NativeCheckLabel: View {
    let state: NativeCheckState?

    var body: some View {
        switch state {
        case nil:
            Text("—").foregroundStyle(.tertiary)
                .help("Not checked yet. Choose Apps > Check for Apple Silicon Versions.")
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label("Check Failed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .help(message)
        case .done(let check):
            Label(check.label, systemImage: check.symbolName)
                .foregroundStyle(check.tint)
                .help(check.detail)
        }
    }
}

/// The Update button for an app with a version to install, and how that update is going.
struct UpdateControl: View {
    let model: AppModel
    let app: AppItem
    let onUpdate: () -> Void

    var body: some View {
        switch model.updateState(for: app) {
        case .running(let step):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(step).foregroundStyle(.secondary)
            }
        case .failed(let message, _):
            Button("Retry", action: onUpdate)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Update failed: \(message)")
        case nil:
            if let method = model.updateMethod(for: app) {
                Button(method.buttonTitle, action: onUpdate)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(method.help(for: app))
            }
        }
    }
}

extension UpdateMethod {
    var buttonTitle: String {
        if case .appStore = self { "App Store" } else { "Update" }
    }

    func help(for app: AppItem) -> String {
        switch self {
        case .homebrew(let token):
            AppInstaller.brewPath == nil
                ? "Install Homebrew first (brew.sh), then this installs the cask “\(token)”."
                : "Install the Apple Silicon version with Homebrew (brew install --cask \(token)), replacing this copy."
        case .download(let download):
            "Download \(app.name) \(download.version) from its update feed, check its signatures, and replace this copy (the old one goes to the Trash)."
        case .appStore:
            "Open \(app.name) in the App Store to update it there."
        }
    }

    /// What the confirmation says will happen.
    func confirmation(for app: AppItem) -> String {
        switch self {
        case .homebrew(let token):
            "Homebrew installs the cask “\(token)” into /Applications, replacing \(app.name) \(app.version ?? ""). Homebrew may ask for your password in some cases; SiliconScope then offers to finish in Terminal."
        case .download(let download):
            "SiliconScope downloads \(app.name) \(download.version) from the developer's update feed, checks that it's signed by the same developer, and moves the current copy to the Trash."
        case .appStore:
            "The App Store opens on \(app.name)."
        }
    }
}
