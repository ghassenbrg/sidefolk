import Foundation
import Observation
import SidefolkCore
import SwiftUI

/// What the Home sidebar can show.
enum HomeSelection: Hashable {
    case now, conversations, activity, trash
    case collection(String)
    /// An extension's page (D62), by `ExtensionPageInfo.id`.
    case page(String)

    /// The four places every navigation offers, in ⌘1–4 order; `.collection("")` stands for the Notebook.
    static let places: [HomeSelection] = [.now, .collection(""), .conversations, .activity]

    var title: LocalizedStringKey {
        switch self {
        case .now: "Today"
        case .collection, .trash: "Notebook"
        case .conversations: "Conversations"
        case .activity: "Activity"
        case .page: "Extensions"
        }
    }

    var symbol: String {
        switch self {
        case .now: "sun.max"
        case .collection, .trash: "book.closed"
        case .conversations: "bubble.left.and.bubble.right"
        case .activity: "list.bullet.rectangle"
        case .page: "puzzlepiece.extension"
        }
    }

    /// The same place, whichever collection is open.
    func isPlace(_ place: HomeSelection) -> Bool {
        switch (self, place) {
        case (.collection, .collection), (.trash, .collection): true
        default: self == place
        }
    }
}

/// State behind the Home window. Follows `.dataChanged` events while the window is open, so what
/// it shows stays current without polling.
@MainActor @Observable
final class HomeModel {
    let services: AppServices
    let now: NowModel
    let notebook: NotebookModel
    let activity: ActivityModel
    let conversations: ConversationsModel
    /// Extensions' pages (D62).
    let pages: ExtensionPagesModel
    /// The one bar's search (D58); while it has words, Home shows what it found.
    let find: FindModel

    var selection: HomeSelection? = .now {
        didSet { if selection != oldValue { selectionChanged() } }
    }

    /// The new or edited collection's sheet, opened from the sidebar or the toolbar's New menu.
    var collectionSheet: CollectionSheet.Mode?

    private var eventTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var pending: Set<DataDomain> = []

    init(services: AppServices) {
        self.services = services
        now = NowModel(services: services)
        notebook = NotebookModel(services: services)
        activity = ActivityModel(services: services)
        conversations = ConversationsModel(services: services)
        pages = ExtensionPagesModel(services: services)
        find = FindModel { query in (try? await services.runtime.find(query)) ?? SearchResults() }
        now.openPage = { [weak self] id in self?.selection = .page(id) }
    }

    /// Sends the one bar's words on, and empties it.
    func send(_ how: AskHow) {
        let text = find.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        find.query = ""
        services.ask(text, how: how)
    }

    var companionName: String { services.runtime.settings.current.companionName }

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
    }

    /// Stops following changes and saves any edit in progress.
    func stop() {
        eventTask?.cancel()
        eventTask = nil
        reloadTask?.cancel()
        Task { await notebook.flush() }
    }

    func reloadAll() async {
        await now.reload()
        await notebook.reload()
        await activity.reload()
        await conversations.reload()
        await pages.reload()
        if case .collection(let id) = selection, notebook.collectionId == nil { await notebook.show(collectionId: id) }
    }

    /// Opens the Notebook at an item.
    func reveal(_ item: NotebookItem) async {
        selection = .collection(item.collectionId)
        await notebook.show(collectionId: item.collectionId)
        notebook.select(item.id)
    }

    /// Opens Conversations, at `thread` when given.
    func showConversation(_ thread: String?) async {
        if let thread { conversations.selectedId = thread }
        selection = .conversations
        await conversations.reload()
    }

    /// Picks the Notebook's last collection, or the Inbox.
    /// Goes to one of the four places; the Notebook opens where it was.
    func go(to place: HomeSelection) {
        if case .collection = place { Task { await showNotebook() } } else { selection = place }
    }

    /// A new note in the collection on screen, or the Inbox.
    func newNote() async {
        await showNotebook()
        await notebook.newItem()
    }

    func showNotebook() async {
        if case .collection = selection { return }
        if notebook.collections.isEmpty { await notebook.reloadCollections() }
        if let id = notebook.collectionId ?? notebook.inboxId { selection = .collection(id) }
    }

    private func selectionChanged() {
        switch selection {
        case .collection(let id): Task { await notebook.show(collectionId: id) }
        case .trash: Task { await notebook.reloadTrash() }
        case .activity: Task { await activity.reload() }
        case .conversations: Task { await conversations.reload() }
        case .now, .page, nil: break
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
            // Now shows reminders, watchers, sessions, jobs and attention together; any change can touch it.
            await now.reload()
            if domains.contains(.notebook) || domains.contains(.memories) {
                await notebook.reload()
            } else if domains.contains(.reminders) {
                await notebook.reloadReminders()
            }
            if domains.contains(.activity) || domains.contains(.runs) { await activity.reload() }
            if domains.contains(.conversations) || domains.contains(.settings) { await conversations.reload() }
            if domains.contains(.extensions) {
                await pages.reload()
                if case .page(let id) = selection, pages.info(id) == nil { selection = .now }
            }
        }
    }
}
