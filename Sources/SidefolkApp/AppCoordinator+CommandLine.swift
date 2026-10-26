import AppKit
import SidefolkCore

/// Puts the `sidefolk` command on the user's PATH (only on their click, after confirmation).
extension AppCoordinator {
    static var commandLineToolPath: String { NSHomeDirectory() + "/.local/bin/sidefolk" }

    var commandLineToolInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: Self.commandLineToolPath)) == stableHelperPath
    }

    func installCommandLineTool() async -> UserFacingError? {
        installHelperLink()
        let fm = FileManager.default
        let target = Self.commandLineToolPath
        let existingLink = try? fm.destinationOfSymbolicLink(atPath: target)
        if fm.fileExists(atPath: target), existingLink == nil {
            return UserFacingError("~/.local/bin/sidefolk already exists and isn't Sidefolk's.", recovery: "Remove or rename it, then try again.")
        }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Install the sidefolk command?")
        alert.informativeText = String(localized: """
            Adds a link at ~/.local/bin/sidefolk so you can type “sidefolk run -- npm test” in a terminal. \
            Nothing else changes. If ~/.local/bin isn't on your PATH, add this line to ~/.zshrc:
            """) + "\nexport PATH=\"$HOME/.local/bin:$PATH\""
        alert.addButton(withTitle: String(localized: "Install"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        do {
            try fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if existingLink != nil { try fm.removeItem(atPath: target) }
            try fm.createSymbolicLink(atPath: target, withDestinationPath: stableHelperPath)
            runtime.events.changed(.settings)
            return nil
        } catch {
            return UserFacingError("I couldn't add the sidefolk command.", detail: String(describing: error))
        }
    }

    func removeCommandLineTool() async -> UserFacingError? {
        guard commandLineToolInstalled else { return nil }
        do {
            try FileManager.default.removeItem(atPath: Self.commandLineToolPath)
            runtime.events.changed(.settings)
            return nil
        } catch {
            return UserFacingError("I couldn't remove ~/.local/bin/sidefolk.", detail: String(describing: error))
        }
    }
}
