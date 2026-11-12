import Foundation

/// A currently-running process and how it's actually executing right now.
struct ProcessItem: Identifiable {
    let id: Int32 // pid
    let name: String
    let path: String
    /// True when the OS is running this process under Rosetta 2 translation,
    /// regardless of what architectures the binary on disk supports.
    let isTranslated: Bool
    let architecture: Architecture

    var isAppBundle: Bool { path.contains(".app/") }
}
