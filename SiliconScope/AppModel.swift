import LogKitUI
import SwiftUI

/// Everything the window shows, kept for the app's lifetime so switching
/// pages doesn't rescan, and native-version results aren't lost.
@MainActor
@Observable
final class AppModel {
    var page: SidebarItem? = .apps

    private(set) var apps: [AppItem] = []
    private(set) var isScanningApps = false
    private(set) var hasScannedApps = false

    /// Native-version checks, by app path.
    private(set) var nativeChecks: [AppItem.ID: NativeCheckState] = [:]
    private(set) var isCheckingNative = false

    /// Updates installing or failed, by app path.
    private(set) var updates: [AppItem.ID: UpdateState] = [:]

    let log = LogViewerModel(store: AppLog.store)

    var intelApps: [AppItem] { apps.filter { $0.architecture == .intel } }

    var nativeAvailableCount: Int {
        nativeChecks.values.filter {
            if case .done(let check) = $0 { check.verdict == .nativeAvailable } else { false }
        }.count
    }

    func check(for app: AppItem) -> NativeCheckState? { nativeChecks[app.id] }

    // MARK: - Updating

    enum UpdateState: Equatable {
        case running(String)
        case failed(String, terminalCommand: String?)
    }

    func updateState(for app: AppItem) -> UpdateState? { updates[app.id] }

    /// How the Update button would install the version found for `app`.
    func updateMethod(for app: AppItem) -> UpdateMethod? {
        guard case .done(let check) = nativeChecks[app.id] else { return nil }
        return check.method
    }

    /// Apps whose update SiliconScope installs itself (App Store ones open the store instead).
    var updatableApps: [AppItem] {
        apps.filter { app in
            switch updateMethod(for: app) {
            case .homebrew, .download: if case .running = updates[app.id] { false } else { true }
            case .appStore, nil: false
            }
        }
    }

    var isUpdating: Bool { updates.values.contains { if case .running = $0 { true } else { false } } }

    func update(_ app: AppItem) async {
        guard let method = updateMethod(for: app) else { return }
        if case .running = updates[app.id] { return }
        if case .appStore = method {
            try? await AppInstaller.shared.install(method, for: app) { _ in }
            AppLog.post(.info, "Opened \(app.name) in the App Store", source: "App Store")
            return
        }
        updates[app.id] = .running("Starting…")
        let id = app.id
        do {
            try await AppInstaller.shared.install(method, for: app) { [weak self] step in
                self?.updates[id] = .running(step)
            }
            updates[id] = nil
            nativeChecks[id] = nil
            await scanApps()
            if let updated = apps.first(where: { $0.id == id }) {
                let level: LogLevel = updated.architecture == .intel ? .warning : .info
                AppLog.post(level, "\(updated.name) \(updated.version ?? "") is now \(updated.architecture.label)", source: "Update")
            }
        } catch {
            let command = (error as? InstallError)?.terminalCommand
            updates[id] = .failed(error.localizedDescription, terminalCommand: command)
            AppLog.post(.error, "\(app.name) wasn't updated: \(error.localizedDescription)", source: "Update")
        }
    }

    /// One after another: Homebrew allows a single install at a time.
    func updateAll() async {
        for app in updatableApps { await update(app) }
    }

    func clearUpdateFailure(_ app: AppItem) { updates[app.id] = nil }

    // MARK: - Scanning

    func scanAppsIfNeeded() async {
        guard !hasScannedApps else { return }
        await scanApps()
    }

    func scanApps() async {
        guard !isScanningApps else { return }
        isScanningApps = true
        let started = Date()
        let extraFolders = Preferences.extraFolders
        apps = await Task.detached(priority: .userInitiated) { AppScanner.scan(extraFolders: extraFolders) }.value
        isScanningApps = false
        hasScannedApps = true
        // Results for apps that changed or went away no longer apply.
        let current = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        nativeChecks = nativeChecks.filter { current[$0.key]?.architecture == .intel }
        // Known without asking anyone.
        for app in intelApps where app.isCrossOverLauncher {
            nativeChecks[app.id] = .done(.windowsApp)
        }

        let windows = intelApps.filter(\.isCrossOverLauncher).count
        AppLog.post(.info, String(format: "Scanned %d apps in %.1f s: %d Intel only, %d of them CrossOver launchers for Windows programs",
                                  apps.count, Date().timeIntervalSince(started), intelApps.count, windows),
                    source: "Scan")
        for app in intelApps where !app.isCrossOverLauncher {
            AppLog.post(.warning, "\(app.name) \(app.version ?? "") is Intel only and runs through Rosetta", source: "Scan")
        }
        if UserDefaults.standard.bool(forKey: Preferences.checkAfterScan) {
            await checkNativeVersions()
        }
    }

    // MARK: - Native versions

    /// Checks every Intel-only app, or only `only` when given.
    func checkNativeVersions(only: [AppItem]? = nil) async {
        let targets = (only ?? intelApps).filter {
            $0.architecture == .intel && !$0.isCrossOverLauncher && nativeChecks[$0.id] != .checking
        }
        guard !targets.isEmpty else { return }
        isCheckingNative = true
        defer { isCheckingNative = nativeChecks.values.contains(.checking) }
        for app in targets { nativeChecks[app.id] = .checking }
        AppLog.post(.info, "Looking for Apple Silicon versions of \(targets.count) app\(targets.count == 1 ? "" : "s")", source: "Native Check")

        let sources = Preferences.nativeSources
        await withTaskGroup(of: (AppItem, NativeCheckState).self) { group in
            for app in targets {
                group.addTask {
                    do {
                        return (app, .done(try await NativeVersionChecker.shared.check(app, sources: sources)))
                    } catch {
                        return (app, .failed(error.localizedDescription))
                    }
                }
            }
            for await (app, state) in group {
                nativeChecks[app.id] = state
                Self.log(state, for: app)
            }
        }
    }

    private static func log(_ state: NativeCheckState, for app: AppItem) {
        switch state {
        case .checking:
            break
        case .failed(let message):
            AppLog.post(.error, "\(app.name): \(message)", source: "Native Check")
        case .done(let check):
            let level: LogLevel = switch check.verdict {
            case .nativeAvailable, .updateAvailable, .unknown, .windowsApp: .info
            case .stillIntel: .warning
            }
            AppLog.post(level, "\(app.name): \(check.detail)", source: check.source?.rawValue ?? "Native Check")
        }
    }
}
