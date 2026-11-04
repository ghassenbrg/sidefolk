import Foundation
import Observation
import SidefolkCore

/// The Notebook as the Home window edits it: collections, the items of one collection, the item
/// being edited (saved when editing pauses or ends), and the Trash. These are the user's own
/// edits to Sidefolk's data, so they go straight to the store and announce `.notebook`.
@MainActor @Observable
final class NotebookModel {
    enum KindFilter: String, CaseIterable, Identifiable {
        case all, notes, ideas, tasks, links
        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .all: "All"
            case .notes: "Notes"
            case .ideas: "Ideas"
            case .tasks: "Tasks"
            case .links: "Links"
            }
        }

        var kind: NotebookItem.Kind? {
            switch self {
            case .all: nil
            case .notes: .note
            case .ideas: .idea
            case .tasks: .task
            case .links: .link
            }
        }
    }

    struct ToastState: Identifiable {
        let id = UUID()
        var message: String
        var actionTitle: String?
        var action: (() -> Void)?
    }

    static let profileName = "About you"

    var collections: [NotebookCollection] = []
    private(set) var archived: [NotebookCollection] = []
    private(set) var counts: [String: Int] = [:]
    /// What the Notebook's own page shows (D134).
    private(set) var overview = NotebookOverview()
    private(set) var trash: [NotebookItem] = []
    private(set) var items: [NotebookItem] = []
    private(set) var collectionId: String?

    var filter: KindFilter = .all {
        didSet { if filter != oldValue { scheduleItemsReload() } }
    }
    var query = "" {
        didSet { if query != oldValue { scheduleItemsReload(delay: .milliseconds(200)) } }
    }
    /// A search looks in every collection instead of only the open one.
    var everywhere = false {
        didSet { if everywhere != oldValue, !query.trimmingCharacters(in: .whitespaces).isEmpty { scheduleItemsReload() } }
    }

    /// Each item's next reminder (D49), for the bell beside it.
    private(set) var reminders: [String: Reminder] = [:]
    /// The item whose reminder time is being picked.
    var pickingTime: NotebookItem?
    var pickingDue: NotebookItem?

    private(set) var selectedId: String?
    /// Where the selected item was made and changed (D58), for its Connected list.
    private(set) var conversations = ItemConversations()
    private var conversationsTask: Task<Void, Never>?
    /// The selected item as edited; written back when editing pauses, the selection changes or the window closes.
    var draft: NotebookItem? {
        didSet { if draft != oldValue, draft != nil, draft?.id == oldValue?.id { scheduleSave() } }
    }
    /// The draft as it was last stored or read from the store: what the person has changed is the difference, and only
    /// that is written back, over whatever an agent or another part of the app stored meanwhile (`NoteEdits`).
    private var base: NotebookItem?
    /// An item created here and not yet given any content; dropped if left empty.
    private var freshId: String?

    var toast: ToastState?

    let services: AppServices
    private var runtime: SidefolkRuntime { services.runtime }
    private var store: NotebookStore { runtime.notebook }
    private var saveTask: Task<Void, Never>?
    private var itemsTask: Task<Void, Never>?
    private var showing: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
    }

    var current: NotebookCollection? { collection(id: collectionId) }

    func collection(id: String?) -> NotebookCollection? {
        guard let id else { return nil }
        return (collections + archived).first { $0.id == id }
    }

    var inboxId: String? { collections.first { $0.kind == .inbox }?.id }
    var trashCount: Int { trash.count }

    // MARK: Loading

    func reload() async {
        await reloadCollections()
        await reloadItems()
        await adoptStoredChanges()
        await reloadTrash()
        await reloadReminders()
        loadConversations()
    }

    func reloadReminders() async {
        reminders = (try? await runtime.reminderStore.next()) ?? [:]
    }

    func reloadCollections() async {
        await ensureProfile()
        let all = (try? await store.collections(includeArchived: true)) ?? []
        let rank: (NotebookCollection) -> Int = { $0.kind == .inbox ? 0 : $0.kind == .profile ? 1 : 2 }
        let sorted = all.sorted { (rank($0), $0.sortOrder, $0.name.lowercased()) < (rank($1), $1.sortOrder, $1.name.lowercased()) }
        collections = sorted.filter { $0.archivedAt == nil }
        archived = sorted.filter { $0.archivedAt != nil }
        let live = (try? await store.items(limit: 100_000)) ?? []
        counts = Dictionary(grouping: live, by: \.collectionId).mapValues(\.count)
        overview = NotebookOverview(collections: collections, items: live)
    }

    /// Everything that matches, whichever collection it's in, for the Notebook's own page.
    func searchEverything(_ query: String) async -> [NotebookItem] {
        (try? await store.search(query.trimmingCharacters(in: .whitespacesAndNewlines), limit: 50)) ?? []
    }

    /// The name people see (the Inbox and “About you” in the app's language).
    func collectionName(_ id: String) -> String? { collection(id: id).map(NotebookCollections.shownName) }

    /// "About you" is part of the Notebook from day one (DECISIONS D6).
    private func ensureProfile() async {
        let all = (try? await store.collections(includeArchived: true)) ?? []
        guard !all.contains(where: { $0.kind == .profile }) else { return }
        _ = await createCollection(named: Self.profileName, kind: .profile)
    }

    /// The Tasks tab: pinned as ever, then what's due, soonest first, then the rest as they were (D117). A sort that
    /// keeps its place among equals, so nothing else moves.
    static func dueFirst(_ items: [NotebookItem]) -> [NotebookItem] {
        func rank(_ item: NotebookItem) -> (Int, Date) {
            if item.pinnedAt != nil { return (0, .distantPast) }
            if item.status == .open, let due = item.dueAt { return (1, due) }
            return (2, .distantPast)
        }
        return items.enumerated().sorted { a, b in
            let (ra, rb) = (rank(a.element), rank(b.element))
            return ra == rb ? a.offset < b.offset : ra < rb
        }.map(\.element)
    }

    func reloadItems() async {
        guard let collectionId else {
            items = []
            return
        }
        let kinds = filter.kind.map { [$0] }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            items = (try? await store.items(collectionId: collectionId, kinds: kinds, limit: 1000)) ?? []
            if filter.kind == .task { items = Self.dueFirst(items) }
        } else {
            items = (try? await store.search(q, collectionId: everywhere ? nil : collectionId, kinds: kinds, limit: 200)) ?? []
        }
        if let selectedId, !items.contains(where: { $0.id == selectedId }), draft?.collectionId != collectionId {
            select(nil)
        }
    }

    func reloadTrash() async {
        trash = (try? await store.deletedItems(limit: 500)) ?? []
    }

    private func scheduleItemsReload(delay: Duration = .zero) {
        itemsTask?.cancel()
        itemsTask = Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await reloadItems()
        }
    }

    // MARK: Selection and editing

    /// One at a time: choosing a place opens its collection, and whoever chose it may then wait for the same one and add to it.
    func show(collectionId id: String) async {
        await showing?.value
        guard id != collectionId else { return }
        let opening = Task {
            await flush()
            collectionId = id
            query = ""
            filter = .all
            select(nil)
            await reloadItems()
        }
        showing = opening
        await opening.value
    }

    func select(_ id: String?) {
        guard id != selectedId else { return }
        let leaving = draft, leavingBase = base
        saveTask?.cancel()
        selectedId = id
        draft = items.first { $0.id == id }
        base = draft
        if let leaving, let leavingBase { Task { await write(leaving, from: leavingBase) } }
        loadConversations()
        // The list may be a moment behind the store: show what is stored.
        Task { await adoptStoredChanges() }
    }

    /// Takes in what was stored since the draft was read (an agent's `notes_update`, a change from another part of the
    /// app): the fields the person hasn't touched show it, the ones they have keep their words. Without this the open
    /// note kept showing, and later saved, the old text.
    func adoptStoredChanges() async {
        guard let mine = draft, let was = base, mine.id == was.id,
              let stored = try? await store.item(id: mine.id), stored.deletedAt == nil, !NoteEdits.same(stored, was) else { return }
        // The draft's own change is what saves next, so the base moves first: a save in between sees only the person's edits.
        base = stored
        let merged = NoteEdits.apply(mine, since: was, onto: stored)
        if merged != mine, draft?.id == mine.id { draft = merged }
    }

    private func loadConversations() {
        conversationsTask?.cancel()
        guard let item = draft else {
            conversations = ItemConversations()
            return
        }
        conversationsTask = Task {
            let found = (try? await runtime.exchanges.conversations(about: item)) ?? ItemConversations()
            guard !Task.isCancelled, selectedId == item.id else { return }
            conversations = found
        }
    }

    /// Saves the draft now (window closing, collection switch).
    func flush() async {
        saveTask?.cancel()
        if let draft, let base { await write(draft, from: base) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let draft, let base else { return }
            await write(draft, from: base)
        }
    }

    private func write(_ edited: NotebookItem, from base: NotebookItem) async {
        guard let stored = try? await store.item(id: edited.id), stored.deletedAt == nil else { return }
        let isEmpty = edited.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && edited.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if edited.id == freshId, isEmpty, selectedId != edited.id {
            // A new note the user never wrote anything in: nothing to keep.
            try? await store.purge(itemId: edited.id)
            freshId = nil
            runtime.events.changed(.notebook)
            return
        }
        guard !NoteEdits.same(stored, edited) else { return }
        // Only what the person changed since `base`, over what is stored now: an agent's change to the other fields stays.
        guard let item = try? await store.save(edited, from: base), item != stored else { return }
        if !isEmpty, item.id == freshId { freshId = nil }
        if item.id == draft?.id {
            // What was saved is the new base; fields the person hasn't touched since this save began show what is stored.
            self.base = item
            draft = NoteEdits.apply(draft ?? item, since: edited, onto: item)
        }
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
        if item.collectionId != stored.collectionId, item.collectionId != collectionId {
            let name = collectionName(item.collectionId) ?? String(localized: "another collection")
            if selectedId == item.id {
                selectedId = nil
                draft = nil
                self.base = nil
            }
            items.removeAll { $0.id == item.id }
            showToast(String(localized: "Moved to \(name)."))
        }
        runtime.events.changed(.notebook)
    }

    func newItem() async {
        guard let collectionId else { return }
        let kind = filter.kind ?? .note
        let item = NotebookItem(collectionId: collectionId, kind: kind, title: "", source: "user")
        try? await store.add(item)
        freshId = item.id
        query = ""
        await reloadItems()
        select(item.id)
    }

    func toggleDone(_ item: NotebookItem) async {
        let next: NotebookItem.Status = item.status == .done ? .open : .done
        if draft?.id == item.id {
            draft?.status = next
        } else {
            _ = try? await store.setStatus(itemId: item.id, next)
            runtime.events.changed(.notebook)
        }
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].status = next }
    }

    /// Pinned items come first in their collection.
    func togglePin(_ item: NotebookItem) async {
        let pinned = item.pinnedAt == nil
        await flush()
        try? await store.setPinned(itemId: item.id, pinned)
        if draft?.id == item.id {
            let at = pinned ? Date() : nil
            draft?.pinnedAt = at
            base?.pinnedAt = at
        }
        runtime.events.changed(.notebook)
        await reloadItems()
    }

    func moveToTrash(_ item: NotebookItem) async {
        if draft?.id == item.id {
            await flush()
            select(nil)
        }
        _ = try? await store.trash(itemId: item.id)
        runtime.events.changed(.notebook)
        await reloadItems()
        await reloadTrash()
        let message = item.title.isEmpty ? String(localized: "Moved to the Trash.")
            : String(localized: "“\(item.title.clipped(40))” moved to the Trash.")
        showToast(message, actionTitle: String(localized: "Undo")) { [weak self] in
            Task { await self?.restore(item, quietly: true) }
        }
    }

    func restore(_ item: NotebookItem, quietly: Bool = false) async {
        try? await store.restore(itemId: item.id)
        runtime.events.changed(.notebook)
        await reloadItems()
        await reloadTrash()
        toast = nil
        if !quietly {
            showToast(String(localized: "Restored to \(collectionName(item.collectionId) ?? String(localized: "the Notebook"))."))
        }
    }

    /// Only the user, from the Trash, removes an item for good.
    func deleteForever(_ item: NotebookItem) async {
        try? await store.purge(itemId: item.id)
        runtime.events.changed(.notebook)
        await reloadTrash()
    }

    /// Only the user, from the Trash, empties it.
    func emptyTrash() async {
        _ = try? await store.emptyTrash()
        runtime.events.changed(.notebook)
        await reloadTrash()
    }

    // MARK: Reminders (D49)

    enum RemindPreset: CaseIterable {
        case inAnHour, thisEvening, tomorrowMorning

        /// In the words the reminder parser reads, so "evening" and "morning" are the person's own hours.
        var phrase: String {
            switch self {
            case .inAnHour: "in 1 hour"
            case .thisEvening: "this evening"
            case .tomorrowMorning: "tomorrow morning"
            }
        }

        var title: String {
            switch self {
            case .inAnHour: String(localized: "In an hour")
            case .thisEvening: String(localized: "This evening")
            case .tomorrowMorning: String(localized: "Tomorrow morning")
            }
        }
    }

    /// The quick times that still make sense now, and when each would come ("This evening" only before the evening).
    func remindPresets(now: Date = Date()) -> [(preset: RemindPreset, date: Date)] {
        let parser = WhenParser(settings: runtime.settings.current)
        return RemindPreset.allCases.compactMap { preset in
            guard let found = parser.parse(preset.phrase, now: now), found.confidence != .low, found.date > now else { return nil }
            if preset == .thisEvening, !parser.calendar.isDate(found.date, inSameDayAs: now) { return nil }
            return (preset, found.date)
        }
    }

    /// A reminder that belongs to `item`, through the reminder tool like any reminder the person sets; `phrase` is what
    /// they typed for it ("every monday at 9" keeps its repeat), else the time itself.
    func remind(_ item: NotebookItem, at date: Date, phrase: String? = nil) async {
        await flush()
        let stored = (try? await store.item(id: item.id)) ?? item
        if let problem = await services.remind(about: stored, when: phrase ?? ISO8601DateFormatter().string(from: date)) {
            showToast(problem.message)
        } else {
            showToast(String(localized: "I'll remind you \(TimeFormat.when(date, now: Date(), calendar: .autoupdatingCurrent)).",
                             comment: "After setting a reminder for a note or task: “I'll remind you Tomorrow 09:00.”"))
        }
        await reloadReminders()
    }

    /// Cancels the item's next reminder; a later one, if any, shows next.
    func removeReminder(of item: NotebookItem) async {
        guard let reminder = reminders[item.id] else { return }
        await services.cancelReminder(reminder.id)
        await reloadReminders()
    }

    // MARK: Collections

    /// The person dragged a collection in the sidebar; the Inbox stays first (D117).
    func arrange(from: IndexSet, to: Int) {
        var shown = collections.filter { $0.kind != .profile }
        shown.move(fromOffsets: from, toOffset: to)
        let ids = shown.map(\.id)
        collections = collections.filter { $0.kind == .profile } + shown
        Task {
            try? await store.arrangeCollections(ids)
            runtime.events.changed(.notebook)
            await reloadCollections()
        }
    }

    /// A task's due date, or none (D117). Not a reminder: it nudges nobody; it stands here and on the Calendar.
    func setDue(_ item: NotebookItem, at date: Date?, allDay: Bool) async {
        guard var fresh = try? await store.item(id: item.id) else { return }
        fresh.dueAt = date
        fresh.dueAllDay = date != nil && allDay
        fresh.updatedAt = Date()
        try? await store.update(fresh)
        runtime.events.changed(.notebook)
        await reloadItems()
    }

    /// Creates a collection with exactly this name (refusing duplicates, case-insensitively).
    @discardableResult
    func createCollection(named name: String, kind: NotebookCollection.Kind) async -> Result<NotebookCollection, UserFacingError> {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return .failure(UserFacingError("Give the collection a name.")) }
        let existing = (try? await store.collections(includeArchived: true)) ?? []
        if existing.contains(where: { $0.name.lowercased() == clean.lowercased() }) {
            return .failure(UserFacingError("There's already a collection called “\(clean)”.", recovery: "Pick another name."))
        }
        do {
            let created = try await store.createCollection(name: clean, kind: kind)
            runtime.events.changed(.notebook)
            await reloadCollections()
            return .success(collection(id: created.id) ?? created)
        } catch {
            return .failure(UserFacingError("I couldn't create that collection. Nothing was changed.", detail: String(describing: error)))
        }
    }

    func rename(_ c: NotebookCollection, to name: String) async -> UserFacingError? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return UserFacingError("Give the collection a name.") }
        if collections.contains(where: { $0.id != c.id && $0.name.lowercased() == clean.lowercased() }) {
            return UserFacingError("There's already a collection called “\(clean)”.", recovery: "Pick another name.")
        }
        try? await store.rename(collectionId: c.id, to: clean)
        runtime.events.changed(.notebook)
        await reloadCollections()
        return nil
    }

    func setLook(_ c: NotebookCollection, emoji: String, symbol: String?, color: String?) async {
        let emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        try? await store.setLook(collectionId: c.id, emoji: emoji.isEmpty ? nil : emoji, symbol: symbol, color: color)
        runtime.events.changed(.notebook)
        await reloadCollections()
    }

    func setArchived(_ c: NotebookCollection, _ archived: Bool) async {
        try? await store.setArchived(collectionId: c.id, archived)
        runtime.events.changed(.notebook)
        await reloadCollections()
        showToast(archived ? String(localized: "Archived “\(c.name)”.") : String(localized: "“\(c.name)” is back."))
    }

    /// Deleting a collection never deletes notes outright: its items move to the Trash (as Inbox
    /// items, so a restore has somewhere to go), then the empty collection is removed.
    func delete(_ c: NotebookCollection) async {
        guard c.kind != .inbox, c.kind != .profile, let inboxId else { return }
        if collectionId == c.id {
            await flush()
            select(nil)
        }
        let now = Date()
        let contained = (try? await store.items(collectionId: c.id, includeDeleted: true, limit: 100_000)) ?? []
        for var item in contained {
            item.collectionId = inboxId
            if item.deletedAt == nil { item.deletedAt = now }
            item.updatedAt = now
            try? await store.update(item)
        }
        try? await store.deleteCollection(id: c.id)
        runtime.events.changed(.notebook)
        if collectionId == c.id { collectionId = nil }
        await reload()
        showToast(contained.isEmpty ? String(localized: "Deleted “\(c.name)”.")
            : String(localized: "Deleted “\(c.name)”. Its items are in the Trash."))
    }

    // MARK: Toast

    func showToast(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        toast = ToastState(message: message, actionTitle: actionTitle, action: action)
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }
}

private extension NotebookItem {
    func sameContent(as other: NotebookItem) -> Bool {
        title == other.title && body == other.body && kind == other.kind && collectionId == other.collectionId
            && tags == other.tags && status == other.status && url == other.url
    }
}
