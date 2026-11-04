import AppKit
import KeyboardShortcuts
import SidefolkCore
import SwiftUI

extension KeyboardShortcuts.Name {
    /// No default here: naming one takes the keys from every app as soon as anything touches this name. ⌃⌥F is set when the ring is first turned on.
    static let fileRing = Self("fileRing")
}

/// The ring of what a file can become (D152). While it's on, a pressed mouse button starts a look at the system's drag: only its change
/// count, which says nothing of what's in it, until the person holds the key with the pointer at rest. Then the file list is read, and the
/// ring opens. Nothing reaches an extension until a file is let go on a slice or a slice is clicked. No key or mouse data is kept, and it
/// needs no permission: the key comes from the modifier state any app can see. Off, there's no watcher at all.
@MainActor final class FileRingController {
    /// A drag this long still at the key opens the ring: ⌥ is also how Finder copies, and a copy on its way somewhere shouldn't meet one.
    private static let rest: TimeInterval = 0.35
    /// The system may deliver a drop a moment after the button's up, so the ring waits for it.
    private static let dropGrace: Duration = .milliseconds(600)

    let model = FileRingModel()
    /// What these files can become.
    var choicesFor: ([String]) -> [RingChoice] = { _ in [] }
    /// The person chose: run it, as the card's choice does.
    var choose: (RingChoice, [URL]) -> Void = { _, _ in }
    /// More files than a ring can name: the card shows every one.
    var toCard: ([URL]) -> Void = { _ in }
    var packPicture: (String, String) async -> NSImage? = { _, _ in nil }
    /// Says something in Ask, for what only words can answer.
    var say: (String) -> Void = { _ in }

    private lazy var panel = makePanel()
    private var key: FileRingSettings.DragKey = .option
    private var downMonitor: Any?
    private var openMonitors: [Any] = []
    private var tick: Timer?
    private var changeAtPress = 0
    private var openedThisPress = false
    private var shiftWasDown = false
    private var keyUpSince: Date?
    private var lastPoint = NSPoint.zero
    private var stillSince = Date()
    private var openedAt = Date.distantPast
    private var aim = RingAim(openedAt: 0, x: 0, y: 0)
    private var urls: [URL] = []
    private var closing: Task<Void, Never>?
    private var noteTimer: Task<Void, Never>?
    private var readingFinder = false
    private var handlerInstalled = false
    private var scrollSum = 0.0
    private var scrollTurned = false
    /// On a slice at all, lit or not.
    private var overSlice = false
    private(set) var isOn = false
    /// Sidefolk's other keys, palettes' among them.
    var otherKeys: () -> [KeyboardShortcuts.Shortcut] = { [] }

    var isOpen: Bool { panel.isVisible }

    func apply(_ settings: FileRingSettings) {
        key = settings.dragKey
        #if DEBUG
        // A test run never watches: the mouse and keys are those of whoever is using this Mac.
        if WindowActivation.quiet { return }
        #endif
        if settings.enabled != isOn {
            isOn = settings.enabled
            if isOn {
                if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
                    MainActor.assumeIsolated { self?.pressed() }
                }) { downMonitor = monitor }
                offerTheShortcutOnce()
                if !handlerInstalled {
                    // Handlers add up and turning off doesn't remove them, so there's only ever this one.
                    handlerInstalled = true
                    KeyboardShortcuts.onKeyDown(for: .fileRing) { [weak self] in self?.shortcutPressed() }
                }
            } else {
                if let downMonitor { NSEvent.removeMonitor(downMonitor) }
                downMonitor = nil
                stopWatching()
                close()
            }
        }
        // `disable` unregisters by keys, not by name: never for keys another of Sidefolk's shortcuts holds, or that one dies too.
        let keys = KeyboardShortcuts.getShortcut(for: .fileRing)
        if isOn, conflict == nil {
            KeyboardShortcuts.enable(.fileRing)
        } else if !sharedWithSidefolk(keys) {
            KeyboardShortcuts.disable(.fileRing)
        }
    }

    private func sharedWithSidefolk(_ keys: KeyboardShortcuts.Shortcut?) -> Bool {
        guard let keys else { return false }
        return keys == KeyboardShortcuts.getShortcut(for: .ask) || keys == KeyboardShortcuts.getShortcut(for: .talk)
            || keys == KeyboardShortcuts.getShortcut(for: .answerCard) || otherKeys().contains(keys)
    }

    /// Why its shortcut is off, in words for the page.
    var conflict: CardShortcut.Conflict? {
        let keys = KeyboardShortcuts.getShortcut(for: .fileRing)
        if let found = CardShortcut.conflict(keys) { return found }
        return sharedWithSidefolk(keys) ? .sidefolk : nil
    }

    private func offerTheShortcutOnce() {
        let asked = "fileRing.shortcutOffered"
        guard !UserDefaults.standard.bool(forKey: asked) else { return }
        UserDefaults.standard.set(true, forKey: asked)
        if KeyboardShortcuts.getShortcut(for: .fileRing) == nil {
            KeyboardShortcuts.setShortcut(.init(.f, modifiers: [.control, .option]), for: .fileRing)
        }
    }

    // MARK: A drag

    private func pressed() {
        // A new press: whatever the last one left has had its moment.
        if closing != nil { close() }
        changeAtPress = NSPasteboard(name: .drag).changeCount
        openedThisPress = false
        lastPoint = NSEvent.mouseLocation
        stillSince = Date()
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
            if isOpen, !model.byClick { closeSoon() }
            return
        }
        if isOpen {
            lookWhileOpen()
            return
        }
        let point = NSEvent.mouseLocation
        if hypot(point.x - lastPoint.x, point.y - lastPoint.y) > 3 {
            lastPoint = point
            stillSince = Date()
        }
        guard !openedThisPress, NSPasteboard(name: .drag).changeCount != changeAtPress, NSEvent.modifierFlags.contains(key.flag),
              Date().timeIntervalSince(stillSince) >= Self.rest else { return }
        let board = NSPasteboard(name: .drag)
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        // Not files: nothing to do for this drag, and nothing to read again.
        guard !urls.isEmpty else { return stopWatching() }
        openedThisPress = true
        open(urls, byClick: false)
    }

    private func lookWhileOpen() {
        let flags = NSEvent.modifierFlags
        let shift = flags.contains(.shift)
        if shift, !shiftWasDown { turn() }
        shiftWasDown = shift
        // The key let go off any slice: the person changed their mind, and the drag goes on to whatever's under the ring.
        guard !flags.contains(key.flag), !overSlice else {
            keyUpSince = nil
            return
        }
        if let since = keyUpSince {
            if Date().timeIntervalSince(since) > 0.2 { close() }
        } else {
            keyUpSince = Date()
        }
    }

    private func closeSoon() {
        guard closing == nil else { return }
        closing = Task { [weak self] in
            try? await Task.sleep(for: Self.dropGrace)
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    // MARK: The shortcut

    private func shortcutPressed() {
        guard isOn, conflict == nil else { return }
        if isOpen { return close() }
        guard !readingFinder else { return }
        let first = String(localized: "Select a file in Finder first, then press the shortcut.", comment: "The ring's shortcut, from another app")
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return say(first) }
        readingFinder = true
        Task { [weak self] in
            let answer = await FinderSelection.read()
            guard let self else { return }
            self.readingFinder = false
            // It may have taken a while, the first time macOS asks.
            guard self.isOn else { return }
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return self.say(first) }
            switch answer {
            case .files(let paths) where paths.isEmpty: self.say(first)
            case .files(let paths): self.open(paths.map { URL(fileURLWithPath: $0) }, byClick: true)
            case .tooMany: self.say(String(localized: "That's more files than Sidefolk takes at once. Select fewer.", comment: "The ring's shortcut, with a very large selection"))
            case .notAllowed: self.say(String(localized: "Sidefolk can't see what's selected in Finder yet. Turn it on in System Settings › Privacy & Security › Automation.", comment: "The ring's shortcut, when macOS's Automation permission was refused"))
            case .failed: self.say(String(localized: "Finder didn't answer. Try again in a moment.", comment: "The ring's shortcut, when Finder is busy"))
            }
        }
    }

    // MARK: Open and close

    func open(_ urls: [URL], byClick: Bool) {
        closing?.cancel()
        closing = nil
        noteTimer?.cancel()
        let paths = urls.map(\.path), fits = FileRingModel.namesFit(paths)
        let choices = choicesFor(paths)
        // A drag nothing can use is an ordinary drag: no ring in its way.
        if choices.isEmpty, !byClick { return }
        // Every name can be read on a ring of a few files. Past that, the card shows them all.
        if !fits, byClick { return toCard(urls) }
        self.urls = urls
        model.files = paths
        model.choices = fits ? choices : []
        model.note = !fits ? .tooMany : choices.isEmpty ? .nothing : nil
        scrollSum = 0
        scrollTurned = false
        overSlice = false
        model.set = 0
        model.hovered = nil
        model.overMiddle = false
        model.byClick = byClick
        shiftWasDown = NSEvent.modifierFlags.contains(.shift)
        keyUpSince = nil
        openedAt = Date()
        #if DEBUG
        // A test's ring: off every screen and taking nothing, or it would open under the hand of whoever is using this Mac, and take their clicks and keys.
        if testing || WindowActivation.quiet {
            panel.ignoresMouseEvents = true
            panel.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            panel.orderFrontRegardless()
            return
        }
        #endif
        let pointer = NSEvent.mouseLocation
        place(at: pointer)
        // Only words, so a drag goes through them to whatever's underneath.
        panel.ignoresMouseEvents = model.note != nil
        aim = RingAim(openedAt: ProcessInfo.processInfo.systemUptime, x: pointer.x, y: pointer.y)
        panel.orderFrontRegardless()
        // Only words have no use for the keyboard, which stays with the app in front.
        if byClick, model.note == nil { panel.makeKey() }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.scrolled(event) }
        }) { openMonitors.append(monitor) }
        if byClick, let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            // A click anywhere else closes it, as a menu does.
            MainActor.assumeIsolated { self?.close() }
        }) { openMonitors.append(monitor) }
        if model.note != nil {
            noteTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(byClick ? 2.5 : 4))
                guard !Task.isCancelled else { return }
                self?.close()
            }
        }
    }

    func close() {
        closing?.cancel()
        closing = nil
        noteTimer?.cancel()
        noteTimer = nil
        for monitor in openMonitors { NSEvent.removeMonitor(monitor) }
        openMonitors = []
        panel.orderOut(nil)
        model.hovered = nil
        model.overMiddle = false
        // What it drew from the person's file doesn't stay in memory until the next time.
        model.files = []
        model.choices = []
        urls = []
    }

    private func turn() {
        model.turn()
        model.hovered = nil
        aim.turned(at: ProcessInfo.processInfo.systemUptime)
    }

    /// A mouse's notch is one turn. A trackpad's flick is too, however far it glides.
    private func scrolled(_ event: NSEvent) {
        guard event.momentumPhase == [] else { return }
        guard event.hasPreciseScrollingDeltas else {
            if event.scrollingDeltaY != 0 { turn() }
            return
        }
        if event.phase == .began {
            scrollSum = 0
            scrollTurned = false
        }
        scrollSum += event.scrollingDeltaY
        if abs(scrollSum) > 12, !scrollTurned {
            scrollTurned = true
            turn()
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
        surface.follow = { [weak self] point in self?.follow(point) ?? false }
        surface.left = { [weak self] in
            self?.overSlice = false
            self?.model.hovered = nil
            self?.model.overMiddle = false
        }
        surface.clicked = { [weak self] point in
            guard let self, RingGeometry.clickCounts(at: self.slice(at: point), lit: self.model.hovered) else { return }
            self.click()
        }
        surface.scrolled = { [weak self] in self?.scrolled($0) }
        surface.dropped = { [weak self] urls in self?.dropped(urls) ?? false }
        panel.onKey = { [weak self] in self?.pressedKey($0) ?? false }
        return panel
    }

    private func slice(at point: NSPoint) -> Int? {
        RingGeometry.slice(dx: Double(point.x - RingLayout.side / 2), dy: Double(point.y - RingLayout.below - RingLayout.side / 2), count: model.shown.count,
                           inner: Double(RingLayout.inner), outer: Double(RingLayout.outer))
    }

    /// The pointer is at this point in the ring's own view. Returns whether it's on a slice that would take a drop.
    private func follow(_ point: NSPoint) -> Bool {
        guard model.note == nil else { return false }
        let dx = Double(point.x - RingLayout.side / 2), dy = Double(point.y - RingLayout.below - RingLayout.side / 2)
        let index = slice(at: point)
        let screen = NSEvent.mouseLocation, now = ProcessInfo.processInfo.systemUptime
        let aimed = aim.follow(x: screen.x, y: screen.y, slice: index, at: now)
        overSlice = index != nil
        model.overMiddle = hypot(dx, dy) < Double(RingLayout.inner)
        // A click has its own moment. A drag's slice lights when a release would count, and the cursor says so.
        if model.byClick {
            model.hovered = aimed
            return aimed != nil
        }
        model.hovered = aim.ready(at: now)
        return model.hovered != nil
    }

    private func dropped(_ dropped: [URL]) -> Bool {
        // Exactly what the ring said it would read. Another list, from a drag that changed under it, isn't what the person saw.
        guard Set(dropped.map(\.path)) == Set(urls.map(\.path)), aim.ready(at: ProcessInfo.processInfo.systemUptime) != nil, let choice = model.hoveredChoice else {
            close()
            return false
        }
        run(choice)
        return true
    }

    /// The first moment doesn't count: the ring opens under a pointer that may be on its way somewhere else.
    private func click() {
        guard model.byClick, Date().timeIntervalSince(openedAt) > RingAim.leastOpen, let choice = model.hoveredChoice else { return }
        run(choice)
    }

    private func run(_ choice: RingChoice) {
        let urls = urls
        close()
        choose(choice, urls)
    }

    private func pressedKey(_ event: NSEvent) -> Bool {
        let count = model.shown.count
        guard count > 0 else { return false }
        switch event.keyCode {
        case 53: close()
        case 48: turn()
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
        let paths = (parts.last ?? "").split(separator: "|").map { URL(fileURLWithPath: String($0)) }
        switch parts.first {
        case "open": open(paths, byClick: true)
        case "drag": open(paths, byClick: false)
        case "hover": model.hovered = Int(parts.last ?? "")
        case "middle": model.overMiddle = true
        case "more": model.turn()
        case "choose":
            model.hovered = Int(parts.last ?? "") ?? model.hovered
            openedAt = .distantPast
            model.byClick = true
            click()
        case "close":
            close()
            testing = false
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
        case .command: .command
        }
    }

    /// As a keycap reads it.
    var keycap: String {
        switch self {
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .command: "⌘ Command"
        }
    }
}
