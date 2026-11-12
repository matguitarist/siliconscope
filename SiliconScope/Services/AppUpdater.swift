// Updates of the app itself, through Sparkle: SUFeedURL (the appcast) and
// SUPublicEDKey (the key that signs updates) are in project.yml.
// tools/release.sh publishes the feed and the zips.

import Sparkle
import SwiftUI

@MainActor
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    /// Whether this build knows where to look for updates.
    let isConfigured: Bool
    private let controller: SPUStandardUpdaterController?

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String) ?? ""
        let key = (info["SUPublicEDKey"] as? String) ?? ""
        isConfigured = !feed.isEmpty && !key.isEmpty
        controller = isConfigured
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
