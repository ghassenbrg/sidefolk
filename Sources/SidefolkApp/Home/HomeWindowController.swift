import AppKit
import SidefolkCore
import SwiftUI

/// Owns the Home window (Now, Conversations, Notebook, Activity). Create one and keep it; `show` reuses the window.
@MainActor
final class HomeWindowController: NSObject, NSWindowDelegate {
    enum Section {
        case now, calendar, notebook, activity
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
        case .calendar: model.selection = .calendar
        case .activity: model.selection = .activity
        case .notebook: Task { await model.showNotebook() }
        case nil: break
        }
        present()
    }

    /// Opens Conversations at `thread`, or where it was (D45).
    func show(conversation thread: String?) {
        Task { await model.showConversation(thread) }
        present()
    }

    /// Opens the Notebook at `item` (what the facade's `open(item:)` should do).
    func show(item: NotebookItem) {
        Task { await model.reveal(item) }
        present()
    }

    /// Opens an extension's page (D62), by `extension id/page`.
    func show(page id: String) {
        Task {
            await model.pages.reload()
            model.selection = .page(id)
        }
        present()
    }

    func close() { window?.performClose(nil) }

    /// Activity, with this row's details open.
    func show(activityRow id: Int64?) {
        model.selection = .activity
        model.activity.openId = id
        present()
    }

    #if DEBUG
    /// Dev channel: the Calendar in a mode (D66), at a day when given ("calendar:week:2026-11-03").
    func showCalendar(_ mode: String?, day: Date?) {
        if let mode = mode.flatMap(CalendarModel.Mode.init(rawValue:)) { model.calendar.mode = mode }
        if let day { model.calendar.jump(to: day) }
        model.selection = .calendar
        present()
    }

    /// Dev channel: the one bar's search (D58).
    func showSearch(_ query: String) {
        model.find.query = query
        Task { await model.find.searchNow() }
        present()
    }
    #endif

    private func present() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.start()
        WindowActivation.show(window)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow()
        Self.configure(window, model: model)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("SidefolkHome")
        return window
    }

    /// Everything about the window except where it sits. UISnapshots uses this too, so pictures
    /// show exactly what people get.
    static func configure(_ window: NSWindow, model: HomeModel) {
        let host = NSHostingController(rootView: HomeView(model: model))
        host.sizingOptions = [.minSize]
        // SwiftUI builds the toolbar (the split view's sidebar button) for this window.
        host.sceneBridgingOptions = [.toolbars]
        window.contentViewController = host
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "Sidefolk"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        // The toolbar shows the window's own background, so the chrome matches the pages (navy in dark).
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.surfaceSunken)
        window.contentMinSize = NSSize(width: 860, height: 560)
        window.setContentSize(NSSize(width: 1080, height: 720))
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
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
