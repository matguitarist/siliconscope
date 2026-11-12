// Updates of the app itself, through Sparkle. Off until releases are
// hosted: Info.plist needs SUFeedURL (the appcast) and SUPublicEDKey (the
// key that signs updates). tools/release.sh publishes both feed and zips.

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

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
