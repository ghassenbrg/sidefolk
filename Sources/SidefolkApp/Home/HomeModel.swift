import Foundation
import Observation
import SidefolkCore

/// What the Home sidebar can show.
enum HomeSelection: Hashable {
    case now, conversations, activity, trash
    case collection(String)
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

    var selection: HomeSelection? = .now {
        didSet { if selection != oldValue { selectionChanged() } }
    }

    private var eventTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var pending: Set<DataDomain> = []

    init(services: AppServices) {
        self.services = services
        now = NowModel(services: services)
        notebook = NotebookModel(services: services)
        activity = ActivityModel(services: services)
        conversations = ConversationsModel(services: services)
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
                case .attention: self?.changed(.attention)
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
        case .now, nil: break
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
            if domains.contains(.notebook) || domains.contains(.memories) { await notebook.reload() }
            if domains.contains(.activity) || domains.contains(.runs) { await activity.reload() }
            if domains.contains(.conversations) || domains.contains(.settings) { await conversations.reload() }
        }
    }
}
