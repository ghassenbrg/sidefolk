import Foundation

// The notebook tools: save, find, list, change and trash notes, plus collections.
// Nothing here is destructive: "trash" moves to the Trash (kept 30 days) and every change can be undone.

private let kindSchema = Schema.string("note, idea, task or link", enum: NotebookItem.Kind.allCases.map(\.rawValue))

struct NotesSaveTool: Tool {
    let notebook: NotebookStore
    let events: EventBus
    /// Gives what is saved its reminder (`remind`, D49); nil where no scheduler runs.
    var reminders: ReminderTools.Shared?

    let spec = ToolSpec(
        name: "notes.save", title: String(localized: "Save to notebook"),
        description: """
            Save a note, idea, task or link in the user's notebook. The first line of `text` becomes the title and the \
            rest the body. Saves to the Inbox unless `collection` names a project or topic (it is created if it \
            doesn't exist; `collection_kind` says what it is then). Use this when the user asks to remember, save, jot down or capture something. \
            The body may use simple Markdown (**bold**, *italic*, `## headings`, `- ` lists, `- [ ] ` checklists, links); \
            the notebook shows it formatted.
            """,
        inputSchema: Schema.object([
            "text": Schema.string("What to save. First line = title, the rest = body."),
            "kind": kindSchema,
            "collection": Schema.string("Project, topic or list to file it in, e.g. “Sidefolk”. Defaults to the Inbox."),
            "collection_kind": Schema.string("Only when `collection` has to be created: project (default), topic or list (shopping and to-do lists).",
                                             enum: ["project", "topic", "list"]),
            "url": Schema.string("A web link this note is about (http or https)."),
            "tags": Schema.array("Short labels", items: Schema.string("One word or hyphenated phrase")),
            "due": Schema.string("For a task: when it's due (\"friday\", \"dec 5 at 5pm\"). It stands on the Calendar; it nudges nobody, that's `remind`."),
            "remind": Schema.string("Also remind the user about it at this time (\"tomorrow at 9\", \"friday 5pm\"): the reminder belongs to it and stops when the task is done or the item trashed."),
        ], required: ["text"]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: true, external: true)

    func summary(for input: JSONValue) -> String {
        let title = NoteText.split(input.string("text") ?? "").title
        return String(localized: "Save “\(title.clipped(60))” to \(input.string("collection") ?? String(localized: "Inbox"))")
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let text = try input.requiredText("text", limit: NoteText.maxText)
        var kind = try NoteText.parseKind(input.string("kind"))
        var url = try input.optionalText("url", limit: 2_048)
        if let u = url, NoteText.httpURL(u) == nil {
            throw UserFacingError("I can only attach web links (http or https) to a note.")
        }
        var (title, body) = NoteText.split(text)

        if kind == nil {
            if let single = NoteText.singleURL(in: text) {
                kind = .link
                url = url ?? single.absoluteString
                title = NoteText.displayTitle(for: single)
                body = ""
            } else {
                kind = .note
            }
        }
        if kind == .link, url == nil { url = NoteText.firstURL(in: text)?.absoluteString }

        // The times are read before anything is saved, so one that can't be used changes nothing.
        let due = try NoteDue.read(input["due"]?.stringValue, parser: reminders?.parser() ?? WhenParser(), now: context.now)
        try NoteDue.check(due, kind: kind ?? .note)
        let remindAt = try input.optionalText("remind", limit: 200)
        if let remindAt {
            guard let reminders else { throw UserFacingError("Reminders aren't running, so I can't set one.") }
            _ = try reminders.future(remindAt, now: context.now)
        }

        let target: (collection: NotebookCollection, created: Bool)
        if let name = input.string("collection") {
            target = try await NotebookCollections.resolveOrCreate(name, kind: try NotebookCollections.newKind(input["collection_kind"]),
                                                                   notebook: notebook, context: context)
        } else {
            target = (try await notebook.inbox(now: context.now), false)
        }
        let finalKind = kind ?? .note
        var item = NotebookItem(
            collectionId: target.collection.id, kind: finalKind, title: title, body: body, url: url,
            tags: NoteText.cleanTags(input.textList("tags") ?? []), source: context.provenanceTag, runId: context.caller.runId,
            now: context.now)
        _ = NoteDue.apply(due, to: &item)
        try await notebook.add(item)
        var reminder: Reminder?
        if let remindAt, let reminders {
            do {
                reminder = try await reminders.remind(about: item, when: remindAt, context: context)
            } catch {
                // Saved and reminded, or neither.
                try? await notebook.purge(itemId: item.id)
                throw error
            }
        }
        events.changed(.notebook)

        let where_ = "\(NotebookCollections.shownName(target.collection)) › \(NoteText.plural(finalKind))"
        var message = "Saved \(finalKind.rawValue) “\(title.clipped(80))” to \(target.collection.name) (id \(item.id))."
        // Said, so a caller doesn't set it again or tell the person something else.
        if case .set(let date, let allDay)? = due {
            let calendar = reminders?.calendar ?? .autoupdatingCurrent
            message += " Due \(allDay ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()) : TimeFormat.full(date, calendar: calendar))."
        }
        var details: [String] = []
        if target.created {
            message += " “\(target.collection.name)” didn't exist, so I created it as a new \(target.collection.kind.rawValue)."
            details.append(NotebookCollections.createdNote(target.collection))
        }
        if let reminder, let reminders {
            message += " Reminder set for \(TimeFormat.full(reminder.fireAt, calendar: reminders.calendar)) (reminder \(reminder.id))."
            details.append(reminders.cardLine(reminder, now: context.now))
        }
        let notebook = self.notebook, events = self.events, id = item.id
        let scheduler = reminders?.scheduler, reminderId = reminder?.id, after = item
        return ToolResult(
            text: message,
            card: ResultCard(kind: .note, title: String(localized: "Saved to \(where_)"), subtitle: title.clipped(80),
                             detail: details.isEmpty ? nil : details.joined(separator: "\n"), refId: id, url: url, itemKind: finalKind),
            undo: UndoAction(label: String(localized: "Removed “\(title.clipped(40))”")) {
                _ = try await notebook.trash(itemId: id)
                if let scheduler, let reminderId { _ = try await scheduler.cancel(id: reminderId) }
                events.changed(.notebook)
            },
            // A partial name may have matched a collection someone else named; the reply quotes it.
            untrusted: NotebookCollections.isForeign(target.collection))
    }
}

struct NotesSearchTool: Tool {
    let notebook: NotebookStore

    let spec = ToolSpec(
        name: "notes.search", title: String(localized: "Search notebook"),
        description: """
            Full-text search over the user's notes, ideas, tasks and links. Returns ids, titles, collections and \
            short snippets, best matches first. Use it to answer "what did I save about …".
            """,
        inputSchema: Schema.object([
            "query": Schema.string("Words to look for"),
            "collection": Schema.string("Only look in this project, topic or list"),
            "kind": kindSchema,
            "limit": Schema.integer("Maximum results (default 10)", minimum: 1, maximum: 25),
        ], required: ["query"]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: false, external: true)

    func summary(for input: JSONValue) -> String {
        let query = (input.string("query") ?? "").clipped(60)
        if let c = input.string("collection") { return String(localized: "Search your notes for “\(query)” in \(c)") }
        return String(localized: "Search your notes for “\(query)”")
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let query = try input.requiredText("query", limit: 300)
        let kind = try NoteText.parseKind(input.string("kind"))
        let limit = input.clampedInt("limit", default: 10, in: 1...25)
        var collectionId: String?
        if let name = input.string("collection") {
            guard let c = try await NotebookCollections.resolve(name, notebook: notebook) else {
                throw ToolError.notFound(String(localized: "a collection called “\(name)”"))
            }
            collectionId = c.id
        }
        let items = try await notebook.search(query, collectionId: collectionId, kinds: kind.map { [$0] }, limit: limit)
        guard !items.isEmpty else {
            return ToolResult(text: "No notes matched “\(query.clipped(60))”.",
                              card: ResultCard(kind: .list, title: String(localized: "No matching notes"), subtitle: query.clipped(60)))
        }
        let collections = try await NotebookCollections.byId(notebook)
        let reminders = await NoteFormat.reminders(items, notebook: notebook)
        let body = items.map { NoteFormat.line($0, collections: collections, reminder: reminders[$0.id]) }.joined(separator: "\n")
        return ToolResult(
            text: "\(ToolFormat.count(items.count, "note")) matched “\(query.clipped(60))”:\n\(body)",
            card: ResultCard(kind: .list, title: String(localized: "\(items.count) matches for “\(query.clipped(40))”"),
                             subtitle: items.prefix(3).map { $0.title.clipped(30) }.joined(separator: " · ")),
            untrusted: NoteFormat.hasForeign(items, collections: collections))
    }
}

struct NotesListTool: Tool {
    let notebook: NotebookStore
    /// Reads a due date as the person's calendar and day-part hours do.
    var reminders: ReminderTools.Shared?

    let spec = ToolSpec(
        name: "notes.list", title: String(localized: "List notes"),
        description: "List the newest notes, ideas, tasks and links, optionally for one collection, kind or status. With due_before or due_after, only what's due then, soonest first.",
        inputSchema: Schema.object([
            "collection": Schema.string("Only this project, topic or list"),
            "kind": kindSchema,
            "status": Schema.string("open or done (for tasks)", enum: ["open", "done"]),
            "due_after": Schema.string("Only what's due from then on (\"today\", \"dec 5\" or ISO 8601). A day means from its start."),
            "due_before": Schema.string("Only what's due up to then (\"friday\", \"dec 5\" or ISO 8601). A day counts in full."),
            "limit": Schema.integer("Maximum items (default 20)", minimum: 1, maximum: 50),
        ]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: false)

    func summary(for input: JSONValue) -> String {
        if let c = input.string("collection") { return String(localized: "List what's in \(c)") }
        return String(localized: "List your newest notes")
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let kind = try NoteText.parseKind(input.string("kind"))
        let limit = input.clampedInt("limit", default: 20, in: 1...50)
        var status: NotebookItem.Status?
        if let raw = input.string("status") {
            guard let s = NotebookItem.Status(rawValue: raw.lowercased()) else {
                throw ToolError.invalidInput(String(localized: "“status” must be open or done."))
            }
            status = s
        }
        var collectionId: String?
        var scope = "everywhere"
        var shownScope = String(localized: "everywhere")
        // The scope quotes the collection's own name, which a partial name may have matched.
        var foreignScope = false
        if let name = input.string("collection") {
            // Reading "About you" is fine here; only filing into it is refused.
            let found = NotebookCollections.isProfileName(name)
                ? try await NotebookCollections.profile(notebook, create: false)
                : try await NotebookCollections.resolve(name, notebook: notebook)
            guard let c = found else { throw ToolError.notFound(String(localized: "a collection called “\(name)”")) }
            collectionId = c.id
            scope = "in \(c.name)"
            shownScope = String(localized: "in \(NotebookCollections.shownName(c))")
            foreignScope = NotebookCollections.isForeign(c)
        }
        let due = try DateWindow.read(from: input.string("due_after"), to: input.string("due_before"), parser: reminders?.parser() ?? WhenParser(), now: context.now)
        let items = try await notebook.items(collectionId: collectionId, kinds: kind.map { [$0] }, status: status,
                                             dueFrom: due?.start, dueBefore: due?.end, limit: limit)
        guard !items.isEmpty else {
            return ToolResult(text: "Nothing found \(scope).", card: ResultCard(kind: .list, title: String(localized: "Nothing here yet"), subtitle: shownScope),
                              untrusted: foreignScope)
        }
        let collections = try await NotebookCollections.byId(notebook)
        let reminders = await NoteFormat.reminders(items, notebook: notebook)
        return ToolResult(
            text: "\(ToolFormat.count(items.count, "item")) \(scope), \(due == nil ? "newest" : "soonest due") first:\n"
                + items.map { NoteFormat.line($0, collections: collections, reminder: reminders[$0.id]) }.joined(separator: "\n"),
            // A window is asked of the person's own words too, so its card says what's in it.
            card: ResultCard(kind: .list, title: String(localized: "\(items.count) items"), subtitle: shownScope,
                             detail: due == nil ? nil : items.prefix(8).map { item in
                                 (item.dueAt.map { TimeFormat.day($0, now: context.now, calendar: .autoupdatingCurrent) + " " } ?? "") + item.title.clipped(60)
                             }.joined(separator: "\n")),
            untrusted: foreignScope || NoteFormat.hasForeign(items, collections: collections))
    }
}

struct NotesUpdateTool: Tool {
    let notebook: NotebookStore
    let events: EventBus
    /// Gives the item a reminder (`remind`, D49); nil where no scheduler runs.
    var reminders: ReminderTools.Shared?

    let spec = ToolSpec(
        name: "notes.update", title: String(localized: "Change a note"),
        description: """
            Change an existing note by id: replace its text (first line = title), move it to another collection, \
            mark a task open or done, replace its tags, or give it a reminder. Find ids with notes.search or notes.list. \
            Marking a task done ends its reminders.
            """,
        inputSchema: Schema.object([
            "id": Schema.string("The note's id"),
            "text": Schema.string("New text; the first line becomes the title"),
            "collection": Schema.string("Move it to this project, topic or list (created if missing)"),
            "status": Schema.string("open or done", enum: ["open", "done"]),
            "tags": Schema.array("Replaces the tags; an empty list clears them", items: Schema.string("A tag")),
            "append": Schema.string("Words to add at the end, leaving what's there. Instead of `text`."),
            "due": Schema.string("For a task: when it's due (\"friday\", \"dec 5 at 5pm\"); empty clears it. Not a reminder: it nudges nobody."),
            "remind": Schema.string("Add a reminder about it at this time (\"tomorrow at 9\"); it belongs to the item."),
        ], required: ["id"]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: true)

    func summary(for input: JSONValue) -> String {
        var changes: [String] = []
        if input["text"] != nil || input["append"] != nil { changes.append(String(localized: "text")) }
        if input["due"] != nil { changes.append(String(localized: "due date")) }
        if let c = input.string("collection") { changes.append(String(localized: "move to \(c)")) }
        if let s = input.string("status") { changes.append(Self.mark(s)) }
        if input["tags"] != nil { changes.append(String(localized: "tags")) }
        if let when = input.string("remind") { changes.append(String(localized: "remind you \(when.clipped(40))")) }
        return String(localized: "Change a note (\(changes.isEmpty ? String(localized: "nothing") : Wording.list(changes)))")
    }

    private static func mark(_ status: String) -> String {
        switch NotebookItem.Status(rawValue: status.lowercased()) {
        case .done: String(localized: "mark done")
        case .open: String(localized: "mark open")
        case nil: String(localized: "mark \(status)")
        }
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let id = try input.requiredText("id", limit: 64)
        guard var item = try await notebook.item(id: id) else { throw ToolError.notFound(String(localized: "a note with that id")) }
        guard item.deletedAt == nil else {
            throw UserFacingError("That note is in the Trash, so I left it alone.", recovery: "Restore it from the Trash first.")
        }
        if try await NotebookCollections.isProfile(collectionId: item.collectionId, notebook: notebook) {
            throw UserFacingError("That's a fact in “About you”. Use the profile tools to change it.")
        }
        // Marking it done would end its reminders: another agent can't end an important one this way either, card or no card (T24).
        if case .external = context.caller, item.kind == .task, item.status != .done, input.string("status")?.lowercased() == "done",
           await notebook.holdsAnImportantReminder(itemId: id) {
            throw ReminderTools.Shared.importantOneHoldsIt
        }
        let previous = item
        let due = try NoteDue.read(input["due"]?.stringValue, parser: reminders?.parser() ?? WhenParser(), now: context.now)
        try NoteDue.check(due, kind: item.kind)
        // What changed, in English for the model and in the app's language for the card.
        var changed: [String] = []
        var shownChanged: [String] = []

        // Adding to a note, without having to send back all of it (D117). Words from elsewhere make it elsewhere's; a
        // note already from elsewhere never becomes the person's by being added to.
        if let more = try input.optionalText("append", limit: NoteText.maxText) {
            guard input.string("text") == nil else { throw ToolError.invalidInput(String(localized: "give “text” or “append”, not both.")) }
            guard item.body.count + more.count + 2 <= NoteText.maxText else {
                throw UserFacingError("That would make the note too long. Start a new one instead.")
            }
            item.body = item.body.isEmpty ? more : item.body + "\n\n" + more
            if !ItemProvenance.isForeign(item.source) { item.source = context.provenanceTag }
            changed.append("text")
            shownChanged.append(String(localized: "text"))
        }
        if input.string("text") != nil {
            let (title, body) = NoteText.split(try input.requiredText("text", limit: NoteText.maxText))
            // A reminder carrying the note's title follows a rename (D49): that would reword an important one (T24).
            if case .external = context.caller, title != item.title, await notebook.hasAnImportantReminder(itemId: id) {
                throw UserFacingError(verbatim: "That note has a reminder the user marked important, so only they can change its title, in Sidefolk. You can change the rest with append, or ask them to.")
            }
            item.title = title
            item.body = body
            // Whoever last wrote the words is who they are attributed to, but an outsider's note never becomes
            // trusted just because Sidefolk's own agent edited it.
            if !(ItemProvenance.isForeign(item.source) && context.caller != .user) { item.source = context.provenanceTag }
            changed.append("text")
            shownChanged.append(String(localized: "text"))
        }
        var movedTo: (collection: NotebookCollection, created: Bool)?
        if let name = input.string("collection") {
            let target = try await NotebookCollections.resolveOrCreate(name, notebook: notebook, context: context)
            if target.collection.id != item.collectionId {
                item.collectionId = target.collection.id
                movedTo = target
                changed.append("moved to \(target.collection.name)")
                shownChanged.append(String(localized: "moved to \(NotebookCollections.shownName(target.collection))"))
            }
        }
        if let raw = input.string("status") {
            guard let status = NotebookItem.Status(rawValue: raw.lowercased()) else {
                throw ToolError.invalidInput(String(localized: "“status” must be open or done."))
            }
            if status != item.status {
                changed.append("marked \(status.rawValue)")
                shownChanged.append(status == .done ? String(localized: "marked done") : String(localized: "marked open"))
            }
            item.status = status
        }
        if let tags = input.textList("tags") {
            item.tags = NoteText.cleanTags(tags).joined(separator: " ")
            changed.append("tags")
            shownChanged.append(String(localized: "tags"))
        }
        if NoteDue.apply(due, to: &item) {
            changed.append("due date")
            shownChanged.append(String(localized: "due date"))
        }
        let remindAt = try input.optionalText("remind", limit: 200)
        if let remindAt {
            guard let reminders else { throw UserFacingError("Reminders aren't running, so I can't set one.") }
            if item.kind == .task, item.status == .done {
                throw UserFacingError("“\(item.title.clipped(60))” is done, so it needs no reminder.", recovery: "Mark it open first.")
            }
            _ = try reminders.future(remindAt, now: context.now)
        }
        guard !changed.isEmpty || remindAt != nil else {
            throw ToolError.invalidInput(String(localized: "nothing to change. Give new text, words to append, a due date, a collection, a status, tags or a reminder."))
        }

        if !changed.isEmpty {
            // Over the note as it is stored now: the person may be typing in it, and their words stay (the Notebook's
            // draft saves by the same rule), so only what this changed is written.
            guard let saved = try await notebook.save(item, from: previous, now: context.now) else {
                throw UserFacingError("That note went to the Trash while I was changing it, so I left it alone.", recovery: "Restore it from the Trash first.")
            }
            item = saved
        }
        var reminder: Reminder?
        if let remindAt, let reminders {
            do {
                reminder = try await reminders.remind(about: item, when: remindAt, context: context)
            } catch {
                if !changed.isEmpty { _ = try? await notebook.save(previous, from: item, now: context.now) }
                throw error
            }
            shownChanged.append(reminders.cardLine(reminder!, now: context.now))
        }
        events.changed(.notebook)

        var message = changed.isEmpty ? "“\(item.title.clipped(80))”:" : "Updated “\(item.title.clipped(80))”: \(changed.joined(separator: ", "))."
        if movedTo?.created == true { message += " Created the new project “\(movedTo!.collection.name)”." }
        if let reminder, let reminders {
            message += " Reminder set for \(TimeFormat.full(reminder.fireAt, calendar: reminders.calendar)) (reminder \(reminder.id))."
        }
        let notebook = self.notebook, events = self.events, wordsChanged = !changed.isEmpty
        let scheduler = reminders?.scheduler, reminderId = reminder?.id, after = item
        return ToolResult(
            text: message,
            card: ResultCard(kind: .note, title: changed.isEmpty ? NoteText.reminded : NoteText.updated(item.kind), subtitle: item.title.clipped(80),
                             detail: Wording.list(shownChanged), refId: item.id, itemKind: item.kind),
            undo: UndoAction(label: wordsChanged ? String(localized: "Restored “\(previous.title.clipped(40))”") : String(localized: "Cancel reminder")) {
                if let scheduler, let reminderId { _ = try await scheduler.cancel(id: reminderId) }
                guard wordsChanged else { return }
                // Put back what this changed, not the note itself: later edits stay, and if it was moved to the Trash
                // since, it stays there.
                _ = try await notebook.save(previous, from: after, inTheTrash: true)
                events.changed(.notebook)
            },
            untrusted: movedTo.map { NotebookCollections.isForeign($0.collection) } == true)
    }
}

struct NotesTrashTool: Tool {
    let notebook: NotebookStore
    let events: EventBus

    let spec = ToolSpec(
        name: "notes.trash", title: String(localized: "Move a note to the Trash"),
        description: "Move a note to the Trash by id. It stays restorable for 30 days.",
        inputSchema: Schema.object(["id": Schema.string("The note's id")], required: ["id"]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: true)

    func summary(for input: JSONValue) -> String { String(localized: "Move a note to the Trash") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let id = try input.requiredText("id", limit: 64)
        guard let item = try await notebook.item(id: id) else { throw ToolError.notFound(String(localized: "a note with that id")) }
        guard item.deletedAt == nil else { throw UserFacingError("That note is already in the Trash.") }
        if try await NotebookCollections.isProfile(collectionId: item.collectionId, notebook: notebook) {
            throw UserFacingError("That's a fact in “About you”. Use “forget” to remove it.")
        }
        // Trashing it would end its reminders (T24), as marking it done would.
        if case .external = context.caller, await notebook.holdsAnImportantReminder(itemId: id) {
            throw UserFacingError(verbatim: "That note has a reminder the user marked important, so only they can move it to the Trash, in Sidefolk. You can ask them to.")
        }
        _ = try await notebook.trash(itemId: id, now: context.now)
        events.changed(.notebook)
        let notebook = self.notebook, events = self.events
        return ToolResult(
            text: "Moved “\(item.title.clipped(80))” to the Trash. It can be restored for 30 days.",
            card: ResultCard(kind: .note, title: String(localized: "Moved to Trash"), subtitle: item.title.clipped(80), refId: id, itemKind: item.kind),
            undo: UndoAction(label: String(localized: "Restored “\(item.title.clipped(40))”")) {
                try await notebook.restore(itemId: id)
                events.changed(.notebook)
            })
    }
}

/// Brings a note back from the Trash by id: how a mistaken `notes.trash` is undone later. There's no listing of the
/// Trash here: an agent restores what it already knows, and only the person sees what's in there.
struct NotesRestoreTool: Tool {
    let notebook: NotebookStore
    let events: EventBus

    let spec = ToolSpec(
        name: "notes.restore", title: String(localized: "Restore a note"),
        description: "Bring a note back from the Trash by id, where it was. Waiting reminders still ahead come back with it.",
        inputSchema: Schema.object(["id": Schema.string("The note's id")], required: ["id"]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: true)

    func summary(for input: JSONValue) -> String { String(localized: "Restore a note") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let id = try input.requiredText("id", limit: 64)
        guard let item = try await notebook.item(id: id) else { throw ToolError.notFound(String(localized: "a note with that id")) }
        guard item.deletedAt != nil else { throw UserFacingError("That note isn't in the Trash.") }
        if try await NotebookCollections.isProfile(collectionId: item.collectionId, notebook: notebook) {
            throw UserFacingError("That's a fact in “About you”. It can be restored from the Trash in Sidefolk.")
        }
        try await notebook.restore(itemId: id, now: context.now)
        events.changed(.notebook)
        let notebook = self.notebook, events = self.events
        return ToolResult(
            text: "Restored “\(item.title.clipped(80))” (id \(id)).",
            card: ResultCard(kind: .note, title: String(localized: "Restored"), subtitle: item.title.clipped(80), refId: id, itemKind: item.kind),
            undo: UndoAction(label: String(localized: "Moved to Trash")) {
                _ = try await notebook.trash(itemId: id)
                events.changed(.notebook)
            },
            untrusted: !ContextBuilder.isUserSourced(item.source))
    }
}

struct CollectionsListTool: Tool {
    let notebook: NotebookStore

    let spec = ToolSpec(
        name: "collections.list", title: String(localized: "List collections"),
        description: "List the notebook's collections (Inbox, projects, topics, lists) with how many items each holds.",
        inputSchema: Schema.object([:]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: false)

    func summary(for input: JSONValue) -> String { String(localized: "List your notebook collections") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        var collections = try await notebook.collections()
        // What's known about the person isn't another agent's to size up (T4).
        switch context.caller {
        case .external, .extension: collections.removeAll { $0.kind == .profile }
        case .user, .agent, .routine, .command: break
        }
        let counts = try await NotebookCollections.itemCounts(notebook)
        guard !collections.isEmpty else {
            return ToolResult(text: "The notebook has no collections yet. Notes go to the Inbox.",
                              card: ResultCard(kind: .collection, title: String(localized: "No collections yet")))
        }
        let lines = collections.map { c in
            var meta = [c.kind == .profile ? "about you" : c.kind.rawValue, ToolFormat.count(counts[c.id] ?? 0, "item")]
            if let origin = ItemProvenance.note(for: c.source) { meta.append(origin) }
            return "\(ToolFormat.oneLine(ExternalText.clean(c.name), 60)) (\(meta.joined(separator: ", ")))"
        }
        // A name someone else chose is their words, not the user's (SECURITY T2, T3).
        return ToolResult(text: "Collections:\n" + lines.map { "- " + $0 }.joined(separator: "\n"),
                          card: ResultCard(kind: .collection, title: String(localized: "\(collections.count) collections"),
                                           subtitle: collections.prefix(4).map(NotebookCollections.shownName).joined(separator: " · ")),
                          untrusted: collections.contains(where: NotebookCollections.isForeign))
    }
}

struct CollectionsCreateTool: Tool {
    let notebook: NotebookStore
    let events: EventBus

    let spec = ToolSpec(
        name: "collections.create", title: String(localized: "Create a collection"),
        description: "Create a project, topic or list to file notes in. If one with that name exists it is reused.",
        inputSchema: Schema.object([
            "name": Schema.string("Name, e.g. “Sidefolk” or “Reading list”"),
            "kind": Schema.string("project, topic or list (default project)", enum: ["project", "topic", "list"]),
        ], required: ["name"]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: true)

    func summary(for input: JSONValue) -> String { String(localized: "Create the collection “\(NotebookCollections.cleanName(input.string("name") ?? ""))”") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        // As the card showed it: no line breaks, nothing unseen.
        let name = NotebookCollections.cleanName(try input.requiredText("name", limit: 200))
        guard !name.isEmpty else { throw ToolError.invalidInput(String(localized: "a collection needs a name.")) }
        var kind = NotebookCollection.Kind.project
        if let raw = input.string("kind") {
            guard let k = NotebookCollection.Kind(rawValue: raw.lowercased()), [.project, .topic, .list].contains(k) else {
                throw ToolError.invalidInput(String(localized: "“kind” must be project, topic or list."))
            }
            kind = k
        }
        if NotebookCollections.looksLikeProfile(name) { throw NotebookCollections.profileRefusal }
        if NotebookCollections.looksLikeInbox(name) {
            // The Inbox always exists (it is made on first use); a look-alike second one is never wanted.
            let inbox = try await notebook.inbox(now: context.now)
            return ToolResult(text: "“\(inbox.name)” already exists.",
                              card: ResultCard(kind: .collection, title: NotebookCollections.shownName(inbox),
                                               subtitle: String(localized: "Already exists"), refId: inbox.id))
        }
        // Reuse only an exact (case-insensitive) match here; fuzzy matching is for filing notes.
        let existing = try await NotebookCollections.filable(notebook).first { NotebookCollections.asItReads($0.name) == NotebookCollections.asItReads(name) }
        if let existing {
            return ToolResult(text: "“\(existing.name)” already exists.",
                              card: ResultCard(kind: .collection, title: existing.name, subtitle: String(localized: "Already exists"), refId: existing.id))
        }
        let created = try await NotebookCollections.create(name, kind: kind, notebook: notebook, context: context)
        events.changed(.notebook)
        let notebook = self.notebook, events = self.events, id = created.id
        return ToolResult(
            text: "Created the \(kind.rawValue) “\(created.name)”.",
            card: ResultCard(kind: .collection, title: created.name, subtitle: NotebookCollections.newLabel(kind), refId: id),
            undo: UndoAction(label: String(localized: "Removed “\(created.name.clipped(40))”")) {
                // Never cascade-delete notes that were filed here since.
                guard try await NotebookCollections.totalItemCount(collectionId: id, notebook: notebook) == 0 else {
                    throw UserFacingError("“\(created.name)” has notes in it now, so I left it.")
                }
                try await notebook.deleteCollection(id: id)
                events.changed(.notebook)
            })
    }
}

/// A note in full, words and all: the lists cut each to a line, so without this nothing can read what the person wrote.
struct NotesGetTool: Tool {
    let notebook: NotebookStore

    var spec: ToolSpec {
        ToolSpec(name: "notes.get", title: String(localized: "Read a note"),
                 description: "Read one note, idea, task or link in full by its id, from notes_search or notes_list. Those cut each to a line; this has all of it.",
                 inputSchema: Schema.object(["id": Schema.string("The item's id.")], required: ["id"]),
                 risk: .low, capabilities: [.notebook], category: .notes, mutates: false, external: true)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Read a note") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let id = try input.requiredText("id", limit: 64)
        guard let item = try await notebook.item(id: id), item.deletedAt == nil else {
            throw ToolError.notFound(String(localized: "a note with that id"))
        }
        let collections = try await NotebookCollections.byId(notebook)
        let reminders = await NoteFormat.reminders([item], notebook: notebook)
        let head = NoteFormat.line(item, collections: collections, snippet: false, reminder: reminders[item.id])
        let body = ExternalText.clean(item.body)
        return ToolResult(text: body.isEmpty ? head : "\(head)\n\n\(body)",
                          card: ResultCard(kind: .note, title: item.title, refId: item.id, itemKind: item.kind),
                          untrusted: NoteFormat.hasForeign([item], collections: collections))
    }
}

/// Changes a collection itself: its name, icon and colour, as its sheet in Home does (D117).
struct NotesCollectionTool: Tool {
    let notebook: NotebookStore
    let events: EventBus

    var spec: ToolSpec {
        ToolSpec(name: "notes.collection", title: String(localized: "Change a collection"),
                 description: """
                 Change a project, topic or list: its name, its icon (emoji, or symbol, an SF Symbol from the app's set) and its \
                 color (red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray, or #RRGGBB). An empty \
                 emoji, symbol or color goes back to the default. The Inbox and About you keep their names.
                 """,
                 inputSchema: Schema.object([
                     "collection": Schema.string("Which one, by name."),
                     "name": Schema.string("Its new name."),
                     "emoji": Schema.string("An emoji for its icon."),
                     "symbol": Schema.string("An SF Symbol for its icon, like \"star.fill\"."),
                     "color": Schema.string("A color name or #RRGGBB."),
                 ], required: ["collection"]),
                 risk: .low, capabilities: [.notebook], category: .notes, mutates: true, external: true)
    }

    func summary(for input: JSONValue) -> String {
        let which = NotebookCollections.cleanName(input.string("collection") ?? "")
        // The card has to say what a new name is: a yes to it is the only thing between an agent and a name beside the person's own.
        if let name = input.string("name").map({ NotebookCollections.cleanName($0) }), !name.isEmpty { return String(localized: "Rename “\(which)” to “\(name)”") }
        return String(localized: "Change “\(which)”")
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let wanted = try input.requiredText("collection", limit: 100)
        guard let found = try await NotebookCollections.resolve(wanted, notebook: notebook) else {
            throw ToolError.notFound(String(localized: "a collection called “\(wanted)”"))
        }
        var c = found
        if let name = input.string("name")?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            guard c.kind != .inbox, c.kind != .profile else { throw UserFacingError("The Inbox and About you keep their names.") }
            let clean = NotebookCollections.cleanName(name)
            guard !clean.isEmpty, !NotebookCollections.looksLikeProfile(clean), !NotebookCollections.looksLikeInbox(clean) else {
                throw UserFacingError("That name is taken by the notebook's own: choose another.")
            }
            if try await NotebookCollections.twin(of: clean, excluding: c.id, notebook: notebook) != nil {
                throw UserFacingError("There's already a collection called “\(clean)”.")
            }
            c.name = clean
            // A name is quoted to the model as the user's own only when it is (T3).
            c.source = context.provenanceTag
        }
        if let emoji = input["emoji"]?.stringValue {
            let clean = CollectionLooks.emoji(emoji)
            guard clean != nil || emoji.isEmpty else { throw ToolError.invalidInput(String(localized: "“emoji” must be one emoji.")) }
            c.emoji = clean
            if clean != nil { c.symbol = nil }
        }
        if let symbol = input["symbol"]?.stringValue {
            guard symbol.isEmpty || CollectionLooks.symbols.contains(symbol) else {
                throw ToolError.invalidInput(String(localized: "“\(symbol.clipped(40))” isn't one of the icons."))
            }
            c.symbol = symbol.isEmpty ? nil : symbol
            if !symbol.isEmpty { c.emoji = nil }
        }
        if let color = input["color"]?.stringValue {
            guard color.isEmpty || CollectionLooks.isColor(color) else {
                throw ToolError.invalidInput(String(localized: "“color” must be a color's name or #RRGGBB."))
            }
            c.color = color.isEmpty ? nil : color.lowercased()
        }
        guard c != found else { throw ToolError.invalidInput(String(localized: "nothing to change. Give a name, an emoji, a symbol or a color.")) }
        c.updatedAt = context.now
        try await notebook.updateCollection(c)
        events.changed(.notebook)
        let notebook = self.notebook
        let events = self.events
        return ToolResult(text: "Changed the collection “\(c.name)”.", card: ResultCard(kind: .list, title: String(localized: "Changed “\(NotebookCollections.shownName(c))”")),
                          undo: UndoAction(label: String(localized: "Changed it back")) {
                              try await notebook.restoreLook(of: found)
                              events.changed(.notebook)
                          },
                          untrusted: NotebookCollections.isForeign(found))
    }
}

/// Puts collections in an order (D117).
struct NotesArrangeTool: Tool {
    let notebook: NotebookStore
    let events: EventBus

    var spec: ToolSpec {
        ToolSpec(name: "notes.arrange", title: String(localized: "Arrange collections"),
                 description: "Put projects, topics and lists in this order in the sidebar, each by name. The Inbox stays first, and any not named follow.",
                 inputSchema: Schema.object(["collections": .object(["type": "array", "items": ["type": "string"], "description": "Names in the new order."])], required: ["collections"]),
                 risk: .low, capabilities: [.notebook], category: .notes, mutates: true, external: true)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Arrange your collections") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let names = input.textList("collections") ?? []
        guard !names.isEmpty else { throw ToolError.invalidInput(String(localized: "“collections” must list them in their new order.")) }
        var ids: [String] = []
        for name in names {
            guard let c = try await NotebookCollections.resolve(name, notebook: notebook) else {
                throw ToolError.notFound(String(localized: "a collection called “\(name)”"))
            }
            ids.append(c.id)
        }
        let before = try await notebook.collections(includeArchived: true)
        try await notebook.arrangeCollections(ids, now: context.now)
        events.changed(.notebook)
        let notebook = self.notebook
        let events = self.events
        return ToolResult(text: "Arranged \(ids.count) collections.", card: ResultCard(kind: .list, title: String(localized: "Arranged your collections")),
                          undo: UndoAction(label: String(localized: "Put them back")) {
                              try await notebook.restoreOrder(of: before)
                              events.changed(.notebook)
                          })
    }
}
