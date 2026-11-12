import Foundation

/// Finds out whether an Intel-only app has a version that runs natively on
/// Apple Silicon, from three places, best evidence first:
///
/// 1. **Homebrew's cask index** (one download for every app, cached for a day).
///    Casks whose newest version needs Rosetta carry `caveats_rosetta`, and
///    casks with a separate Apple Silicon download list `arm64_*` variations.
///    A cask with neither is native, or universal, in its newest version.
/// 2. **The app's own Sparkle feed** (`SUFeedURL`). A newer item that declares
///    `sparkle:hardwareRequirements` with `arm64` is native for sure; any
///    other newer item is reported as an update whose architecture isn't stated.
/// 3. **The App Store**, for apps installed from it: a newer version there.
///
/// Only Homebrew's public index, the app's own feed (which the app itself
/// already contacts), and Apple's lookup API (only for App Store apps) are
/// contacted. Nothing about this Mac is sent beyond the App Store app's ID.
actor NativeVersionChecker {
    static let shared = NativeVersionChecker()

    private let session: URLSession
    private var caskIndex: CaskIndex?

    private static let caskIndexURL = URL(string: "https://formulae.brew.sh/api/cask.json")!
    private static let caskCacheMaxAge: TimeInterval = 24 * 60 * 60

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = ["User-Agent": "SiliconScope"]
        session = URLSession(configuration: configuration)
    }

    func check(_ app: AppItem, sources: Set<NativeCheck.Source> = Set(NativeCheck.Source.allCases)) async throws -> NativeCheck {
        if app.isCrossOverLauncher { return .windowsApp }
        if sources.isEmpty { throw CheckError("Every source is turned off in Settings > Apple Silicon Versions.") }
        // Sources fail independently: a dead feed shouldn't hide a Homebrew answer.
        async let brewResult = attempt { sources.contains(.homebrew) ? try await self.homebrewCheck(app) : nil }
        async let feedResult = attempt { sources.contains(.sparkle) ? try await self.sparkleCheck(app) : nil }
        async let storeResult = attempt { sources.contains(.appStore) ? try await self.appStoreCheck(app) : nil }
        let results = await [brewResult, feedResult, storeResult]

        let checks = results.compactMap { try? $0.get() }.compactMap { $0 }
        if let best = checks.max(by: { $0.verdict < $1.verdict }) {
            // Homebrew saying the newest version still needs Rosetta outranks a
            // feed's "newer version, architecture not stated".
            if best.verdict == .updateAvailable,
               let intel = checks.first(where: { $0.verdict == .stillIntel && $0.source == .homebrew }),
               let brewVersion = intel.latestVersion, let newer = best.latestVersion,
               !Self.isNewer(newer, than: brewVersion) {
                return intel
            }
            return best
        }
        // Every source that applies failed: say why instead of "not found".
        if let error = results.compactMap({ result -> Error? in
            if case .failure(let error) = result { return error } else { return nil }
        }).first {
            throw error
        }
        return .notFound
    }

    private func attempt(_ body: () async throws -> NativeCheck?) async -> Result<NativeCheck?, Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }

    // MARK: - Homebrew

    private func homebrewCheck(_ app: AppItem) async throws -> NativeCheck? {
        let index = try await loadCaskIndex()
        guard let cask = index.cask(forAppNamed: app.bundleFileName, bundleIdentifier: app.bundleIdentifier) else {
            return nil
        }
        let version = cask.displayVersion
        // Homebrew can lag behind the app's own releases: then its version says nothing useful.
        let newestVersion = app.version.map { Self.isNewer($0, than: version) } == true ? nil : version
        if cask.requiresRosetta || cask.intelOnly {
            return NativeCheck(
                verdict: .stillIntel, latestVersion: newestVersion, source: .homebrew, url: cask.homepage,
                detail: "Homebrew's cask “\(cask.token)” \(version) still needs Rosetta.",
                homebrewToken: cask.token)
        }
        let how = cask.hasARMDownload
            ? "has a separate Apple Silicon download"
            : "runs natively on Apple Silicon"
        return NativeCheck(
            verdict: .nativeAvailable, latestVersion: newestVersion, source: .homebrew, url: cask.homepage,
            detail: "Homebrew's cask “\(cask.token)” \(version) \(how). Install it with: brew install --cask \(cask.token)",
            homebrewToken: cask.token)
    }

    nonisolated static var caskCacheURL: URL { URL.cachesDirectory.appending(path: "SiliconScope/cask.json") }

    /// When Homebrew's index was last downloaded, if it's cached.
    nonisolated static var caskCacheDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: caskCacheURL.path))?[.modificationDate] as? Date
    }

    /// Forgets the cached index, so the next check downloads it again.
    func clearCaskCache() {
        caskIndex = nil
        try? FileManager.default.removeItem(at: Self.caskCacheURL)
    }

    private func loadCaskIndex() async throws -> CaskIndex {
        if let caskIndex { return caskIndex }
        let cacheURL = Self.caskCacheURL
        let data: Data
        if let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < Self.caskCacheMaxAge,
           let cached = try? Data(contentsOf: cacheURL) {
            data = cached
        } else {
            let (downloaded, response) = try await session.data(from: Self.caskIndexURL)
            try Self.requireSuccess(response, what: "Homebrew's cask index")
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? downloaded.write(to: cacheURL, options: .atomic)
            data = downloaded
        }
        let index = try CaskIndex(json: data)
        caskIndex = index
        AppLog.post(.info, "Loaded \(index.count) Homebrew casks", source: "Homebrew")
        return index
    }

    // MARK: - Sparkle feed

    private func sparkleCheck(_ app: AppItem) async throws -> NativeCheck? {
        guard let feedURL = app.updateFeedURL, feedURL.scheme == "https" || feedURL.scheme == "http" else { return nil }
        let (data, response) = try await session.data(from: feedURL)
        try Self.requireSuccess(response, what: "\(app.name)'s update feed")
        let items = AppcastParser.items(in: data)
        guard let newest = items.max(by: { !Self.isNewer($0.version, than: $1.version) }) else { return nil }

        if newest.hardwareRequirements.contains(where: { $0.lowercased().contains("arm64") }) {
            return NativeCheck(
                verdict: .nativeAvailable, latestVersion: newest.version, source: .sparkle, url: newest.link ?? newest.download,
                detail: "\(app.name)'s update feed says \(newest.version) is built for Apple Silicon.")
        }
        guard let installed = app.version, Self.isNewer(newest.version, than: installed) else { return nil }
        return NativeCheck(
            verdict: .updateAvailable, latestVersion: newest.version, source: .sparkle, url: newest.link ?? newest.download,
            detail: "\(app.name) \(newest.version) is out (you have \(installed)). Its feed doesn't say whether it runs natively; updating often brings Apple Silicon support.")
    }

    // MARK: - App Store

    private func appStoreCheck(_ app: AppItem) async throws -> NativeCheck? {
        guard app.isFromAppStore, let bundleID = app.bundleIdentifier,
              var components = URLComponents(string: "https://itunes.apple.com/lookup") else { return nil }
        components.queryItems = [.init(name: "bundleId", value: bundleID), .init(name: "entity", value: "macSoftware")]
        guard let url = components.url else { return nil }
        let (data, response) = try await session.data(from: url)
        try Self.requireSuccess(response, what: "the App Store")
        struct Lookup: Decodable {
            struct Result: Decodable { let version: String?; let trackViewUrl: String? }
            let results: [Result]
        }
        guard let result = try JSONDecoder().decode(Lookup.self, from: data).results.first,
              let latest = result.version, let installed = app.version,
              Self.isNewer(latest, than: installed) else { return nil }
        return NativeCheck(
            verdict: .updateAvailable, latestVersion: latest, source: .appStore,
            url: result.trackViewUrl.flatMap(URL.init(string:)),
            detail: "The App Store has \(app.name) \(latest) (you have \(installed)). Update it from the App Store.")
    }

    // MARK: - Helpers

    nonisolated static func isNewer(_ candidate: String, than installed: String) -> Bool {
        candidate.compare(installed, options: .numeric) == .orderedDescending
    }

    private static func requireSuccess(_ response: URLResponse, what: String) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CheckError("\(what) answered HTTP \(http.statusCode).")
        }
    }
}

struct CheckError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Homebrew cask index

/// The parts of Homebrew's cask index SiliconScope needs, keyed by the
/// app bundle each cask installs.
struct CaskIndex: Sendable {
    struct Cask: Sendable {
        let token: String
        let version: String
        let homepage: URL?
        let requiresRosetta: Bool
        let intelOnly: Bool
        let hasARMDownload: Bool
        /// Bundle IDs the cask names (in `uninstall`/`zap` quit and launchctl entries).
        let mentionedIdentifiers: String

        /// Homebrew versions carry build details after a comma ("6.1,1791918634,…").
        var displayVersion: String { version.split(separator: ",").first.map(String.init) ?? version }
    }

    /// Casks by the lowercased name of the app they install, with that name's exact spelling.
    private let byAppName: [String: [(exactName: String, cask: Cask)]]
    var count: Int { byAppName.values.reduce(0) { $0 + $1.count } }

    init(json data: Data) throws {
        guard let casks = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CheckError("Homebrew's cask index isn't in the expected format.")
        }
        var byAppName: [String: [(exactName: String, cask: Cask)]] = [:]
        for raw in casks {
            guard let token = raw["token"] as? String,
                  let artifacts = raw["artifacts"] as? [[String: Any]] else { continue }
            if raw["disabled"] as? Bool == true { continue }
            let appNames = artifacts.flatMap { artifact -> [String] in
                (artifact["app"] as? [Any] ?? []).compactMap { $0 as? String }
            }
            guard !appNames.isEmpty else { continue }

            let arches = ((raw["depends_on"] as? [String: Any])?["arch"] as? [[String: Any]] ?? [])
                .compactMap { $0["type"] as? String }
            let cask = Cask(
                token: token,
                version: (raw["version"] as? String) ?? "",
                homepage: (raw["homepage"] as? String).flatMap(URL.init(string:)),
                requiresRosetta: raw["caveats_rosetta"] as? Bool == true,
                intelOnly: !arches.isEmpty && !arches.contains("arm"),
                hasARMDownload: Self.hasSeparateARMDownload(raw),
                mentionedIdentifiers: Self.identifiers(in: raw))
            for name in appNames {
                let fileName = (name as NSString).lastPathComponent
                byAppName[fileName.lowercased(), default: []].append((fileName, cask))
            }
        }
        self.byAppName = byAppName
    }

    /// The cask that installs this app, or nil when no cask can be trusted to be it.
    ///
    /// Names collide (the Wii U emulator Cemu.app and the calculator emulator
    /// CEmu.app), so a cask that names bundle IDs must name this one, and a
    /// cask that names none must spell the app exactly the same.
    func cask(forAppNamed appName: String, bundleIdentifier: String?) -> Cask? {
        guard let candidates = byAppName[appName.lowercased()] else { return nil }
        let trusted = candidates.filter { candidate in
            let identifiers = candidate.cask.mentionedIdentifiers
            if let bundleIdentifier, identifiers.contains(bundleIdentifier.lowercased()) { return true }
            return identifiers.isEmpty && candidate.exactName == appName
        }
        // Foo and Foo@beta both install Foo.app: prefer the stable cask.
        return (trusted.first { !$0.cask.token.contains("@") } ?? trusted.first)?.cask
    }

    /// Homebrew's API describes the Apple Silicon download in `url` and lists
    /// Intel systems (`tahoe`, `sonoma`…) as variations; when those point
    /// elsewhere, the cask has a download made for each architecture.
    private static func hasSeparateARMDownload(_ raw: [String: Any]) -> Bool {
        guard let base = raw["url"] as? String,
              let variations = raw["variations"] as? [String: Any] else { return false }
        return variations.contains { key, value in
            guard !key.hasPrefix("arm64"), let url = (value as? [String: Any])?["url"] as? String else { return false }
            return url != base
        }
    }

    private static func identifiers(in raw: [String: Any]) -> String {
        guard let artifacts = raw["artifacts"] as? [[String: Any]] else { return "" }
        let relevant = artifacts.filter { $0["uninstall"] != nil || $0["zap"] != nil }
        guard !relevant.isEmpty, let data = try? JSONSerialization.data(withJSONObject: relevant) else { return "" }
        return String(decoding: data, as: UTF8.self).lowercased()
    }
}

// MARK: - Sparkle appcast

/// Reads the items of a Sparkle appcast: version, download, release notes
/// link, and the hardware requirements Sparkle 2 feeds can declare.
enum AppcastParser {
    struct Item: Sendable {
        var version: String = ""
        var hardwareRequirements: [String] = []
        var link: URL?
        var download: URL?
    }

    static func items(in data: Data) -> [Item] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items.filter { !$0.version.isEmpty }
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [Item] = []
        private var current: Item?
        private var text = ""
        private var buildVersion = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch name {
            case "item":
                current = Item()
                buildVersion = ""
            case "enclosure":
                if let short = attributes["sparkle:shortVersionString"], current?.version.isEmpty ?? false {
                    current?.version = short
                }
                if let build = attributes["sparkle:version"] { buildVersion = build }
                current?.download = attributes["url"].flatMap(URL.init(string:))
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "sparkle:shortVersionString": if !value.isEmpty { current?.version = value }
            case "sparkle:version": if !value.isEmpty { buildVersion = value }
            case "sparkle:hardwareRequirements":
                current?.hardwareRequirements += value.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
            case "link": if current != nil { current?.link = URL(string: value) }
            case "item":
                if var item = current {
                    if item.version.isEmpty { item.version = buildVersion }
                    items.append(item)
                }
                current = nil
            default:
                break
            }
            text = ""
        }
    }
}
