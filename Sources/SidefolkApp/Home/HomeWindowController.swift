import AppKit
import SidefolkCore
import SwiftUI

/// Owns the Home window (Today, Calendar, Notebook, On duty, History, the Gallery). Create one and keep it; `show` reuses the window.
@MainActor
final class HomeWindowController: NSObject, NSWindowDelegate {
    enum Section {
        case now, calendar, notebook, onDuty, history, gallery
    }

    private let model: HomeModel
    private var window: NSWindow?

    init(services: AppServices) {
        model = HomeModel(services: services)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    #if DEBUG
    /// The window and the Calendar's model, for the dev channel's calendar commands.
    var devWindow: NSWindow? { window }
    var devCalendar: CalendarModel { model.calendar }
    #endif

    /// Brings Home to the front, optionally on a section; keeps the current section otherwise.
    func show(section: Section? = nil) {
        switch section {
        case .now: model.selection = .now
        case .calendar: model.selection = .calendar
        case .onDuty: model.selection = .onDuty
        case .history: model.selection = .history
        case .gallery: model.selection = .gallery
        case .notebook: Task { await model.showNotebook() }
        case nil: break
        }
        present()
    }

    /// Opens History with the conversation `thread` open in place (D45, D84).
    func show(conversation thread: String?) {
        Task { await model.showConversation(thread) }
        present()
    }

    /// Opens the Notebook at `item` (what the facade's `open(item:)` should do).
    func show(item: NotebookItem) {
        Task { await model.reveal(item) }
        present()
    }

    #if DEBUG
    /// `flip:<page id>:on|off` (dev.swift): a page's main switch as if clicked on its sidebar row (D67).
    func flip(page id: String, on: Bool) {
        Task {
            await model.pages.reload()
            guard let info = model.pages.info(id), let control = model.pages.summaries[id]?.control else {
                Log.shared.warning("dev", "no main switch", ["page": id])
                return
            }
            await model.pages.flip(info, control, on: on)
        }
    }
    #endif

    /// Opens an extension's page (D62), by `extension id/page`.
    func show(page id: String) {
        Task {
            await model.pages.reload()
            model.selection = .page(id)
        }
        present()
    }

    func close() { window?.performClose(nil) }

    /// History, with this Activity row's record open (D84).
    func show(activityRow id: Int64?) {
        model.selection = .history
        Task {
            await model.history.reload()
            model.history.open(activityRow: id)
        }
        present()
    }

    #if DEBUG
    /// Dev channel: the Calendar in a mode (D66), at a day when given ("calendar:week:2026-11-03").
    func showCalendar(_ mode: String?, day: Date?) {
        if let mode = mode.flatMap(CalendarModel.Mode.init(word:)) { model.calendar.mode = mode }
        if let day { model.calendar.jump(to: day) }
        model.selection = .calendar
        present()
    }

    /// Dev channel: `home:<place>` (today, calendar, notebook, onduty, history, you, trash, gallery), and History's filter
    /// as `home:history:agents` (D84).
    func showPlace(_ place: String) {
        let parts = place.split(separator: ":").map(String.init)
        switch parts.first {
        case "today": model.selection = .now
        case "calendar": model.selection = .calendar
        case "notebook": Task { await model.showNotebook() }
        case "onduty": model.selection = .onDuty
        case "history":
            model.selection = .history
            if let filter = parts.dropFirst().first.flatMap(HistoryFilter.init(rawValue:)) { model.history.filter = filter }
        case "you": model.selection = .you
        case "trash": model.selection = .trash
        case "gallery": model.selection = .gallery
        case "watch":
            // home:watch[:<id>[:check|:sidebyside]], the first watch On duty lists without an id (D87): its page, then
            // its Check now button or its change in two columns.
            guard let id = parts.dropFirst().first ?? model.now.watchers.first?.id else { break }
            model.selection = .watch(id)
            let then = parts.dropFirst(2).first
            model.watch.sideBySide = then == "sidebyside"
            if then == "check" { Task { await model.watch.show(id); await model.watch.checkNow() } }
        default: Log.shared.warning("dev", "no such place", ["place": place])
        }
        present()
    }

    /// Dev channel: the Say bar's words (D58, D84).
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
