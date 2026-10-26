import Foundation

// Copying Apple Notes into the notebook, and removing copied notes from Notes when the person asked
// to move them. Copying never changes Notes. Removing is high risk, asked every time, and only for a
// note whose whole copy is in the notebook and which Notes will keep in Recently Deleted.

struct AppleNotesCopyTool: Tool {
    let notes: AppleNotes
    let ledger: AppleNotesLedger
    let notebook: NotebookStore
    let events: EventBus
    static let maxNotes = 50
    /// Longer notes are cut, and their copy counts as incomplete (so the original is never removed).
    static let maxBody = 100_000

    let spec = ToolSpec(
        name: "applenotes.copy", title: String(localized: "Copy Apple Notes to the notebook"),
        description: """
            Copy Apple Notes into the user's notebook, each into the collection you choose for it (created if missing; \
            `collection_kind` says what a new one is). The whole text is copied as written, with a line saying where it \
            came from (Apple Notes folder and dates); attachments stay in Notes and are named. Notes already copied and \
            locked notes are skipped. Up to 50 notes per call: for a big library, copy a batch, report progress, and continue \
            with the next batch (applenotes_list with not_copied). This never changes Apple Notes.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(["notes": .object([
                "type": "array", "description": "Which notes go where",
                "maxItems": .number(Double(maxNotes)),
                "items": .object([
                    "type": "object",
                    "properties": .object([
                        "id": Schema.string("Note id from applenotes_list"),
                        "collection": Schema.string("Notebook collection to put it in, e.g. “Recipes”"),
                        "collection_kind": Schema.string("Only when the collection has to be created: project (default), topic or list",
                                                         enum: ["project", "topic", "list"]),
                    ]),
                    "required": ["id", "collection"],
                    "additionalProperties": false,
                ]),
            ])]),
            "required": ["notes"],
            "additionalProperties": false,
        ]),
        risk: .medium, capabilities: [.macApps, .notebook], category: .notes, mutates: true)

    struct Assignment {
        var id: String
        var collection: String
        var kind: JSONValue?
    }

    static func assignments(_ input: JSONValue) throws -> [Assignment] {
        var seen = Set<String>()
        var out: [Assignment] = []
        for entry in input["notes"]?.arrayValue ?? [] {
            guard let id = entry.string("id"), let collection = entry.string("collection") else {
                throw UserFacingError("Each entry in “notes” needs an “id” and a “collection”.")
            }
            guard collection.count <= 60 else { throw UserFacingError("A collection name is too long (the limit is 60 characters).") }
            if seen.insert(id).inserted { out.append(Assignment(id: id, collection: collection, kind: entry["collection_kind"])) }
        }
        guard !out.isEmpty else { throw UserFacingError("“notes” needs at least one note.") }
        guard out.count <= maxNotes else { throw UserFacingError("That's too many notes for one step (the limit is \(maxNotes)).") }
        return out
    }

    /// A malformed list is refused before anyone is asked to approve it.
    func refusal(for input: JSONValue, context: ToolContext) -> String? {
        do {
            _ = try Self.assignments(input)
            return nil
        } catch {
            return ToolExecutor.userFacing(error, tool: spec).message
        }
    }

    func summary(for input: JSONValue) -> String {
        let list = (try? Self.assignments(input)) ?? []
        var names: [String] = []
        for a in list where !names.contains(a.collection.clipped(40)) { names.append(a.collection.clipped(40)) }
        return String(localized: "Copy \(list.count) notes from Apple Notes into \(Wording.names(names.map { "“\($0)”" }))")
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let list = try Self.assignments(input)
        return try await MacAppAccess.run(.notes) {
            let (found, unknown) = try await AppleNotesPlaces.resolve(list.map(\.id), notes: notes)
            let index = try await notes.index()
            let copied = try await ledger.load()
            var assigned: [String: Assignment] = [:]
            for a in list { if let note = index.note(a.id) { assigned[note.id] = a } }

            var skipped: [String] = unknown.map { "\(MacAppAccess.line($0, 40)): not found (list the notes again)" }
            var wanted: [NoteSummary] = []
            for note in found {
                let label = "\(note.handle) “\(MacAppAccess.line(note.title, 80))”"
                if index.isRecentlyDeleted(note) {
                    skipped.append("\(label): it is in Recently Deleted")
                } else if note.locked {
                    skipped.append("\(label): it is locked; the user can unlock it in Notes")
                } else if let entry = copied[note.id], let item = try await notebook.item(id: entry.itemId), item.deletedAt == nil {
                    skipped.append("\(label): already in the notebook (id \(item.id))")
                } else {
                    wanted.append(note)
                }
            }

            let fetched = try await notes.fetch(wanted.map(\.id), maxChars: 400_000)
            var collections: [String: NotebookCollection] = [:]
            var made: [(note: FetchedNote, item: NotebookItem, collection: NotebookCollection)] = []
            var entries: [String: AppleNotesLedger.Entry] = [:]
            for note in fetched {
                guard let assignment = assigned[note.id] else { continue }
                let label = "\(AppleNotes.handle(for: note.id)) “\(MacAppAccess.line(note.title, 80))”"
                if let code = note.unreadable {
                    skipped.append("\(label): Notes wouldn't hand over its text (Apple Events error \(code)); it stays in Notes")
                    continue
                }
                let collection: NotebookCollection
                do {
                    if let known = collections[assignment.collection.lowercased()] {
                        collection = known
                    } else {
                        collection = try await NotebookCollections.resolveOrCreate(
                            assignment.collection, kind: try NotebookCollections.newKind(assignment.kind), notebook: notebook, context: context).collection
                        collections[assignment.collection.lowercased()] = collection
                    }
                } catch {
                    skipped.append("\(label): \(ToolExecutor.userFacing(error, tool: spec).message)")
                    continue
                }
                let place = index.folder(note.folderId)?.place ?? note.folderName
                let (item, complete) = Self.item(for: note, place: place, collection: collection, now: context.now)
                do {
                    try await notebook.add(item)
                } catch {
                    // What is already in the notebook stays known, so trying again doesn't copy it twice.
                    try? await ledger.record(entries)
                    throw error
                }
                made.append((note, item, collection))
                entries[note.id] = AppleNotesLedger.Entry(itemId: item.id, title: note.title.clipped(120), place: place, modified: note.modified,
                                                          complete: complete, copiedAt: context.now)
            }
            let gone = wanted.filter { w in !fetched.contains { $0.id == w.id } }
            skipped += gone.map { "\($0.handle) “\(MacAppAccess.line($0.title, 80))”: no longer in Notes" }
            if !entries.isEmpty {
                try await ledger.record(entries)
                events.changed(.notebook)
            }
            return try await result(made: made, skipped: skipped, index: index)
        }
    }

    /// The notebook item for a note: its title, its text as Markdown, the names of attachments left in
    /// Notes, and where it came from. Dated as in Notes. Source "app:notes": a copy is outside content
    /// (SECURITY T2, T3), so reading it back later taints the turn and it is never offered unasked.
    static func item(for note: FetchedNote, place: String, collection: NotebookCollection, now: Date) -> (NotebookItem, complete: Bool) {
        var body = note.markdown
        var cut = note.truncated
        if body.count > maxBody {
            body = String(body.prefix(maxBody)) + "\n\n[…]"
            cut = true
        }
        var extras: [String] = []
        if !note.attachments.isEmpty {
            extras.append(String(localized: "Attachments left in Apple Notes: \(Wording.list(note.attachments.map { $0.clipped(60) }))"))
        }
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Wording.locale)
        let dates = [note.created.map { String(localized: "created \($0.formatted(style))") },
                     note.modified.map { String(localized: "changed \($0.formatted(style))") }].compactMap { $0 }
        let origin = dates.isEmpty ? String(localized: "From Apple Notes › \(place)")
            : String(localized: "From Apple Notes › \(place) · \(dates.joined(separator: ", "))")
        extras.append("*\(origin)*")
        body = ((body.isEmpty ? [] : [body]) + extras).joined(separator: "\n\n")
        let title = note.title.trimmedText.isEmpty ? String(localized: "Untitled note") : note.title.trimmedText.clipped(NoteText.maxTitle)
        var item = NotebookItem(collectionId: collection.id, kind: .note, title: title, body: body, tags: ["apple-notes"],
                                source: "app:notes", now: now)
        item.createdAt = note.created ?? now
        item.updatedAt = note.modified ?? item.createdAt
        return (item, !cut && note.attachments.isEmpty && !note.attachmentsPartial)
    }

    private func result(made: [(note: FetchedNote, item: NotebookItem, collection: NotebookCollection)], skipped: [String],
                        index: NotesIndex) async throws -> ToolResult {
        var lines: [String] = []
        if made.isEmpty {
            lines.append("Copied nothing.")
        } else {
            lines.append("Copied \(ToolFormat.count(made.count, "note")) into the notebook:")
            lines += made.map { m in
                "- \(AppleNotes.handle(for: m.note.id)) “\(MacAppAccess.line(m.note.title, 80))” → \(MacAppAccess.line(m.collection.name, 60)) (id \(m.item.id))"
                    + (m.note.attachments.isEmpty ? "" : ", \(ToolFormat.count(m.note.attachments.count, "attachment")) left in Notes")
            }
        }
        if !skipped.isEmpty { lines.append("Not copied:\n" + skipped.map { "- " + $0 }.joined(separator: "\n")) }
        let copied = try await ledger.load()
        let live = index.live
        let done = live.filter { copied[$0.id] != nil }.count
        let locked = live.filter { $0.locked && copied[$0.id] == nil }.count
        var progress = "Progress: \(done) of \(live.count) notes in Apple Notes are in the notebook; \(live.count - done - locked) to go"
        progress += locked > 0 ? " (and \(locked) locked)." : "."
        lines.append(progress)

        var names: [String] = []
        for m in made where !names.contains(NotebookCollections.shownName(m.collection)) { names.append(NotebookCollections.shownName(m.collection)) }
        let title = made.isEmpty ? String(localized: "Nothing new to copy from Apple Notes")
            : String(localized: "Copied \(made.count) notes from Apple Notes")
        let ids = made.map(\.item.id), noteIds = made.map(\.note.id)
        let notebook = self.notebook, ledger = self.ledger, events = self.events
        return ToolResult(
            text: lines.joined(separator: "\n"),
            card: ResultCard(kind: .note, title: title, subtitle: names.isEmpty ? nil : Wording.names(names, max: 4),
                             detail: String(localized: "\(done) of \(live.count) copied so far"), refId: ids.first, itemKind: .note),
            undo: made.isEmpty ? nil : UndoAction(label: String(localized: "Removed \(made.count) copied notes")) {
                for id in ids { _ = try await notebook.trash(itemId: id) }
                try await ledger.forget(noteIds)
                events.changed(.notebook)
            },
            untrusted: true)
    }
}

struct AppleNotesRemoveTool: Tool {
    let notes: AppleNotes
    let ledger: AppleNotesLedger
    let notebook: NotebookStore
    static let maxNotes = 50

    let spec = ToolSpec(
        name: "applenotes.remove", title: String(localized: "Remove notes from Apple Notes"),
        description: """
            Move Apple Notes that are already copied into the notebook to Notes' Recently Deleted folder (Notes keeps them \
            30 days). Only when the user explicitly asked to move notes out of Apple Notes or to delete them there; copying \
            is the default, and "organize" or "copy" never means removing. Notes whose copy isn't complete (attachments, \
            a cut body), that changed since they were copied, or that are locked stay in Notes. The user approves every call.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(["ids": .object([
                "type": "array", "description": "Ids of notes already copied with applenotes_copy",
                "items": Schema.string("A note id"), "maxItems": .number(Double(maxNotes)),
            ])]),
            "required": ["ids"],
            "additionalProperties": false,
        ]),
        risk: .high, capabilities: [.macApps], category: .notes, mutates: true)

    func summary(for input: JSONValue) -> String {
        String(localized: "Move \((input.textList("ids") ?? []).count) notes in Apple Notes to Recently Deleted")
    }

    /// The approval lists every note by title, so the person sees exactly what leaves Notes.
    func scope(for input: JSONValue) -> ToolScope {
        let lines = (input.textList("ids") ?? []).prefix(Self.maxNotes).map { id -> String in
            guard let entry = ledger.cached(note: id) else { return id }
            return "“\(entry.title.clipped(80))” (\(entry.place.clipped(60)))"
        }
        let note = String(localized: "Their copies stay in your notebook. Notes keeps deleted notes in Recently Deleted for 30 days.")
        return ToolScope(text: lines.joined(separator: "\n") + "\n\n" + note)
    }

    func refusal(for input: JSONValue, context: ToolContext) -> String? {
        guard ledger.isLoaded else { return nil }   // `run` checks everything again either way
        let ids = input.textList("ids") ?? []
        guard ids.contains(where: { ledger.cached(note: $0) == nil }) else { return nil }
        return String(localized: "Only notes already copied into the notebook can be removed from Apple Notes. Copy them first.")
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let ids = try MacAppAccess.ids(input, max: Self.maxNotes)
        return try await MacAppAccess.run(.notes) {
            // Where each note is now, not where a list saw it a while ago.
            let index = try await notes.index(refresh: true)
            let copied = try await ledger.load()
            var kept: [String] = []
            var eligible: [NoteSummary] = []
            for id in ids {
                guard let note = index.note(id) else { kept.append("\(MacAppAccess.line(id, 40)): not found in Notes"); continue }
                let label = "\(note.handle) “\(MacAppAccess.line(note.title, 80))”"
                if let why = try await reasonToKeep(note, entry: copied[note.id], index: index) {
                    kept.append("\(label): \(why)")
                } else {
                    eligible.append(note)
                }
            }
            let outcome = try await notes.remove(eligible.map(\.id))
            var moved: [String] = [], removed: [String] = []
            for note in eligible {
                let label = "\(note.handle) “\(MacAppAccess.line(note.title, 80))”"
                switch outcome[note.id] {
                case .movedToRecentlyDeleted?: moved.append(label)
                case .removed?: removed.append(label)
                case .missing?, nil: kept.append("\(label): it was already gone")
                }
            }
            var lines: [String] = []
            if !moved.isEmpty { lines.append("Moved to Recently Deleted in Apple Notes:\n" + moved.map { "- " + $0 }.joined(separator: "\n")) }
            if !removed.isEmpty {
                lines.append("Removed from Apple Notes (Notes didn't report them in Recently Deleted; check there):\n"
                             + removed.map { "- " + $0 }.joined(separator: "\n"))
            }
            if !kept.isEmpty { lines.append("Left in Apple Notes:\n" + kept.map { "- " + $0 }.joined(separator: "\n")) }
            if moved.isEmpty, removed.isEmpty { lines.insert("Nothing was removed from Apple Notes.", at: 0) }
            let count = moved.count + removed.count
            return ToolResult(
                text: lines.joined(separator: "\n"),
                card: ResultCard(kind: .info, title: count == 0 ? String(localized: "Nothing removed from Apple Notes")
                                     : String(localized: "Moved \(count) notes to Recently Deleted in Apple Notes"),
                                 subtitle: String(localized: "Their copies are in your notebook"),
                                 detail: kept.isEmpty ? nil : String(localized: "\(kept.count) stayed in Notes")),
                untrusted: true)
        }
    }

    /// Why a note must stay in Notes, or nil when removing it loses nothing.
    private func reasonToKeep(_ note: NoteSummary, entry: AppleNotesLedger.Entry?, index: NotesIndex) async throws -> String? {
        guard let entry else { return "it hasn't been copied into the notebook" }
        guard let item = try await notebook.item(id: entry.itemId), item.deletedAt == nil else {
            return "its copy is no longer in the notebook"
        }
        if !entry.complete { return "its copy isn't complete (attachments or a long body are only in Notes)" }
        if note.locked { return "it is locked" }
        if index.isRecentlyDeleted(note) { return "it is already in Recently Deleted" }
        if !index.canMoveToRecentlyDeleted(note) { return "its account has no Recently Deleted folder, so it would be deleted for good" }
        if let then = entry.modified, let now = note.modified, abs(now.timeIntervalSince(then)) > 1 {
            return "it changed in Notes after it was copied; copy it again first"
        }
        return nil
    }
}
