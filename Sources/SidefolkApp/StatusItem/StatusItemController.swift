import AppKit
import SidefolkCore

/// The menu bar icon: Ask, what's live now, quiet mode, show/hide, Home, Settings, About, Quit.
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
    var onOpenHome: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onAbout: (() -> Void)?
    var onToggleCompanion: (() -> Void)?
    var onQuiet: ((TimeInterval?) -> Void)?
    var nowProvider: (() async -> [NowEntry])?
    var isQuiet: () -> Bool = { false }
    var companionVisible: () -> Bool = { true }
    var hotkeyLabel: () -> String = { "" }
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

    func setBadge(_ count: Int) {
        item.button?.title = count > 0 ? " \(count)" : ""
        item.length = count > 0 ? NSStatusItem.variableLength : NSStatusItem.squareLength
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
        let ask = menu.addItem(withTitle: String(localized: "Ask Sidefolk…"), action: #selector(ask), keyEquivalent: "")
        ask.target = self
        ask.toolTip = hotkeyLabel()

        menu.addItem(.separator())
        let header = menu.addItem(withTitle: String(localized: "Now"), action: nil, keyEquivalent: "")
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
        menu.addItem(withTitle: String(localized: "Quit Sidefolk"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        refreshNow()
    }

    @objc private func ask() { onAsk?() }
    @objc private func openHome() { onOpenHome?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func showAbout() { onAbout?() }
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
