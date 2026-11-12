import AppKit
import CryptoKit
import Foundation
import LogKit
import os
import Security

/// Installs a version found by `NativeVersionChecker` over the installed app.
///
/// - **Homebrew**: `brew upgrade --cask` when Homebrew manages the app,
///   otherwise `brew install --cask --force`, which replaces the copy in
///   /Applications. A copy elsewhere moves to the Trash once the new one is in.
/// - **Update feed**: downloads the archive, checks its EdDSA signature
///   against the app's own SUPublicEDKey (as Sparkle would), unpacks it, and
///   requires a valid code signature from the same developer team as the
///   installed app. Only then does the old copy move to the Trash.
/// - **App Store**: opens the app's page; the App Store does the update.
actor AppInstaller {
    static let shared = AppInstaller()

    typealias Progress = @MainActor @Sendable (String) -> Void

    nonisolated static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Returns where the old copy went in the Trash, when it can be put back.
    @discardableResult
    func install(_ method: UpdateMethod, for app: AppItem, progress: Progress) async throws -> URL? {
        switch method {
        case .homebrew(let token):
            return try await installWithHomebrew(token: token, app: app, progress: progress)
        case .download(let download):
            return try await installDownload(download, app: app, progress: progress)
        case .appStore(let url):
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "macappstore"
            let storeURL = components?.url ?? url
            await MainActor.run { _ = NSWorkspace.shared.open(storeURL) }
            return nil
        }
    }

    /// Undoes an update: the new copy goes to the Trash and the old one comes back to its path.
    func putBack(oldCopy: URL, at path: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: oldCopy.path) else {
            throw InstallError("The old copy is no longer in the Trash.")
        }
        let destination = URL(filePath: path)
        if fm.fileExists(atPath: path) {
            do {
                try fm.trashItem(at: destination, resultingItemURL: nil)
            } catch {
                throw InstallError("Couldn't move the new copy to the Trash: \(error.localizedDescription)")
            }
        }
        do {
            try fm.moveItem(at: oldCopy, to: destination)
        } catch {
            throw InstallError("Couldn't put the old copy back: \(error.localizedDescription)")
        }
    }

    // MARK: - Homebrew

    private func installWithHomebrew(token: String, app: AppItem, progress: Progress) async throws -> URL? {
        guard let brew = Self.brewPath else {
            throw InstallError("Homebrew isn't installed. Get it from brew.sh, or download \(app.name) from its website.", terminalCommand: nil)
        }
        try await quitIfRunning(app, progress: progress)

        let managed = try await ProcessRunner.run(brew, ["list", "--cask", token]).status == 0
        let arguments = managed ? ["upgrade", "--cask", token] : ["install", "--cask", "--force", token]
        let command = "brew " + arguments.joined(separator: " ")
        await progress(managed ? "Upgrading…" : "Installing…")
        AppLog.post(.info, "\(app.name): running \(command)", source: "Homebrew")

        // A copy Homebrew doesn't manage goes to the Trash first, so the update can be undone
        // (--force would delete it). It comes back if brew fails.
        var trashed: URL?
        if !managed {
            var resulting: NSURL?
            try? FileManager.default.trashItem(at: URL(filePath: app.path), resultingItemURL: &resulting)
            trashed = resulting as URL?
        }
        func restore() {
            if let trashed, !FileManager.default.fileExists(atPath: app.path) {
                try? FileManager.default.moveItem(at: trashed, to: URL(filePath: app.path))
            }
        }

        let result = try await ProcessRunner.run(brew, arguments, environment: [
            "HOMEBREW_NO_ENV_HINTS": "1",
            "NONINTERACTIVE": "1",
        ]) { line in
            let level: LogLevel = line.hasPrefix("Error") ? .error : line.hasPrefix("Warning") ? .warning : .info
            AppLog.post(level, line, source: "Homebrew")
        }
        guard result.status == 0 else {
            restore()
            let reason = result.output.contains("sudo") || result.output.contains("password")
                ? "This cask needs your administrator password."
                : (result.output.split(separator: "\n").last { $0.hasPrefix("Error") }.map(String.init) ?? "brew stopped with code \(result.status).")
            throw InstallError("\(reason) Run it in Terminal to finish.", terminalCommand: "\(brew) \(arguments.joined(separator: " "))")
        }

        // Homebrew installs into /Applications; a copy somewhere else is now the old one.
        let installedPath = "/Applications/\(app.bundleFileName)"
        guard Bundle(path: installedPath)?.bundleIdentifier == app.bundleIdentifier else {
            // The cask put the app under another name: keep the old copy where it was.
            restore()
            AppLog.post(.warning, "Homebrew finished, but \(app.bundleFileName) isn't in /Applications", source: "Homebrew")
            return nil
        }
        if trashed == nil, app.path != installedPath {
            var resulting: NSURL?
            try? FileManager.default.trashItem(at: URL(filePath: app.path), resultingItemURL: &resulting)
            trashed = resulting as URL?
        }
        if trashed != nil {
            AppLog.post(.info, "Moved the old copy of \(app.name) at \(app.path) to the Trash", source: "Homebrew")
        }
        return trashed
    }

    // MARK: - Download from the app's feed

    private func installDownload(_ download: SparkleDownload, app: AppItem, progress: Progress) async throws -> URL? {
        let work = FileManager.default.temporaryDirectory.appending(path: "SiliconScope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        var mountPoint: URL?
        defer {
            if let mountPoint { _ = try? ProcessRunner.runSync("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force", "-quiet"]) }
            try? FileManager.default.removeItem(at: work)
        }

        await progress("Downloading…")
        AppLog.post(.info, "\(app.name): downloading \(download.url.absoluteString)", source: "Update Feed")
        let (temporary, response) = try await URLSession.shared.download(from: download.url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw InstallError("The download answered HTTP \(http.statusCode).")
        }
        let fileName = download.url.lastPathComponent.isEmpty ? "update" : download.url.lastPathComponent
        let archive = work.appending(path: fileName)
        try FileManager.default.moveItem(at: temporary, to: archive)

        await progress("Checking…")
        let feedSigned = try verifyEdSignature(archive: archive, download: download, app: app)

        let extracted = work.appending(path: "extracted")
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        let lowercased = fileName.lowercased()
        let searchRoot: URL
        if lowercased.hasSuffix(".zip") {
            try runChecked("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path], what: "unzip the download")
            searchRoot = extracted
        } else if lowercased.hasSuffix(".dmg") {
            let mount = work.appending(path: "mount")
            try runChecked("/usr/bin/hdiutil", ["attach", archive.path, "-nobrowse", "-readonly", "-noautoopen",
                                                "-mountpoint", mount.path], input: "Y\n", what: "open the disk image")
            mountPoint = mount
            searchRoot = mount
        } else if [".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz", ".tar.xz"].contains(where: lowercased.hasSuffix) {
            try runChecked("/usr/bin/tar", ["-xf", archive.path, "-C", extracted.path], what: "unpack the download")
            searchRoot = extracted
        } else {
            throw InstallError("\(app.name) ships its update as “\(fileName)”, which SiliconScope can't install. Use Open Download Page.")
        }

        guard let newApp = findApp(in: searchRoot, bundleIdentifier: app.bundleIdentifier) else {
            throw InstallError("The download doesn't contain \(app.bundleFileName).")
        }
        try verifyCodeSignature(newApp: newApp, oldApp: URL(filePath: app.path), feedSigned: feedSigned)

        try await quitIfRunning(app, progress: progress)
        await progress("Installing…")
        let trashed = try replace(old: URL(filePath: app.path), with: newApp)
        AppLog.post(.info, "\(app.name) \(download.version) installed; the old copy is in the Trash", source: "Update Feed")
        return trashed
    }

    /// Checks the archive the way Sparkle does. Returns whether it was checked.
    private func verifyEdSignature(archive: URL, download: SparkleDownload, app: AppItem) throws -> Bool {
        guard let signature = download.edSignature.flatMap({ Data(base64Encoded: $0) }),
              let keyData = app.updateFeedPublicKey.flatMap({ Data(base64Encoded: $0) }) else { return false }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard key.isValidSignature(signature, for: data) else {
            throw InstallError("The download isn't signed with \(app.name)'s update key, so it wasn't installed.")
        }
        return true
    }

    private func verifyCodeSignature(newApp: URL, oldApp: URL, feedSigned: Bool) throws {
        guard CodeSignature.isValid(newApp) else {
            throw InstallError("The downloaded app's code signature isn't valid, so it wasn't installed.")
        }
        let oldTeam = CodeSignature.teamIdentifier(oldApp)
        let newTeam = CodeSignature.teamIdentifier(newApp)
        if let oldTeam {
            guard newTeam == oldTeam else {
                throw InstallError("The downloaded app is signed by another developer (\(newTeam ?? "none") instead of \(oldTeam)), so it wasn't installed.")
            }
        } else if !feedSigned {
            throw InstallError("Neither the installed app nor its feed can prove the download comes from the same developer. Use Open Download Page.")
        }
    }

    private func findApp(in root: URL, bundleIdentifier: String?) -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        for level1 in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            if level1.pathExtension == "app" { candidates.append(level1); continue }
            for level2 in (try? fm.contentsOfDirectory(at: level1, includingPropertiesForKeys: nil)) ?? [] where level2.pathExtension == "app" {
                candidates.append(level2)
            }
        }
        return candidates.first { Bundle(url: $0)?.bundleIdentifier == bundleIdentifier }
    }

    /// Moves the old copy to the Trash and puts the new one at its path, or puts the old one back.
    /// Returns where the old copy went in the Trash.
    private func replace(old: URL, with new: URL) throws -> URL? {
        let fm = FileManager.default
        var trashed: NSURL?
        do {
            try fm.trashItem(at: old, resultingItemURL: &trashed)
        } catch {
            throw InstallError("Couldn't move the old copy to the Trash: \(error.localizedDescription)")
        }
        do {
            try runChecked("/usr/bin/ditto", [new.path, old.path], what: "copy the new version")
        } catch {
            try? fm.removeItem(at: old)
            if let trashed = trashed as URL? { try? fm.moveItem(at: trashed, to: old) }
            throw error
        }
        return trashed as URL?
    }

    // MARK: - Helpers

    private func quitIfRunning(_ app: AppItem, progress: Progress) async throws {
        let running = await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier ?? "")
                .filter { $0.bundleURL?.standardizedFileURL.path == URL(filePath: app.path).standardizedFileURL.path }
                .map(\.processIdentifier)
        }
        guard !running.isEmpty else { return }
        await progress("Quitting \(app.name)…")
        await MainActor.run {
            for pid in running { NSRunningApplication(processIdentifier: pid)?.terminate() }
        }
        for _ in 0..<40 {
            let stillRunning = await MainActor.run { running.contains { NSRunningApplication(processIdentifier: $0) != nil } }
            if !stillRunning { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw InstallError("\(app.name) didn't quit. Quit it, then update again.")
    }

    private func runChecked(_ tool: String, _ arguments: [String], input: String? = nil, what: String) throws {
        let result = try ProcessRunner.runSync(tool, arguments, input: input)
        guard result.status == 0 else {
            throw InstallError("Couldn't \(what): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}

struct InstallError: LocalizedError {
    let message: String
    /// A command that finishes the job in Terminal, when there is one.
    let terminalCommand: String?
    init(_ message: String, terminalCommand: String? = nil) {
        self.message = message
        self.terminalCommand = terminalCommand
    }
    var errorDescription: String? { message }
}

// MARK: - Code signatures

enum CodeSignature {
    static func isValid(_ url: URL) -> Bool {
        guard let code = staticCode(url) else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
    }

    static func teamIdentifier(_ url: URL) -> String? {
        guard let code = staticCode(url) else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func staticCode(_ url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess else { return nil }
        return code
    }
}

// MARK: - Running tools

enum ProcessRunner {
    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    /// Runs a tool without blocking, passing each output line to `onLine` as it comes.
    static func run(_ tool: String, _ arguments: [String], environment: [String: String] = [:],
                    onLine: (@Sendable (String) -> Void)? = nil) async throws -> Result {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env.merge(environment) { _, new in new }
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let buffer = OSAllocatedUnfairLock(initialState: (all: "", partial: ""))
        pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let chunk = String(decoding: handle.availableData, as: UTF8.self)
            let lines: [String] = buffer.withLock { state in
                state.all += chunk
                state.partial += chunk
                var parts = state.partial.components(separatedBy: "\n")
                state.partial = parts.removeLast()
                return parts
            }
            for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty { onLine?(line) }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { @Sendable finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let (output, last) = buffer.withLock { state in
                    state.all += rest
                    return (state.all, state.partial + rest)
                }
                if !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { onLine?(last) }
                continuation.resume(returning: Result(status: finished.terminationStatus, output: output))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// Runs a short tool and waits for it (unzipping, mounting).
    static func runSync(_ tool: String, _ arguments: [String], input: String? = nil) throws -> Result {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let inputPipe = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : inputPipe
        try process.run()
        if let input {
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inputPipe.fileHandleForWriting.close()
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
