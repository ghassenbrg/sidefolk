import AppKit
import KeyboardShortcuts
import SidefolkCore

/// The menu bar icon: Ask, what's live now, how much Sidefolk asks, quiet mode, show/hide, Home,
/// Settings, About, updates, Quit.
final class StatusItemController: NSObject, NSMenuDelegate {
    struct NowEntry {
        var title: String
        var detail: String
        var symbol: String
        var action: () -> Void
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    var onAsk: (() -> Void)?
    /// Extensions' palettes (D63), so Clipboard is in the menu bar as Maccy is (D68): opened under the icon.
    var palettes: () -> [ExtensionPaletteInfo] = { [] }
    var onPalette: ((_ id: String, _ under: NSRect?) -> Void)?
    var onOpenHome: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onAbout: (() -> Void)?
    /// "Check for Updates…", or "Update to Sidefolk …" while `waitingUpdate` names a version (D46).
    var onUpdates: (() -> Void)?
    var waitingUpdate: () -> String? = { nil }
    var onToggleCompanion: (() -> Void)?
    var onQuiet: ((TimeInterval?) -> Void)?
    /// Switches the approval mode; Full access goes through `onFullAccess` (its sheet) instead.
    var onMode: ((GuardMode) -> Void)?
    var onFullAccess: (() -> Void)?
    private(set) var mode: GuardMode = .askOncePerKind
    var nowProvider: (() async -> [NowEntry])?
    var isQuiet: () -> Bool = { false }
    var companionVisible: () -> Bool = { true }
    var hotkeyLabel: () -> String = { "" }
    /// The companion's name, so the menu asks the one on the desktop, as Now's "Ask Mochi…" does.
    var companionName: () -> String = { "Sidefolk" }
    private var nowCache: [NowEntry] = []

    func install(image: NSImage?) {
        if let image {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "Sidefolk")
        }
        item.button?.setAccessibilityLabel("Sidefolk")
        menu.delegate = self
        item.menu = menu
    }

    private var badge = 0
    private var readout: String?

    /// In Full access the menu bar icon turns orange, like the Mac's own "in use" dots, so the mode
    /// is visible even with the companion and the Ask panel hidden (D37).
    func setMode(_ mode: GuardMode) {
        self.mode = mode
        let full = mode == .fullAccess
        item.button?.contentTintColor = full ? .systemOrange : nil
        item.button?.setAccessibilityLabel(full ? String(localized: "Sidefolk, Full access is on") : "Sidefolk")
    }

    func setBadge(_ count: Int) {
        badge = count
        updateTitle()
    }

    /// A live value beside the icon, while the companion is away from the desktop (nil removes it).
    func setReadout(_ text: String?) {
        guard text != readout else { return }
        readout = text
        updateTitle()
    }

    private func updateTitle() {
        let parts = [readout?.clipped(28), badge > 0 ? String(badge) : nil].compactMap { $0 }
        item.button?.title = parts.isEmpty ? "" : " " + parts.joined(separator: "  ")
        item.length = parts.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
        item.button?.imagePosition = .imageLeading
    }

    func refreshNow() {
        guard let nowProvider else { return }
        Task {
            nowCache = await nowProvider()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let ask = menu.addItem(withTitle: String(localized: "Ask \(companionName())…"), action: #selector(ask), keyEquivalent: "")
        ask.target = self
        ask.toolTip = hotkeyLabel()
        for info in palettes() {
            let mi = menu.addItem(withTitle: "\(info.title)…", action: #selector(openPalette(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = info.id
            mi.setShortcut(for: PaletteController.shortcutName(info))
        }
        if mode == .fullAccess {
            // First thing in the menu while it lasts, with the way out right under it.
            let on = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
            on.attributedTitle = NSAttributedString(string: String(localized: "Full access is on"), attributes: [
                .foregroundColor: NSColor.systemOrange, .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            ])
            on.image = NSImage(systemSymbolName: GuardMode.fullAccess.symbol, accessibilityDescription: nil)
            on.isEnabled = false
            let off = menu.addItem(withTitle: String(localized: "Turn Off Full Access"), action: #selector(chooseMode(_:)), keyEquivalent: "")
            off.target = self
            off.representedObject = GuardMode.askOncePerKind.rawValue
        }

        menu.addItem(.separator())
        let header = menu.addItem(withTitle: String(localized: "Today"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        if nowCache.isEmpty {
            let none = menu.addItem(withTitle: String(localized: "Nothing running or due soon"), action: nil, keyEquivalent: "")
            none.isEnabled = false
        }
        for (i, entry) in nowCache.prefix(6).enumerated() {
            let mi = menu.addItem(withTitle: "\(entry.title) — \(entry.detail)", action: #selector(openNow(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = i
            mi.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
        }

        menu.addItem(.separator())
        menu.addItem(modesItem())
        if isQuiet() {
            let q = menu.addItem(withTitle: String(localized: "Turn Quiet Off"), action: #selector(quietOff), keyEquivalent: "")
            q.target = self
        } else {
            let quiet = NSMenuItem(title: String(localized: "Quiet"), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let spans: [(String, Double)] = [(String(localized: "For 30 minutes"), 1800), (String(localized: "For 1 hour"), 3600),
                                             (String(localized: "For 3 hours"), 10800), (String(localized: "Until tomorrow"), -1)]
            for (title, seconds) in spans {
                let mi = sub.addItem(withTitle: title, action: #selector(quietFor(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = seconds
            }
            quiet.submenu = sub
            menu.addItem(quiet)
        }
        let toggle = menu.addItem(withTitle: companionVisible() ? String(localized: "Hide Companion") : String(localized: "Show Companion"),
                                  action: #selector(toggleCompanion), keyEquivalent: "")
        toggle.target = self

        menu.addItem(.separator())
        let home = menu.addItem(withTitle: String(localized: "Open Sidefolk"), action: #selector(openHome), keyEquivalent: "o")
        home.target = self
        let settings = menu.addItem(withTitle: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        let about = menu.addItem(withTitle: String(localized: "About Sidefolk"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        let update = menu.addItem(withTitle: waitingUpdate().map { String(localized: "Update to Sidefolk \($0)…", comment: "Menu bar: a newer version waits") }
                                      ?? String(localized: "Check for Updates…"),
                                  action: #selector(updates), keyEquivalent: "")
        update.target = self
        menu.addItem(withTitle: String(localized: "Quit Sidefolk"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        refreshNow()
    }

    /// "Approvals" › the four modes, the current one checked. Full access opens its sheet in Settings
    /// rather than switching from a menu.
    private func modesItem() -> NSMenuItem {
        let parent = NSMenuItem(title: String(localized: "Approvals: \(mode.title)", comment: "Menu bar: the approval mode, “Approvals: Auto”"),
                                action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
        let sub = NSMenu()
        for option in GuardMode.allCases {
            let full = option == .fullAccess
            let title = full && mode != .fullAccess ? String(localized: "Full access…") : option.title
            let mi = sub.addItem(withTitle: title, action: #selector(chooseMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = option.rawValue
            mi.state = option == mode ? .on : .off
            mi.toolTip = option.explanation
        }
        parent.submenu = sub
        return parent
    }

    @objc private func chooseMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let chosen = GuardMode(rawValue: raw), chosen != mode else { return }
        if chosen == .fullAccess { onFullAccess?() } else { onMode?(chosen) }
    }

    @objc private func ask() { onAsk?() }
    @objc private func openPalette(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onPalette?(id, item.button?.window?.frame)
    }
    @objc private func openHome() { onOpenHome?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func showAbout() { onAbout?() }
    @objc private func updates() { onUpdates?() }
    @objc private func toggleCompanion() { onToggleCompanion?() }
    @objc private func quietOff() { onQuiet?(nil) }
    @objc private func quietFor(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        if seconds < 0 {
            let cal = Calendar.current
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
            let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)!
            onQuiet?(morning.timeIntervalSinceNow)
        } else {
            onQuiet?(seconds)
        }
    }

    @objc private func openNow(_ sender: NSMenuItem) {
        guard nowCache.indices.contains(sender.tag) else { return }
        nowCache[sender.tag].action()
    }
}
