import AppKit
import Foundation

/// UserDefaults keys, shared by Settings (`@AppStorage`) and the model.
enum Preferences {
    static let listViewMode = "listViewMode"
    static let extraScanFolders = "extraScanFolders"
    static let showCrossOverLaunchers = "showCrossOverLaunchers"
    static let refreshProcesses = "refreshProcesses"
    static let checkAfterScan = "checkNativeAfterScan"
    static let useHomebrew = "nativeSourceHomebrew"
    static let useUpdateFeeds = "nativeSourceUpdateFeeds"
    static let useAppStore = "nativeSourceAppStore"

    static func register() {
        // The Appearance setting is gone (1.3): windows follow the Mac's appearance.
        UserDefaults.standard.removeObject(forKey: "theme")
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

enum AppLinks {
    static let repository = URL(string: "https://github.com/matguitarist/siliconscope")!
    static let releases = URL(string: "https://github.com/matguitarist/siliconscope/releases")!
    static let newIssue = URL(string: "https://github.com/matguitarist/siliconscope/issues/new")!
    static let rosetta = URL(string: "https://support.apple.com/102527")!
    static let homebrew = URL(string: "https://formulae.brew.sh/cask/")!
}
