import SwiftUI

/// What SiliconScope found out about an Apple Silicon version of an Intel-only app.
struct NativeCheck: Sendable, Equatable {
    enum Verdict: Int, Sendable, Comparable {
        /// A Windows program run by CrossOver: there is no Mac version to find.
        case windowsApp
        /// Nothing anywhere says whether a native version exists.
        case unknown
        /// The newest version still needs Rosetta.
        case stillIntel
        /// A newer version exists; whether it is native isn't stated.
        case updateAvailable
        /// A version that runs natively on Apple Silicon exists.
        case nativeAvailable

        static func < (lhs: Verdict, rhs: Verdict) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Source: String, Sendable {
        case homebrew = "Homebrew"
        case sparkle = "Update Feed"
        case appStore = "App Store"
    }

    let verdict: Verdict
    let latestVersion: String?
    let source: Source?
    /// Where to get it: the download, the store page, or the app's site.
    let url: URL?
    /// One sentence for hover help and the log.
    let detail: String
    /// The Homebrew cask that installs it, for `brew install --cask`.
    var homebrewToken: String? = nil

    static let notFound = NativeCheck(
        verdict: .unknown, latestVersion: nil, source: nil, url: nil,
        detail: "Not listed in Homebrew, no update feed, and not from the App Store.")

    static let windowsApp = NativeCheck(
        verdict: .windowsApp, latestVersion: nil, source: nil, url: nil,
        detail: "A CrossOver launcher for a Windows program. It always runs through Wine and Rosetta; look for a Mac version of the program itself.")

    var label: String {
        switch verdict {
        case .windowsApp: "Windows App"
        case .nativeAvailable: latestVersion.map { "Native \($0)" } ?? "Native"
        case .updateAvailable: latestVersion.map { "Update \($0)" } ?? "Update"
        case .stillIntel: "Still Intel"
        case .unknown: "Not Found"
        }
    }

    var symbolName: String {
        switch verdict {
        case .nativeAvailable: "arrow.down.circle.fill"
        case .updateAvailable: "arrow.up.circle"
        case .stillIntel: "xmark.circle"
        case .unknown: "questionmark.circle"
        case .windowsApp: "macwindow"
        }
    }

    var tint: Color {
        switch verdict {
        case .nativeAvailable: .green
        case .updateAvailable: .blue
        case .stillIntel: .orange
        case .unknown, .windowsApp: .secondary
        }
    }
}

/// Where a native-version check stands for one app.
enum NativeCheckState: Sendable, Equatable {
    case checking
    case done(NativeCheck)
    case failed(String)
}
