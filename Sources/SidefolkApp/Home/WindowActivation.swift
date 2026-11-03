import AppKit

/// Sidefolk is an accessory app (no Dock icon) until one of its normal windows is open. While Home
/// or Settings is open it becomes a regular app so ⌘Tab and the Dock reach it; when the last one
/// closes it goes back to the menu bar and hands focus to the app the user came from.
/// See docs/MACOS-NOTES.md §2 and §13.2.
@MainActor
enum WindowActivation {
    private static var open: Set<ObjectIdentifier> = []
    private static var previous: NSRunningApplication?

    private static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    #if DEBUG
    /// A test run's windows stay out of the person's way (AGENTS.md): drawn off-screen, as the snapshots are, so they still
    /// lay out and `snap` still reads them, with nothing brought forward. Clicks and keys need a run without it.
    private static let quiet = ProcessInfo.processInfo.environment["SIDEFOLK_QUIET_WINDOWS"] == "1"
    #endif

    /// Call when a window is shown on the user's request (menu, hotkey, click).
    static func show(_ window: NSWindow) {
        #if DEBUG
        if quiet {
            // Not remembered, or the next run opens off-screen too.
            window.setFrameAutosaveName("")
            // Moved after it's up, unseen until then: AppKit brings a titled window back on screen as it's ordered in.
            window.alphaValue = 0
            window.orderFrontRegardless()
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            window.alphaValue = 1
            return
        }
        #endif
        if !isFrontmost { previous = NSWorkspace.shared.frontmostApplication }
        open.insert(ObjectIdentifier(window))
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        Task { @MainActor in
            // A menu-bar app's window may open inside another app's full-screen space, and the switch to a regular app
            // takes effect a moment later. Waiting also keeps the menu bar from going stale.
            await untilRegular()
            NSApp.activate()
            CompanionAppIcon.reapply()
            window.makeKeyAndOrderFront(nil)
        }
    }

    private static func untilRegular() async {
        let current = NSRunningApplication.current
        let giveUp = ContinuousClock.now + .seconds(1)
        while current.activationPolicy != .regular, ContinuousClock.now < giveUp {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Call from `windowWillClose`.
    static func closed(_ window: NSWindow) {
        guard open.remove(ObjectIdentifier(window)) != nil, open.isEmpty else { return }
        let wasFrontmost = isFrontmost
        NSApp.setActivationPolicy(.accessory)
        // Only hand focus back when the user closed us while working in Sidefolk.
        if wasFrontmost, let previous, !previous.isTerminated {
            NSApp.yieldActivation(to: previous)
            previous.activate(from: .current, options: [])
        }
        previous = nil
    }
}
