import AppKit
import SidefolkCore
import SwiftUI

/// Owns the Home window (Now, Notebook, Activity). Create one and keep it; `show` reuses the window.
@MainActor
final class HomeWindowController: NSObject, NSWindowDelegate {
    enum Section {
        case now, notebook, activity
    }

    private let model: HomeModel
    private var window: NSWindow?

    init(services: AppServices) {
        model = HomeModel(services: services)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// Brings Home to the front, optionally on a section; keeps the current section otherwise.
    func show(section: Section? = nil) {
        switch section {
        case .now: model.selection = .now
        case .activity: model.selection = .activity
        case .notebook: Task { await model.showNotebook() }
        case nil: break
        }
        present()
    }

    /// Opens the Notebook at `item` (what the facade's `open(item:)` should do).
    func show(item: NotebookItem) {
        Task { await model.reveal(item) }
        present()
    }

    func close() { window?.performClose(nil) }

    private func present() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.start()
        WindowActivation.show(window)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: HomeView(model: model))
        host.sizingOptions = [.minSize]
        host.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "Sidefolk"
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar(identifier: "app.sidefolk.home")
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 860, height: 560)
        window.setContentSize(NSSize(width: 1080, height: 720))
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("SidefolkHome")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
        if let window { WindowActivation.closed(window) }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Sessions and jobs change without a data event; coming back to the window refreshes them.
        Task { await model.now.reload() }
    }
}
