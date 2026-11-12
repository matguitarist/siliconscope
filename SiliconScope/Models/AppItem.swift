import AppKit

/// A single installed application discovered on disk.
struct AppItem: Identifiable {
    /// The app bundle's path, which is stable and unique per app.
    var id: String { path }

    let name: String
    let bundleIdentifier: String?
    let version: String?
    let path: String
    let architecture: Architecture
    let icon: NSImage

    /// Non-optional sort key so version can be used with `KeyPathComparator`.
    var versionSortKey: String { version ?? "" }
}
