import AppKit

/// Small, reusable Finder/pasteboard actions shared by app and process rows.
enum FileActions {
    static func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Opens Terminal running `command`, for steps that need a password.
    static func runInTerminal(_ command: String) {
        let script = FileManager.default.temporaryDirectory.appending(path: "SiliconScope-\(UUID().uuidString).command")
        let contents = "#!/bin/zsh\n\(command)\necho\necho 'Done. You can close this window and rescan in SiliconScope (⌘R).'\n"
        do {
            try contents.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch {
            copyToPasteboard(command)
        }
    }

    static func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
