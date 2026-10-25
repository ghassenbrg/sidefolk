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

    /// Call when a window is shown on the user's request (menu, hotkey, click).
    static func show(_ window: NSWindow) {
        if !isFrontmost { previous = NSWorkspace.shared.frontmostApplication }
        open.insert(ObjectIdentifier(window))
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        // Activating in the same turn as the policy switch can leave a stale menu bar.
        Task { @MainActor in
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
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
