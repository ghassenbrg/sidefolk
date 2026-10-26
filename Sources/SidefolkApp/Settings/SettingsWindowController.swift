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

    /// Privacy & Permissions with the sheet that says what Full access means (from the menu bar).
    func confirmFullAccess() {
        show(tab: .privacy)
        model.confirmingFullAccess = true
    }

    func close() { window?.performClose(nil) }

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
