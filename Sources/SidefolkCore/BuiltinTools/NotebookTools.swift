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

        // The time is read before anything is saved, so a time that can't be used changes nothing.
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
        let item = NotebookItem(
            collectionId: target.collection.id, kind: finalKind, title: title, body: body, url: url,
            tags: NoteText.cleanTags(input.textList("tags") ?? []), source: context.provenanceTag, now: context.now)
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
        let scheduler = reminders?.scheduler, reminderId = reminder?.id
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

    let spec = ToolSpec(
        name: "notes.list", title: String(localized: "List notes"),
        description: "List the newest notes, ideas, tasks and links, optionally for one collection, kind or status.",
        inputSchema: Schema.object([
            "collection": Schema.string("Only this project, topic or list"),
            "kind": kindSchema,
            "status": Schema.string("open or done (for tasks)", enum: ["open", "done"]),
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
        let items = try await notebook.items(collectionId: collectionId, kinds: kind.map { [$0] }, status: status, limit: limit)
        guard !items.isEmpty else {
            return ToolResult(text: "Nothing found \(scope).", card: ResultCard(kind: .list, title: String(localized: "Nothing here yet"), subtitle: shownScope),
                              untrusted: foreignScope)
        }
        let collections = try await NotebookCollections.byId(notebook)
        let reminders = await NoteFormat.reminders(items, notebook: notebook)
        return ToolResult(
            text: "\(ToolFormat.count(items.count, "item")) \(scope), newest first:\n"
                + items.map { NoteFormat.line($0, collections: collections, reminder: reminders[$0.id]) }.joined(separator: "\n"),
            card: ResultCard(kind: .list, title: String(localized: "\(items.count) items"), subtitle: shownScope),
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
            "remind": Schema.string("Add a reminder about it at this time (\"tomorrow at 9\"); it belongs to the item."),
        ], required: ["id"]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: true)

    func summary(for input: JSONValue) -> String {
        var changes: [String] = []
        if input["text"] != nil { changes.append(String(localized: "text")) }
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
        let previous = item
        // What changed, in English for the model and in the app's language for the card.
        var changed: [String] = []
        var shownChanged: [String] = []

        if input.string("text") != nil {
            let (title, body) = NoteText.split(try input.requiredText("text", limit: NoteText.maxText))
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
        let remindAt = try input.optionalText("remind", limit: 200)
        if let remindAt {
            guard let reminders else { throw UserFacingError("Reminders aren't running, so I can't set one.") }
            if item.kind == .task, item.status == .done {
                throw UserFacingError("“\(item.title.clipped(60))” is done, so it needs no reminder.", recovery: "Mark it open first.")
            }
            _ = try reminders.future(remindAt, now: context.now)
        }
        guard !changed.isEmpty || remindAt != nil else {
            throw ToolError.invalidInput(String(localized: "nothing to change. Give new text, a collection, a status, tags or a reminder."))
        }

        if !changed.isEmpty {
            item.updatedAt = context.now
            try await notebook.update(item)
        }
        var reminder: Reminder?
        if let remindAt, let reminders {
            do {
                reminder = try await reminders.remind(about: item, when: remindAt, context: context)
            } catch {
                if !changed.isEmpty { try? await notebook.update(previous) }
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
        let scheduler = reminders?.scheduler, reminderId = reminder?.id
        return ToolResult(
            text: message,
            card: ResultCard(kind: .note, title: changed.isEmpty ? NoteText.reminded : NoteText.updated(item.kind), subtitle: item.title.clipped(80),
                             detail: Wording.list(shownChanged), refId: item.id, itemKind: item.kind),
            undo: UndoAction(label: wordsChanged ? String(localized: "Restored “\(previous.title.clipped(40))”") : String(localized: "Cancel reminder")) {
                if let scheduler, let reminderId { _ = try await scheduler.cancel(id: reminderId) }
                guard wordsChanged else { return }
                // Put the words back, not the note itself: if it was moved to the Trash since, it stays there.
                var back = previous
                if let current = try await notebook.item(id: previous.id) { back.deletedAt = current.deletedAt }
                try await notebook.update(back)
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

struct CollectionsListTool: Tool {
    let notebook: NotebookStore

    let spec = ToolSpec(
        name: "collections.list", title: String(localized: "List collections"),
        description: "List the notebook's collections (Inbox, projects, topics, lists) with how many items each holds.",
        inputSchema: Schema.object([:]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: false)

    func summary(for input: JSONValue) -> String { String(localized: "List your notebook collections") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let collections = try await notebook.collections()
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

    func summary(for input: JSONValue) -> String { String(localized: "Create the collection “\((input.string("name") ?? "").clipped(60))”") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let name = try input.requiredText("name", limit: 60)
        var kind = NotebookCollection.Kind.project
        if let raw = input.string("kind") {
            guard let k = NotebookCollection.Kind(rawValue: raw.lowercased()), [.project, .topic, .list].contains(k) else {
                throw ToolError.invalidInput(String(localized: "“kind” must be project, topic or list."))
            }
            kind = k
        }
        if NotebookCollections.isProfileName(name) { throw NotebookCollections.profileRefusal }
        if name.lowercased() == NotebookStore.inboxName.lowercased() {
            // The Inbox always exists (it is made on first use); a look-alike second one is never wanted.
            let inbox = try await notebook.inbox(now: context.now)
            return ToolResult(text: "“\(inbox.name)” already exists.",
                              card: ResultCard(kind: .collection, title: NotebookCollections.shownName(inbox),
                                               subtitle: String(localized: "Already exists"), refId: inbox.id))
        }
        // Reuse only an exact (case-insensitive) match here; fuzzy matching is for filing notes.
        let existing = try await NotebookCollections.filable(notebook).first { $0.name.lowercased() == name.lowercased() }
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
