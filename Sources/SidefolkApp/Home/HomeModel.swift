import Foundation
import Observation
import SidefolkCore
import SwiftUI

/// What Home shows (D84): the five places, the Notebook's collections, You and the Trash inside it, an extension's
/// page, or the Gallery.
enum HomeSelection: Hashable {
    case now, calendar, onDuty, history, you, trash, gallery
    case collection(String)
    /// The Notebook's own page (D134): what needs doing, every collection, what's pinned.
    case notebook
    /// An extension's page (D62), by `ExtensionPageInfo.id`.
    case page(String)
    /// A watch's own page (D87), by `Watcher.id`; it belongs to On duty.
    case watch(String)
    /// Every watcher in one list, to arrange (D116); it belongs to On duty.
    case watchers

    /// The places, in ⌘1–5 order (D84).
    static let places: [HomeSelection] = [.now, .calendar, .notebook, .onDuty, .history]

    var title: LocalizedStringKey {
        switch self {
        case .now: "Today"
        case .calendar: "Calendar"
        case .notebook, .collection, .trash, .you: "Notebook"
        case .onDuty, .watch, .watchers: "On duty"
        case .history: "History"
        case .page: "Extensions"
        case .gallery: "Gallery"
        }
    }

    /// 03-system › Iconography: the places' symbols.
    var symbol: String {
        switch self {
        case .now: "sun.max"
        case .calendar: "calendar"
        case .notebook, .collection, .trash, .you: "book.closed"
        case .onDuty, .watch, .watchers: "dot.radiowaves.left.and.right"
        case .history: "clock.arrow.circlepath"
        case .page: "puzzlepiece.extension"
        case .gallery: "sparkles"
        }
    }

    /// The same place, whichever collection is open.
    func isPlace(_ place: HomeSelection) -> Bool {
        switch (self, place) {
        case (.collection, .notebook), (.trash, .notebook), (.you, .notebook), (.watch, .onDuty), (.watchers, .onDuty): true
        default: self == place
        }
    }
}

/// State behind the Home window. Follows `.dataChanged` events while the window is open, so what
/// it shows stays current without polling.
@MainActor @Observable
final class HomeModel {
    /// Why a live value couldn't move beside the companion (D116), until the next try.
    var watcherProblem: String?
    let services: AppServices
    let now: NowModel
    let notebook: NotebookModel
    let calendar: CalendarModel
    /// History (D84): Activity and Conversations as one timeline; the conversation open in place is its own.
    let history: HistoryModel
    /// You (D84): what Sidefolk keeps in mind about the person.
    let you: YouModel
    /// Extensions' pages (D62).
    let pages: ExtensionPagesModel
    /// The Say bar's search (D58, D84); while it has words, the understanding panel shows what Return does.
    let find: FindModel
    /// The watch open on its own page (D87).
    let watch: WatchDetailModel
    /// Whether the place's own title is in sight, so the toolbar's stays out of the way (`homePageTitle`).
    let title = HomeTitleTracker()
    /// The Gallery in Home (D84) is Settings' own gallery models, with their install previews and downloads.
    @ObservationIgnored private(set) lazy var settingsHost = SettingsModel(services: services)

    var selection: HomeSelection? = .now {
        didSet {
            if selection != oldValue { selectionChanged() }
        }
    }

    /// The new or edited collection's sheet, opened from the sidebar or the toolbar's New menu.
    var collectionSheet: CollectionSheet.Mode?
    /// The Say bar has the keyboard: its panel shows under it while it has words.
    var saying = false

    private var eventTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var pagesTask: Task<Void, Never>?
    private var pending: Set<DataDomain> = []

    init(services: AppServices) {
        self.services = services
        now = NowModel(services: services)
        notebook = NotebookModel(services: services)
        calendar = CalendarModel(services: services, now: now)
        history = HistoryModel(services: services)
        you = YouModel(services: services)
        pages = ExtensionPagesModel(services: services)
        watch = WatchDetailModel(services: services)
        find = FindModel { query in (try? await services.runtime.find(query)) ?? SearchResults() }
        now.openPage = { [weak self] id in self?.selection = .page(id) }
        now.openWatch = { [weak self] id in
            guard let self else { return }
            selection = .watch(id)
            // Opening the watch from its tile, row or card is seeing what it noticed, as the tile's popover was.
            Task { await self.now.seen(watcherId: id) }
        }
        // An extension page's heads-up switch stops its watch through the same question as every other Stop.
        pages.askToStop = { [weak self] id, title in self?.now.stopAsk.ask(id: id, title: title) }
        now.stopped = { [weak self] in await self?.pages.alertsChanged() }
        you.trash = { [weak self] item in await self?.notebook.moveToTrash(item) }
        // A switch flipped or a page arranged on one side shows on the other (D67).
        pages.changed = { [weak self] in Task { await self?.now.reloadWidgets() } }
    }

    /// Sends the Say bar's words on, and empties it.
    func send(_ how: AskHow) {
        let text = find.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        find.query = ""
        services.ask(text, how: how)
    }

    var companionName: String { services.runtime.settings.current.companionName }

    /// What's on duty now, the one count Home shows everywhere (the sidebar, Today, On duty's title and line): `OnDuty`'s
    /// running things plus extensions working in the background.
    var onDutyRunning: Int { now.onDuty.running(extra: pages.backgroundCount) }

    /// Starts following changes (idempotent) and refreshes everything once.
    func start() {
        guard eventTask == nil else { return }
        let stream = services.runtime.events.stream()
        eventTask = Task { [weak self] in
            for await event in stream {
                switch event {
                case .dataChanged(let domain): self?.changed(domain)
                case .attention, .approvalRequested, .approvalResolved: self?.changed(.attention)
                case .watchReading(let reading): self?.now.update(reading)
                default: break
                }
            }
        }
        Task { await reloadAll() }
        pagesTask = Task { [pages] in await pages.follow() }
    }

    /// Stops following changes and saves any edit in progress.
    func stop() {
        eventTask?.cancel()
        eventTask = nil
        reloadTask?.cancel()
        pagesTask?.cancel()
        pagesTask = nil
        settingsHost.stop()
        Task { await notebook.flush() }
    }

    func reloadAll() async {
        await now.reload()
        await notebook.reload()
        await history.reload()
        await you.reload()
        await pages.reload()
        if case .collection(let id) = selection, notebook.collectionId == nil { await notebook.show(collectionId: id) }
    }

    /// Opens the Notebook at an item; a fact about the person opens on You.
    func reveal(_ item: NotebookItem) async {
        if notebook.collection(id: item.collectionId)?.kind == .profile {
            selection = .you
            you.editing = item.id
            return
        }
        selection = .collection(item.collectionId)
        await notebook.show(collectionId: item.collectionId)
        notebook.select(item.id)
    }

    /// Opens History with a conversation open in place (D84), or where it was.
    func showConversation(_ thread: String?) async {
        selection = .history
        await history.reload()
        if let thread { history.open(conversation: thread) }
    }

    /// Goes to one of the places.
    func go(to place: HomeSelection) { selection = place }

    /// A new note in the collection on screen, or the Inbox.
    func newNote() async {
        if notebook.collections.isEmpty { await notebook.reloadCollections() }
        if case .collection = selection {} else if let inbox = notebook.inboxId {
            // A tab left on Tasks last time can't be seen from here, so it doesn't decide what this is.
            notebook.filter = .all
            selection = .collection(inbox)
        }
        if case .collection(let id) = selection { await notebook.show(collectionId: id) }
        await notebook.newItem()
    }

    func showNotebook() { selection = .notebook }

    private func selectionChanged() {
        switch selection {
        case .notebook:
            // Leaving a note: a new one with nothing in it goes, and isn't counted here.
            notebook.select(nil)
            Task {
                await notebook.flush()
                await notebook.reloadCollections()
            }
        case .collection(let id): Task { await notebook.show(collectionId: id) }
        case .trash: Task { await notebook.reloadTrash() }
        case .history: Task { await history.reload() }
        case .you: Task { await you.reload() }
        case .calendar: Task { await calendar.reload() }
        case .gallery:
            settingsHost.start()
            Task {
                await settingsHost.refresh()
                await settingsHost.gallery.load()
            }
        case .watch(let id): Task { await watch.show(id) }
        case .now, .onDuty, .page, .watchers, nil: break
        }
    }

    private func changed(_ domain: DataDomain) {
        pending.insert(domain)
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let domains = pending
            pending = []
            // Today and On duty show reminders, watchers, sessions, jobs and attention together; any change can touch them.
            await now.reload()
            // The Calendar shows reminders, their notes and the calendar setting: any change may move something on it.
            if selection == .calendar { await calendar.reload() }
            if domains.contains(.notebook) || domains.contains(.memories) {
                await notebook.reload()
                await you.reload()
            } else if domains.contains(.reminders) {
                await notebook.reloadReminders()
            }
            if case .watch = selection, domains.contains(.watchers) { await watch.reload() }
            if selection == .history, !domains.isDisjoint(with: [.activity, .runs, .conversations, .attention, .settings]) {
                await history.reload()
            }
            if domains.contains(.extensions) {
                await pages.reload()
                if case .page(let id) = selection, pages.info(id) == nil { selection = .now }
            }
        }
    }
}
