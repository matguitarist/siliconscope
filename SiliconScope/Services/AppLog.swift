import Foundation
import LogKit

/// SiliconScope's own log, in ~/Library/Logs/SiliconScope/SiliconScope.log,
/// shown on the Log page. Post from any thread.
enum AppLog {
    nonisolated static let store = LogStore(fileURL: LogStore.defaultFileURL(app: "SiliconScope"))

    nonisolated static func post(_ level: LogLevel, _ message: String, source: String) {
        store.post(level, message, source: source)
    }
}
