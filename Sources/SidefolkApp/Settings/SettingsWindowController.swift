import AppKit
import SidefolkCore
import SwiftUI

/// The page for one Settings tab (D84).
struct SettingsTabContent: View {
    var tab: SettingsTab
    var model: SettingsModel

    var body: some View {
        switch tab {
        case .general: GeneralSettingsView(model: model)
        case .companion: CompanionSettingsView(model: model)
        case .attention: AttentionSettingsView(model: model)
        case .brain: BrainSettingsView(model: model)
        case .trust: TrustSettingsView(model: model)
        case .connections: ConnectionsSettingsView(model: model)
        case .addons: ExtensionsSettingsView(model: model)
        case .appearance: AppearanceSettingsView(model: model)
        }
    }
}

/// Owns the Settings window: a sidebar with search and eight tabs, like System Settings (D84), around the SwiftUI
/// pages. Create one and keep it; `show(tab:)` reuses the window.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private let reviewWindow = InstallPreviewWindow()
    private var window: NSWindow?

    static let size = NSSize(width: 920, height: 700)

    init(services: AppServices) {
        model = SettingsModel(services: services)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// Brings Settings to the front, on `tab` if given (otherwise where the person left it), or at a setting.
    func show(tab: SettingsTab? = nil, reveal key: SettingKey? = nil) {
        let window = self.window ?? makeWindow()
        self.window = window
        if let tab { model.navigation.tab = tab }
        model.start()
        Task { await model.refresh() }
        WindowActivation.show(window)
        // AppKit focuses the first text field (the search); a stray key would start a search.
        Task { @MainActor in window.makeFirstResponder(nil) }
        if let key {
            // After the page is laid out, or there is nothing to scroll to yet.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                model.navigation.jump(to: key)
            }
        }
    }

    /// Trust › Your location (a card that asked which place, D48).
    func showYourLocation() {
        show(reveal: .location)
    }

    /// Trust with the sheet that says what Full access means (from the menu bar).
    func confirmFullAccess() {
        show(tab: .trust)
        model.confirmingFullAccess = true
    }

    func close() { window?.performClose(nil) }

    #if DEBUG
    /// The debug app's `settings:<tab>`, `settings:search:<words>`, `settings:jump:<setting>` and
    /// `settings:full-access` (scripts/dev.swift).
    func dev(_ command: String) {
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first ?? "" {
        case "search":
            show()
            model.navigation.query = parts.count > 1 ? parts[1] : ""
        case "jump":
            if let key = parts.count > 1 ? SettingKey(rawValue: parts[1]) : nil { show(reveal: key) }
        case "full-access": confirmFullAccess()
        default: show(tab: SettingsTab(named: command))
        }
    }

    /// Settings › Companion in a given state, for the debug app (scripts/dev.swift `chooser:…`).
    func chooser(_ command: String) {
        show(tab: .companion)
        let chooser = model.chooser
        chooser.reload()
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        let value = parts.count > 1 ? parts[1] : ""
        switch parts.first ?? "" {
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
    /// decides there (D39). If it can't be previewed, Settings › Add-ons says why.
    func review(folder: URL) {
        Task {
            guard let preview = await model.preview(folder: folder) else { return show(tab: .addons) }
            reviewWindow.show(preview, model: model)
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow()
        Self.configure(window, model: model)
        window.delegate = self
        window.center()
        // A new name: the old window was 640 wide with a toolbar; its saved frame would squeeze the sidebar.
        window.setFrameAutosaveName("SidefolkSettingsSidebar")
        return window
    }

    /// Everything about the window except where it sits. UISnapshots uses this too, so pictures show exactly what
    /// people get.
    static func configure(_ window: NSWindow, model: SettingsModel) {
        let host = NSHostingController(rootView: SettingsRoot(model: model))
        // No preferred size: switching tabs keeps the window's size instead of jumping.
        host.sizingOptions = []
        // The sidebar holds the window's buttons and the title sits level with them, as in System Settings: nothing
        // is pushed under the title bar, so the pages' scroll views start at their top.
        host.safeAreaRegions = []
        window.contentViewController = host
        window.title = String(localized: "Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(Theme.surfaceSunken)
        window.setContentSize(size)
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
        model.navigation.query = ""
        if let window { WindowActivation.closed(window) }
    }
}
