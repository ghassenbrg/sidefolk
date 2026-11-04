import AppKit
import KeyboardShortcuts
import SidefolkCore
import SwiftUI

extension KeyboardShortcuts.Name {
    /// ⌃⌥F by default (D152), and only while the ring is on: the combination stays other apps' the rest of the time.
    static let fileRing = Self("fileRing", default: .init(.f, modifiers: [.control, .option]))
}

/// The ring of what a file can become (D152). While it's on, a pressed mouse button starts a look at the system's drag: only its change
/// count, which says nothing of what's in it, until the person holds the key. Then the file list is read, and the ring opens. Nothing reaches
/// an extension until a file is let go on a slice or a slice is clicked. No key or mouse data is kept, and it needs no permission: the key
/// comes from the modifier state any app can see. Off, there's no watcher at all.
@MainActor final class FileRingController {
    let model = FileRingModel()
    /// What these files can become.
    var choicesFor: ([String]) -> [RingChoice] = { _ in [] }
    /// The person chose: run it, as the card's choice does.
    var choose: (RingChoice, [URL]) -> Void = { _, _ in }
    var packPicture: (String, String) async -> NSImage? = { _, _ in nil }
    /// Says something in Ask, for what only words can answer.
    var say: (String) -> Void = { _ in }

    private lazy var panel = makePanel()
    private var surface: FileRingSurface?
    private var key: FileRingSettings.DragKey = .option
    private var downMonitor: Any?
    private var openMonitors: [Any] = []
    private var tick: Timer?
    private var changeAtPress = 0
    private var shiftWasDown = false
    private var openedAt = Date.distantPast
    private var urls: [URL] = []
    private(set) var isOn = false

    var isOpen: Bool { panel.isVisible }

    func apply(_ settings: FileRingSettings) {
        key = settings.dragKey
        #if DEBUG
        // A test run never watches: the mouse and keys are those of whoever is using this Mac.
        if WindowActivation.quiet { return }
        #endif
        guard settings.enabled != isOn else { return }
        isOn = settings.enabled
        if isOn {
            downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                MainActor.assumeIsolated { self?.pressed() }
            }
            KeyboardShortcuts.onKeyDown(for: .fileRing) { [weak self] in self?.shortcutPressed() }
            if CardShortcut.conflict(KeyboardShortcuts.getShortcut(for: .fileRing)) == nil { KeyboardShortcuts.enable(.fileRing) }
        } else {
            if let downMonitor { NSEvent.removeMonitor(downMonitor) }
            downMonitor = nil
            KeyboardShortcuts.disable(.fileRing)
            stopWatching()
            close()
        }
    }

    // MARK: A drag

    private func pressed() {
        changeAtPress = NSPasteboard(name: .drag).changeCount
        stopWatching()
        // Only while the button stays down: at most ten quick looks a second, and none at all between presses.
        tick = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.look() }
        }
    }

    private func stopWatching() {
        tick?.invalidate()
        tick = nil
    }

    private func look() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            stopWatching()
            // A drop on a slice has just run, on the same turn of the loop or the one before.
            if isOpen, !model.byClick { close() }
            return
        }
        if isOpen {
            let shift = NSEvent.modifierFlags.contains(.shift)
            if shift, !shiftWasDown { model.turn() }
            shiftWasDown = shift
            return
        }
        guard NSPasteboard(name: .drag).changeCount != changeAtPress, NSEvent.modifierFlags.contains(key.flag) else { return }
        let board = NSPasteboard(name: .drag)
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            // Not files: nothing to do for this drag, and nothing to read again.
            stopWatching()
            return
        }
        open(urls, byClick: false)
    }

    // MARK: The shortcut

    private func shortcutPressed() {
        if isOpen { return close() }
        guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == "com.apple.finder" else {
            return say(String(localized: "Select a file in Finder first, then press the shortcut.", comment: "The ring's shortcut, from another app"))
        }
        switch FinderSelection.read() {
        case .files(let urls) where !urls.isEmpty: open(urls, byClick: true)
        case .files: say(String(localized: "Select a file in Finder first, then press the shortcut.", comment: "The ring's shortcut, from another app"))
        case .notAllowed: say(String(localized: "Sidefolk can't see what's selected in Finder yet. Turn it on in System Settings › Privacy & Security › Automation.", comment: "The ring's shortcut, when macOS's Automation permission was refused"))
        case .failed: say(String(localized: "Finder didn't answer. Try again in a moment.", comment: "The ring's shortcut, when Finder is busy"))
        }
    }

    // MARK: Open and close

    func open(_ urls: [URL], byClick: Bool) {
        self.urls = urls
        model.files = urls.map(\.path)
        model.choices = choicesFor(model.files)
        model.nothing = model.choices.isEmpty
        model.set = 0
        model.hovered = nil
        model.byClick = byClick
        shiftWasDown = NSEvent.modifierFlags.contains(.shift)
        openedAt = Date()
        #if DEBUG
        // A test's ring: off every screen and taking nothing, or it would open under the hand of whoever is using this Mac, and take their clicks and keys.
        if testing {
            panel.ignoresMouseEvents = true
            panel.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            panel.orderFrontRegardless()
            return
        }
        #endif
        place(at: NSEvent.mouseLocation)
        panel.orderFrontRegardless()
        if byClick { panel.makeKey() }
        openMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.scrolled(event) }
        } as Any)
        if byClick {
            // A click anywhere else closes it, as a menu does.
            openMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            } as Any)
        }
        if model.nothing {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(byClick ? 2.5 : 4))
                self?.close()
            }
        }
    }

    func close() {
        for monitor in openMonitors { NSEvent.removeMonitor(monitor) }
        openMonitors = []
        panel.orderOut(nil)
        model.hovered = nil
        urls = []
    }

    private var scrollSum = 0.0

    private func scrolled(_ event: NSEvent) {
        scrollSum += event.scrollingDeltaY
        if abs(scrollSum) > 12 {
            scrollSum = 0
            model.turn()
        }
    }

    /// Centred on the pointer, but whole on the screen: a corner moves the ring, so every slice stays reachable.
    private func place(at point: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(origin: .zero, size: RingLayout.size)
        var origin = NSPoint(x: point.x - RingLayout.side / 2, y: point.y - RingLayout.side / 2 - RingLayout.below)
        origin.x = min(max(origin.x, area.minX), area.maxX - RingLayout.size.width)
        origin.y = min(max(origin.y, area.minY), area.maxY - RingLayout.size.height)
        panel.setFrameOrigin(origin)
    }

    private func makePanel() -> FileRingPanel {
        let panel = FileRingPanel()
        let surface = FileRingSurface(frame: NSRect(origin: .zero, size: RingLayout.size))
        let host = NSHostingView(rootView: FileRingView(model: model, packPicture: { [weak self] in await self?.packPicture($0, $1) }))
        host.frame = surface.bounds
        host.autoresizingMask = [.width, .height]
        surface.addSubview(host)
        panel.contentView = surface
        surface.locate = { [weak self] point in
            guard let self, !self.model.nothing else { return nil }
            return RingGeometry.slice(dx: point.x - RingLayout.side / 2, dy: point.y - RingLayout.below - RingLayout.side / 2, count: self.model.shown.count,
                                      inner: Double(RingLayout.inner), outer: Double(RingLayout.outer))
        }
        surface.hover = { [weak self] in self?.model.hovered = $0 }
        surface.clicked = { [weak self] in self?.click() }
        surface.dropped = { [weak self] urls in self?.dropped(urls) ?? false }
        panel.onKey = { [weak self] in self?.pressedKey($0) ?? false }
        self.surface = surface
        return panel
    }

    private func dropped(_ dropped: [URL]) -> Bool {
        // Exactly what the ring said it would read. Another list, from a drag that changed under it, isn't what the person saw.
        guard Set(dropped.map(\.path)) == Set(urls.map(\.path)), let choice = model.hoveredChoice else {
            close()
            return false
        }
        let urls = urls
        close()
        choose(choice, urls)
        return true
    }

    /// The first moment doesn't count: the ring opens under a pointer that may be on its way somewhere else.
    private func click() {
        guard model.byClick, Date().timeIntervalSince(openedAt) > 0.4, let choice = model.hoveredChoice else { return }
        let urls = urls
        close()
        choose(choice, urls)
    }

    private func pressedKey(_ event: NSEvent) -> Bool {
        let count = model.shown.count
        guard count > 0 else {
            if event.keyCode == 53 { close() }
            return true
        }
        switch event.keyCode {
        case 53: close()
        case 48: model.turn()
        case 124, 125: model.hovered = ((model.hovered ?? -1) + 1) % count
        case 123, 126: model.hovered = ((model.hovered ?? 0) - 1 + count) % count
        case 36, 76: click()
        default: return false
        }
        return true
    }

    #if DEBUG
    private var testing = false

    /// The debug app's `ring:` commands, as a person's hand would.
    func dev(_ command: String) {
        testing = true
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "open": open((parts.last ?? "").split(separator: "|").map { URL(fileURLWithPath: String($0)) }, byClick: true)
        case "drag": open((parts.last ?? "").split(separator: "|").map { URL(fileURLWithPath: String($0)) }, byClick: false)
        case "hover": model.hovered = Int(parts.last ?? "")
        case "more": model.turn()
        case "choose":
            model.hovered = Int(parts.last ?? "") ?? model.hovered
            openedAt = .distantPast
            model.byClick = true
            click()
        case "close": close()
        default: Log.shared.warning("dev", "no such ring command", ["command": command])
        }
    }
    #endif
}

extension FileRingSettings.DragKey {
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .option: .option
        case .control: .control
        case .shift: .shift
        case .command: .command
        }
    }

    /// As a keycap reads it.
    var keycap: String {
        switch self {
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .shift: "⇧ Shift"
        case .command: "⌘ Command"
        }
    }
}

/// What's selected in Finder, asked only when the person presses the ring's shortcut with Finder in front. macOS asks once whether Sidefolk may.
enum FinderSelection {
    enum Answer { case files([URL]), notAllowed, failed }

    static func read() -> Answer {
        let source = """
        with timeout of 2 seconds
            tell application id "com.apple.finder"
                set out to {}
                repeat with one in (get selection)
                    set end of out to POSIX path of (one as alias)
                end repeat
                return out
            end tell
        end timeout
        """
        var problem: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failed }
        let answer = script.executeAndReturnError(&problem)
        if let code = problem?[NSAppleScript.errorNumber] as? Int { return code == -1743 ? .notAllowed : .failed }
        guard answer.numberOfItems > 0 else { return .files([]) }
        return .files((1...answer.numberOfItems).compactMap { answer.atIndex($0)?.stringValue.map { URL(fileURLWithPath: $0) } })
    }
}
