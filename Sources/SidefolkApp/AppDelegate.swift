import AppKit
import SidefolkCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    /// The quit work is done (or must be skipped), so terminating doesn't wait for it again.
    private var readyToQuit = false

    /// Quitting from code. Called from inside a task or a main-queue callback, `terminate` with
    /// `.terminateLater` would wait for a task that can't start until that caller returns, and the app
    /// would hang. So the quit work runs first, then termination goes straight through.
    /// - Parameter prepare: false when there is nothing to hand over: a second copy that must leave the
    ///   first one's reminders alone, or data that was just deleted.
    static func quit(prepare: Bool = true) {
        let delegate = NSApp.delegate as? AppDelegate
        Task { @MainActor in
            if prepare, let delegate, !delegate.readyToQuit, let coordinator = delegate.coordinator {
                await coordinator.prepareForQuit()
            }
            delegate?.readyToQuit = true
            NSApp.terminate(nil)
        }
    }

    @objc func showAbout(_ sender: Any?) { coordinator?.showAbout() }

    @objc func openSettings(_ sender: Any?) { coordinator?.openSettings() }
    @objc func openAsk(_ sender: Any?) { coordinator?.showAsk() }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Files Sidefolk creates are private to the user (docs/SECURITY.md T6, T19).
        umask(0o077)
        NSApp.mainMenu = MainMenu.make()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let paths = SidefolkPaths.standard()
        Log.shared.configure(directory: paths.logs, debug: false)
        Log.shared.info("app", "launch", ["version": SidefolkVersion.current, "home": paths.home.path])
        Task {
            do {
                let secrets = KeychainSecretStore()
                let runtime = try await SidefolkRuntime.open(
                    paths: paths, platform: MacPlatform(), bundledResources: ResourceLocator.resources,
                    extensionSecrets: { server in MCPServerSecrets.environment(for: server, store: secrets) })
                Log.shared.setDebug(runtime.settings.current.debugLogging)
                #if DEBUG
                DebugSnapshots.install(home: paths.home)
                #endif
                let coordinator = AppCoordinator(runtime: runtime)
                self.coordinator = coordinator
                await coordinator.start()
            } catch {
                Log.shared.error("app", "launch failed", ["error": String(describing: error)])
                StartupFailure.show(error: error, dataFolder: paths.home)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.openHome()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // The user quit (menu, ⌘Q, logout): this runs from event handling, so the task below can run.
        guard let coordinator, !readyToQuit else { return .terminateNow }
        Task {
            await coordinator.prepareForQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// When the database can't be opened, say so plainly and keep the user's data untouched.
enum StartupFailure {
    static func show(error: Error, dataFolder: URL) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Sidefolk couldn't start"
        alert.informativeText = """
            Sidefolk couldn't open its data folder. Nothing was deleted or changed.

            Try restarting your Mac. If this keeps happening, export diagnostics from \
            ~/Library/Logs/Sidefolk and check the data folder at \(FolderAccess.displayPath(dataFolder.path)).
            """
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Show Data Folder")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([dataFolder])
        }
        NSApp.terminate(nil)
    }
}

/// A minimal main menu so standard editing shortcuts work in Sidefolk's text fields.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Sidefolk", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Ask Sidefolk…", action: #selector(AppDelegate.openAsk(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Sidefolk", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Sidefolk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }
}
