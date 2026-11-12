import AppKit
import Foundation

/// UserDefaults keys, shared by Settings (`@AppStorage`) and the model.
enum Preferences {
    static let theme = "theme"
    static let listViewMode = "listViewMode"
    static let extraScanFolders = "extraScanFolders"
    static let showCrossOverLaunchers = "showCrossOverLaunchers"
    static let refreshProcesses = "refreshProcesses"
    static let checkAfterScan = "checkNativeAfterScan"
    static let useHomebrew = "nativeSourceHomebrew"
    static let useUpdateFeeds = "nativeSourceUpdateFeeds"
    static let useAppStore = "nativeSourceAppStore"

    static func register() {
        UserDefaults.standard.register(defaults: [
            showCrossOverLaunchers: true,
            refreshProcesses: false,
            checkAfterScan: false,
            useHomebrew: true,
            useUpdateFeeds: true,
            useAppStore: true,
        ])
    }

    /// Folders scanned on top of /Applications and ~/Applications.
    static var extraFolders: [String] {
        get { UserDefaults.standard.stringArray(forKey: extraScanFolders) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: extraScanFolders) }
    }

    static var nativeSources: Set<NativeCheck.Source> {
        let defaults = UserDefaults.standard
        var sources: Set<NativeCheck.Source> = []
        if defaults.bool(forKey: useHomebrew) { sources.insert(.homebrew) }
        if defaults.bool(forKey: useUpdateFeeds) { sources.insert(.sparkle) }
        if defaults.bool(forKey: useAppStore) { sources.insert(.appStore) }
        return sources
    }
}

/// Light, dark, or whatever macOS uses.
enum AppTheme: String, CaseIterable {
    case system, light, dark

    static var current: AppTheme {
        UserDefaults.standard.string(forKey: Preferences.theme).flatMap(AppTheme.init) ?? .system
    }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Applies to every window, including Settings and Help.
    @MainActor func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum AppLinks {
    static let repository = URL(string: "https://github.com/matguitarist/siliconscope")!
    static let releases = URL(string: "https://github.com/matguitarist/siliconscope/releases")!
    static let newIssue = URL(string: "https://github.com/matguitarist/siliconscope/issues/new")!
    static let rosetta = URL(string: "https://support.apple.com/102527")!
    static let homebrew = URL(string: "https://formulae.brew.sh/cask/")!
}
