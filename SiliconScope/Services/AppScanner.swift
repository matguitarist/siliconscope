import AppKit

/// Scans the filesystem for installed applications and classifies each one's architecture.
enum AppScanner {
    /// Folders to search. System apps are intentionally excluded — they're always
    /// universal/native on any supported OS and would just be noise here.
    private static var searchRoots: [String] {
        [
            "/Applications",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications"),
        ]
    }

    static func scan() -> [AppItem] {
        var seenPaths = Set<String>()
        var results: [AppItem] = []

        for root in searchRoots {
            for appPath in findAppBundles(inDirectory: root, remainingDepth: 2) {
                guard seenPaths.insert(appPath).inserted else { continue }
                if let item = makeAppItem(path: appPath) {
                    results.append(item)
                }
            }
        }
        return results
    }

    private static func findAppBundles(inDirectory path: String, remainingDepth: Int) -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return [] }

        var found: [String] = []
        for entry in entries {
            let fullPath = (path as NSString).appendingPathComponent(entry)
            if entry.hasSuffix(".app") {
                found.append(fullPath)
            } else if remainingDepth > 0 {
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue {
                    found.append(contentsOf: findAppBundles(inDirectory: fullPath, remainingDepth: remainingDepth - 1))
                }
            }
        }
        return found
    }

    private static func makeAppItem(path: String) -> AppItem? {
        let url = URL(fileURLWithPath: path)
        let icon = NSWorkspace.shared.icon(forFile: path)
        let fallbackName = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")

        guard let bundle = Bundle(url: url) else {
            return AppItem(name: fallbackName, bundleIdentifier: nil, version: nil, path: path, architecture: .unknown, icon: icon)
        }

        let name = (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? fallbackName
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String

        guard let executableURL = bundle.executableURL else {
            return AppItem(name: name, bundleIdentifier: bundle.bundleIdentifier, version: version, path: path, architecture: .unknown, icon: icon)
        }

        let cpuTypes = MachOReader.cpuTypes(atPath: executableURL.path)
        let architecture = MachOReader.architecture(forCPUTypes: cpuTypes)

        return AppItem(name: name, bundleIdentifier: bundle.bundleIdentifier, version: version, path: path, architecture: architecture, icon: icon)
    }
}
