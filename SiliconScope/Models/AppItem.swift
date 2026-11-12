import Foundation

/// A single installed application discovered on disk.
struct AppItem: Identifiable, Sendable, Hashable {
    /// The app bundle's path, which is stable and unique per app.
    var id: String { path }

    let name: String
    let bundleIdentifier: String?
    let version: String?
    let path: String
    let architecture: Architecture
    /// The app's Sparkle update feed (`SUFeedURL`), when it has one.
    let updateFeedURL: URL?
    /// Installed from the Mac App Store (the bundle carries a receipt).
    let isFromAppStore: Bool

    /// A CrossOver launcher for a Windows program in a bottle: always x86 under
    /// Wine and Rosetta, and never with a Mac version to find.
    var isCrossOverLauncher: Bool {
        bundleIdentifier?.hasPrefix("com.codeweavers.CrossOverHelper") ?? false
    }

    /// "Foo.app", the name Homebrew casks install it under.
    var bundleFileName: String { (path as NSString).lastPathComponent }

    /// Non-optional sort key so version can be used with `KeyPathComparator`.
    var versionSortKey: String { version ?? "" }
}
