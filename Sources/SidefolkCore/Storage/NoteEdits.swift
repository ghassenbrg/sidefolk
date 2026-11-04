import Foundation
import GRDB

/// Saving a note someone else may have changed meanwhile. The Notebook keeps the note open as a draft and writes the
/// whole of it when editing pauses, and an agent's `notes.update` reads the note, works for a while and writes it back
/// whole: either would put the old words back over what the other just saved, and say nothing. Instead a save carries
/// what its author started from (`base`) and changes only what the author changed since, over whatever is stored now.
/// The same field changed by both goes to the one saving later; every other field of the other's change stays.
public enum NoteEdits {
    /// Every field a person or an agent can change, and no other: not the id, when it was made, the Trash or the run
    /// that saved it. The same list is in `same` below.
    /// `theirs` (what is stored now) with every field `mine` changed from `base`. `updatedAt` stays `theirs`.
    public static func apply(_ mine: NotebookItem, since base: NotebookItem, onto theirs: NotebookItem) -> NotebookItem {
        var merged = theirs
        merged.collectionId = take(\.collectionId, mine, base, merged)
        merged.kind = take(\.kind, mine, base, merged)
        merged.title = take(\.title, mine, base, merged)
        merged.body = take(\.body, mine, base, merged)
        merged.url = take(\.url, mine, base, merged)
        merged.tags = take(\.tags, mine, base, merged)
        merged.status = take(\.status, mine, base, merged)
        merged.dueAt = take(\.dueAt, mine, base, merged)
        merged.dueAllDay = take(\.dueAllDay, mine, base, merged)
        merged.source = take(\.source, mine, base, merged)
        merged.pinnedAt = take(\.pinnedAt, mine, base, merged)
        return merged
    }

    /// Whether `a` and `b` say the same in every field a person or an agent can change.
    public static func same(_ a: NotebookItem, _ b: NotebookItem) -> Bool {
        a.collectionId == b.collectionId && a.kind == b.kind && a.title == b.title && a.body == b.body && a.url == b.url
            && a.tags == b.tags && a.status == b.status && a.dueAt == b.dueAt && a.dueAllDay == b.dueAllDay
            && a.source == b.source && a.pinnedAt == b.pinnedAt
    }

    private static func take<T: Equatable>(_ key: KeyPath<NotebookItem, T>, _ mine: NotebookItem, _ base: NotebookItem,
                                           _ theirs: NotebookItem) -> T {
        mine[keyPath: key] != base[keyPath: key] ? mine[keyPath: key] : theirs[keyPath: key]
    }
}

extension NotebookStore {
    /// Saves `edited`, changed from `base`, over the note as stored now, in one step so nothing can land between the
    /// read and the write. Returns what is stored afterwards, or nil when the note is gone or in the Trash (an edit
    /// never brings it back; an undo that must still put words back passes `inTheTrash`). A save that changes nothing
    /// writes nothing and leaves `updatedAt` alone.
    public func save(_ edited: NotebookItem, from base: NotebookItem, now: Date = Date(), inTheTrash: Bool = false) async throws -> NotebookItem? {
        try await db.writer.write { db in
            guard let stored = try NotebookItem.fetchOne(db, key: edited.id), inTheTrash || stored.deletedAt == nil else { return nil }
            var merged = NoteEdits.apply(edited, since: base, onto: stored)
            guard !NoteEdits.same(merged, stored) else { return stored }
            merged.updatedAt = now
            try Self.write(merged, over: stored, in: db)
            return merged
        }
    }
}
