import AppKit
import SidefolkCore
import SwiftUI

/// The SwiftUI page for one Settings tab.
struct SettingsTabContent: View {
    var tab: SettingsTab
    var model: SettingsModel

    var body: some View {
        switch tab {
        case .general: GeneralSettingsView(model: model)
        case .companion: CompanionSettingsView(model: model)
        case .ai: AISettingsView(model: model)
        case .voice: VoiceSettingsView(model: model)
        case .agents: SettingsPage { AgentsGroup(model: model) }
        case .privacy: PrivacySettingsView(model: model)
        case .extensions: ExtensionsSettingsView(model: model)
        }
    }
}

/// Owns the Settings window: Mac-style toolbar tabs, each hosting a SwiftUI page, 640 points wide.
/// Create one and keep it; `show(tab:)` reuses the window.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private let reviewWindow = InstallPreviewWindow()
    private var window: NSWindow?
    private var tabs: NSTabViewController?

    static let width: CGFloat = 640

    init(services: AppServices) {
        model = SettingsModel(services: services)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// Brings Settings to the front, on `tab` if given (otherwise where the user left it).
    func show(tab: SettingsTab? = nil) {
        let window = self.window ?? makeWindow()
        self.window = window
        if let tab, let index = SettingsTab.allCases.firstIndex(of: tab) { tabs?.selectedTabViewItemIndex = index }
        model.start()
        Task { await model.refresh() }
        WindowActivation.show(window)
        // AppKit focuses the first text field (the companion's name, selected); a stray key would replace it.
        Task { @MainActor in window.makeFirstResponder(nil) }
    }

    /// Privacy & Permissions, scrolled to Your location (a card that asked which place, D48).
    func showYourLocation() {
        show(tab: .privacy)
        model.location.reveal = true
    }

    /// Privacy & Permissions with the sheet that says what Full access means (from the menu bar).
    func confirmFullAccess() {
        show(tab: .privacy)
        model.confirmingFullAccess = true
    }

    func close() { window?.performClose(nil) }

    #if DEBUG
    /// Settings › Companion in a given state, for the debug app (scripts/dev.swift `chooser:…`).
    func chooser(_ command: String) {
        show(tab: .companion)
        let chooser = model.chooser
        chooser.reload()
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        let value = parts.count > 1 ? parts[1] : ""
        switch parts.first ?? "" {
        case "yours": chooser.page = .yours
        case "gallery": chooser.page = .gallery
        case "search": chooser.page = .gallery; chooser.browse.text = value
        case "detail": chooser.detail = chooser.galleryEntries.first { $0.companion == value }
        case "get": chooser.galleryEntries.first { $0.companion == value }.map { chooser.get($0, wear: false) }
        case "remove": chooser.removing = chooser.owned.first { $0.id == value }
        case "confirm": chooser.removing.map { companion in Task { await chooser.remove(companion) } }
        case "add": chooser.adding = true
        case "snapshots": model.gallery.showSnapshots()
        case "close": (chooser.detail, chooser.removing, chooser.adding) = (nil, nil, false)
        default: break
        }
    }
    #endif

    /// The install preview of `folder` in its own window: Sidefolk's AI finished a draft, and the person
    /// decides there (D39). If it can't be previewed, Settings › Extensions says why.
    func review(folder: URL) {
        Task {
            guard let preview = await model.preview(folder: folder) else { return show(tab: .extensions) }
            reviewWindow.show(preview, model: model)
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow()
        tabs = Self.configure(window, model: model)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("SidefolkSettings")
        return window
    }

    /// Everything about the window except where it sits; returns the tab controller. UISnapshots
    /// uses this too, so pictures show exactly what people get.
    @discardableResult
    static func configure(_ window: NSWindow, model: SettingsModel) -> NSTabViewController {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: SettingsTabContent(tab: tab, model: model))
            // No preferred size: switching tabs keeps the window's size instead of jumping.
            host.sizingOptions = []
            host.title = tab.title
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.identifier = tab.rawValue
            tabs.addTabViewItem(item)
        }
        window.contentViewController = tabs
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .preference
        // The tabs sit on the window's own background, so the chrome matches the pages (navy in dark).
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.surfaceSunken)
        window.setContentSize(NSSize(width: width, height: 620))
        window.contentMinSize = NSSize(width: width, height: 420)
        window.contentMaxSize = NSSize(width: width, height: 4000)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        return tabs
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
        if let window { WindowActivation.closed(window) }
    }
}
