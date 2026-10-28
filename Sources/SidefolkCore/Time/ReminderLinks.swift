import Foundation
import GRDB

/// Reminders that belong to a note or task follow it (D49). A task marked done or an item moved to the Trash ends the
/// reminders still waiting for it (a repeating one stops), and they come back when the task is opened again or the item
/// restored, if their time is still ahead. Every way an item changes (the Notebook, the tools, Undo, other agents)
/// announces `.notebook`, and the scheduler settles the links then; `fire` checks once more, so a reminder never fires
/// for a task finished a moment before.
extension ReminderScheduler {
    /// Why `item` ends the reminders that belong to it, if it does. An item that no longer exists counts as trashed.
    static func endReason(_ item: NotebookItem?) -> Reminder.EndedWithItem? {
        guard let item, item.deletedAt == nil else { return .trashed }
        return item.kind == .task && item.status == .done ? .done : nil
    }

    /// A one-off reminder whose task was done is done too; anything else stops. The snooze stays, so a reminder that
    /// comes back returns to its snoozed time.
    static func end(_ r: inout Reminder, with reason: Reminder.EndedWithItem) {
        r.state = reason == .done && r.recurrence == nil ? .done : .cancelled
        r.endedWithItem = reason
    }

    /// Brings every reminder in line with its item: ends the ones whose item ended, brings back the ones whose item came
    /// back, and takes away the bubble of one that fired for a task done since.
    public func settleLinks() async {
        let now = clock.now
        let recently = now.addingTimeInterval(-86_400).timeIntervalSince1970
        guard let linked = try? await store.db.writer.read({ db in
            try Reminder.filter(Column("item_id") != nil)
                .filter(["scheduled", "snoozed"].contains(Column("state")) || Column("ended_with_item") != nil
                    || (Column("state") == Reminder.State.fired.rawValue && Column("last_fired_at") > recently))
                .fetchAll(db)
        }), !linked.isEmpty else { return }
        let found = (try? await NotebookStore(store.db).items(ids: Array(Set(linked.compactMap(\.itemId))))) ?? []
        let items = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var changed = false
        var answered: [String] = []
        for r in linked {
            guard let itemId = r.itemId else { continue }
            let reason = Self.endReason(items[itemId])
            switch r.state {
            case .scheduled, .snoozed:
                guard let reason else { continue }
                let ended = try? await update(r.id) { r in
                    guard r.state == .scheduled || r.state == .snoozed else { return false }
                    Self.end(&r, with: reason)
                    return true
                }
                if let ended, ended.before.state != ended.after.state {
                    changed = true
                    answered.append(r.id)
                }
            case .fired:
                if reason != nil { answered.append(r.id) }
            case .done, .cancelled:
                if r.endedWithItem != nil, reason == nil, await bringBack(r) { changed = true }
            }
        }
        // A bubble asking about a task that is done now has nothing left to ask.
        for id in answered { await attention.withdraw(refKind: "reminder", refId: id) }
        if changed { await finishChange() }
    }

    /// A reminder whose item came back: waiting again at its snoozed time, its own time or its series' next time, if
    /// any is still ahead. Either way it no longer waits for its item. True when it changed.
    private func bringBack(_ reminder: Reminder) async -> Bool {
        let now = clock.now
        let anchor = await seriesAnchor(for: reminder)
        let cal = calendar
        let changed = try? await update(reminder.id) { r in
            guard r.endedWithItem != nil, r.state == .done || r.state == .cancelled else { return false }
            r.endedWithItem = nil
            if let until = r.snoozedUntil, until > now {
                r.state = .snoozed
                return true
            }
            r.snoozedUntil = nil
            if r.fireAt > now {
                r.state = .scheduled
            } else if let rule = r.recurrence, let next = RecurrenceMath.nextOccurrence(after: now, recurrence: rule, anchor: anchor, calendar: cal) {
                r.fireAt = next
                r.state = .scheduled
            }
            return true
        }
        return changed != nil
    }

    /// The note or task a reminder belongs to, while it is in the notebook.
    func linkedItem(_ r: Reminder) async -> NotebookItem? {
        guard let id = r.itemId, let item = try? await NotebookStore(store.db).item(id: id), item.deletedAt == nil else { return nil }
        return item
    }

    /// "Task: Send the report", under a reminder whose own words differ from its item's title.
    static func itemLine(_ item: NotebookItem, reminder r: Reminder) -> String? {
        let title = item.title.clipped(120)
        guard !title.isEmpty, title.lowercased() != r.title.lowercased() else { return nil }
        return switch item.kind {
        case .task: String(localized: "Task: \(title)", comment: "Under a reminder: the task it belongs to")
        case .note: String(localized: "Note: \(title)", comment: "Under a reminder: the note it belongs to")
        case .idea: String(localized: "Idea: \(title)", comment: "Under a reminder: the idea it belongs to")
        case .link: String(localized: "Link: \(title)", comment: "Under a reminder: the saved link it belongs to")
        }
    }

    /// "Mark done" on a reminder that belongs to a task: the task is done, this time is answered, and the rest of a
    /// series stops with the task.
    func finishTask(reminderId id: String) async throws {
        guard let r = try await store.reminder(id: id), let itemId = r.itemId else {
            try await complete(id: id)
            return
        }
        let notebook = NotebookStore(store.db)
        if let item = try await notebook.item(id: itemId), item.kind == .task, item.status == .open, item.deletedAt == nil {
            _ = try await notebook.setStatus(itemId: itemId, .done, now: clock.now)
            events.changed(.notebook)
        }
        try await complete(id: id)
        await settleLinks()
    }
}
