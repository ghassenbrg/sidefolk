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
    }

    func close() { window?.performClose(nil) }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: SettingsTabContent(tab: tab, model: model))
            host.sizingOptions = []
            host.title = tab.title
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.identifier = tab.rawValue
            tabs.addTabViewItem(item)
        }
        self.tabs = tabs
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .preference
        window.setContentSize(NSSize(width: Self.width, height: 620))
        window.contentMinSize = NSSize(width: Self.width, height: 420)
        window.contentMaxSize = NSSize(width: Self.width, height: 4000)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("SidefolkSettings")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
        if let window { WindowActivation.closed(window) }
    }
}
