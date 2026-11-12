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
