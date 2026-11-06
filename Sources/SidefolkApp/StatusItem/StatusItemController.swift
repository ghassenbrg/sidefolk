import AppKit
import KeyboardShortcuts
import SidefolkCore
import SwiftUI

/// The menu bar icon (D84): the companion's mark says the state at a glance (an amber dot when something waits, a half
/// circle in Focus, a moon in Quiet, faded while the companion is hidden, orange in Full access), and a click opens the
/// Pocket. A right-click or Control-click opens the same ⋯ menu as the Pocket, so Quit and Check for Updates… are
/// always one step away.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    enum Mark: Equatable { case idle, waiting, focus, quiet }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let badge = StatusMarkBadge()
    let pocket = PocketModel()

    /// Gathers what the Pocket shows, each time it opens.
    var contentProvider: (() async -> PocketContent)?
    var palettes: () -> [ExtensionPaletteInfo] = { [] }
    /// Items extensions put here (D100), as they are now.
    var entries: () -> [ExtensionEntry] = { [] }
    /// One of them, as an item of the menu.
    var entryItem: (ExtensionEntry) -> NSMenuItem? = { _ in nil }
    /// The version waiting, for the ⋯ menu's "Update to Sidefolk …" (D46).
    var waitingUpdate: () -> String? = { nil }
    var actions: PocketActions {
        get { pocket.actions }
        set { pocket.actions = newValue }
    }
    private(set) var mode: GuardMode = .askOncePerKind
    private var fullAccessEnds: Date?
    private var mark: Mark = .idle
    private(set) var hidden = false
    private var readout: String?

    var isPocketShown: Bool { popover.isShown }

    func install(image: NSImage?) {
        if let image {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "Sidefolk")
        }
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        if let button = item.button {
            badge.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.widthAnchor.constraint(equalToConstant: 10), badge.heightAnchor.constraint(equalToConstant: 10),
                badge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
                badge.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -2),
            ])
        }
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PocketView(model: pocket))
        updateLabel()
    }

    /// The Pocket keeps the app's own Light or Dark choice. The icon is left to macOS, which sets its status window's
    /// look from the menu bar itself: that depends on the wallpaper and on a full-screen app, not on Light or Dark, so
    /// the button is never told one (measured: `NSApp.appearance` doesn't reach it, and telling it one fixes it wrong).
    func setPocketAppearance(_ app: NSAppearance?) {
        popover.appearance = app
    }

    /// In Full access the menu bar icon turns orange, like the Mac's own "in use" dots, so the mode is visible even
    /// with the companion and the Ask panel hidden (D37); VoiceOver says when it ends.
    func setMode(_ mode: GuardMode, ends: Date? = nil) {
        self.mode = mode
        fullAccessEnds = mode == .fullAccess ? ends : nil
        item.button?.contentTintColor = mode == .fullAccess ? .systemOrange : nil
        updateLabel()
        if popover.isShown { refresh() }
    }

    /// Something waits, Focus or Quiet, from the state the app keeps (D84).
    func setMark(_ mark: Mark) {
        guard mark != self.mark else { return }
        self.mark = mark
        badge.mark = mark
        updateLabel()
    }

    /// The companion is hidden, for what the icon's menu offers. The icon itself stays as it is: a fading mark read as
    /// broken (the founder, amending D84).
    func setCompanionHidden(_ hidden: Bool) {
        self.hidden = hidden
    }

    /// A live value beside the icon, while the companion is away from the desktop (nil removes it).
    func setReadout(_ text: String?) {
        guard text != readout else { return }
        readout = text
        let title = readout?.clipped(28)
        item.button?.title = title.map { " " + $0 } ?? ""
        item.length = title == nil ? NSStatusItem.squareLength : NSStatusItem.variableLength
        item.button?.imagePosition = .imageLeading
    }

    private func updateLabel() {
        var parts = ["Sidefolk"]
        if mode == .fullAccess {
            parts.append(fullAccessEnds.map { String(localized: "Full access is on until \(TimeText.clock($0))", comment: "VoiceOver: the menu bar icon") }
                         ?? String(localized: "Full access is on"))
        }
        switch mark {
        case .idle: break
        case .waiting: parts.append(String(localized: "something waits for you", comment: "VoiceOver: the menu bar icon"))
        case .focus: parts.append(String(localized: "Focus", comment: "Attention: only cards that need an answer; whispers wait"))
        case .quiet: parts.append(String(localized: "Quiet", comment: "Attention: only what can't wait"))
        }
        item.button?.setAccessibilityLabel(parts.joined(separator: ", "))
    }

    /// Gathers the Pocket's content again while it is open.
    func refresh() {
        guard let contentProvider else { return }
        Task {
            pocket.content = await contentProvider()
            pocket.palettes = palettes()
            pocket.entries = entries()
        }
    }

    // MARK: Opening

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePocket()
        }
    }

    func togglePocket() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        Task {
            if let contentProvider { pocket.content = await contentProvider() }
            pocket.palettes = palettes()
            pocket.entries = entries()
            // The Pocket takes the keyboard (its Ask field, the dial's keys), so Sidefolk comes forward while it's open.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePocket() { if popover.isShown { popover.performClose(nil) } }

    /// The ⋯ menu as a plain menu under the icon.
    private func showMenu() {
        let menu = NSMenu()
        let a = actions
        func add(_ title: String, key: String = "", _ action: @escaping () -> Void) {
            let entry = ClosureTarget.item(title, action)
            entry.keyEquivalent = key
            menu.addItem(entry)
        }
        add(String(localized: "Open Sidefolk"), key: "o", a.openHome)
        add(String(localized: "Settings…"), key: ",", a.openSettings)
        let entries = entries()
        if !entries.isEmpty {
            menu.addItem(.separator())
            for entry in entries { if let item = entryItem(entry) { menu.addItem(item) } }
        }
        let palettes = palettes()
        if !palettes.isEmpty {
            menu.addItem(.separator())
            for info in palettes {
                let entry = ClosureTarget.item("\(info.title)…") { a.openPalette(info.id) }
                entry.setShortcut(for: PaletteController.shortcutName(info))
                menu.addItem(entry)
            }
        }
        menu.addItem(.separator())
        add(hidden ? String(localized: "Show Companion") : String(localized: "Hide Companion"), a.toggleCompanion)
        add(waitingUpdate().map { String(localized: "Update to Sidefolk \($0)…", comment: "Menu bar: a newer version waits") }
            ?? String(localized: "Check for Updates…"), a.checkForUpdates)
        add(String(localized: "About Sidefolk"), a.about)
        menu.addItem(.separator())
        add(String(localized: "Quit Sidefolk"), key: "q", a.quit)
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }
}

/// The small mark on the menu bar icon's corner: an amber dot when something waits, Focus's half circle, Quiet's moon.
final class StatusMarkBadge: NSView {
    var mark: StatusItemController.Mark = .idle { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        switch mark {
        case .idle: return
        case .waiting:
            NSColor(Theme.waitGlow).setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5)).fill()
        case .focus, .quiet:
            let symbol = mark == .focus ? Theme.Symbol.focus : Theme.Symbol.quiet
            let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
                .applying(.init(paletteColors: [NSColor.labelColor]))
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)?
                .draw(in: bounds.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
