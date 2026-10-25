import Foundation

// The notebook tools: save, find, list, change and trash notes, plus collections.
// Nothing here is destructive: "trash" moves to the Trash (kept 30 days) and every change can be undone.

private let kindSchema = Schema.string("note, idea, task or link", enum: NotebookItem.Kind.allCases.map(\.rawValue))

struct NotesSaveTool: Tool {
    let notebook: NotebookStore
    let events: EventBus

    let spec = ToolSpec(
        name: "notes.save", title: "Save to notebook",
        description: """
            Save a note, idea, task or link in the user's notebook. The first line of `text` becomes the title and the \
            rest the body. Saves to the Inbox unless `collection` names a project or topic (it is created if it \
            doesn't exist). Use this when the user asks to remember, save, jot down or capture something.
            """,
        inputSchema: Schema.object([
            "text": Schema.string("What to save. First line = title, the rest = body."),
            "kind": kindSchema,
            "collection": Schema.string("Project, topic or list to file it in, e.g. “Sidefolk”. Defaults to the Inbox."),
            "url": Schema.string("A web link this note is about (http or https)."),
            "tags": Schema.array("Short labels", items: Schema.string("One word or hyphenated phrase")),
        ], required: ["text"]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: true, external: true)

    func summary(for input: JSONValue) -> String {
        let title = NoteText.split(input.string("text") ?? "").title
        return "Save “\(title.clipped(60))” to \(input.string("collection") ?? NotebookStore.inboxName)"
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

        let target: (collection: NotebookCollection, created: Bool)
        if let name = input.string("collection") {
            target = try await NotebookCollections.resolveOrCreate(name, notebook: notebook, now: context.now)
        } else {
            target = (try await notebook.inbox(now: context.now), false)
        }
        let finalKind = kind ?? .note
        let item = NotebookItem(
            collectionId: target.collection.id, kind: finalKind, title: title, body: body, url: url,
            tags: NoteText.cleanTags(input.textList("tags") ?? []), source: context.caller.provenanceTag, now: context.now)
        try await notebook.add(item)
        events.changed(.notebook)

        let where_ = "\(target.collection.name) › \(NoteText.plural(finalKind))"
        var message = "Saved \(finalKind.rawValue) “\(title.clipped(80))” to \(target.collection.name) (id \(item.id))."
        var detail: String?
        if target.created {
            message += " “\(target.collection.name)” didn't exist, so I created it as a new project."
            detail = "New project “\(target.collection.name)” created."
        }
        let notebook = self.notebook, events = self.events, id = item.id
        return ToolResult(
            text: message,
            card: ResultCard(kind: .note, title: "Saved to \(where_)", subtitle: title.clipped(80), detail: detail, refId: id, url: url),
            undo: UndoAction(label: "Removed “\(title.clipped(40))”") {
                _ = try await notebook.trash(itemId: id)
                events.changed(.notebook)
            })
    }
}

struct NotesSearchTool: Tool {
    let notebook: NotebookStore

    let spec = ToolSpec(
        name: "notes.search", title: "Search notebook",
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
        var s = "Search your notes for “\((input.string("query") ?? "").clipped(60))”"
        if let c = input.string("collection") { s += " in \(c)" }
        return s
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let query = try input.requiredText("query", limit: 300)
        let kind = try NoteText.parseKind(input.string("kind"))
        let limit = input.clampedInt("limit", default: 10, in: 1...25)
        var collectionId: String?
        if let name = input.string("collection") {
            guard let c = try await NotebookCollections.resolve(name, notebook: notebook) else {
                throw ToolError.notFound("a collection called “\(name)”")
            }
            collectionId = c.id
        }
        let items = try await notebook.search(query, collectionId: collectionId, kinds: kind.map { [$0] }, limit: limit)
        guard !items.isEmpty else {
            return ToolResult(text: "No notes matched “\(query.clipped(60))”.",
                              card: ResultCard(kind: .list, title: "No matching notes", subtitle: query.clipped(60)))
        }
        let names = try await NotebookCollections.names(notebook)
        let body = items.map { NoteFormat.line($0, collections: names) }.joined(separator: "\n")
        return ToolResult(
            text: "\(ToolFormat.count(items.count, "note")) matched “\(query.clipped(60))”:\n\(body)",
            card: ResultCard(kind: .list, title: "\(ToolFormat.count(items.count, "match", "matches")) for “\(query.clipped(40))”",
                             subtitle: items.prefix(3).map { $0.title.clipped(30) }.joined(separator: " · ")),
            untrusted: NoteFormat.hasForeign(items))
    }
}

struct NotesListTool: Tool {
    let notebook: NotebookStore

    let spec = ToolSpec(
        name: "notes.list", title: "List notes",
        description: "List the newest notes, ideas, tasks and links, optionally for one collection, kind or status.",
        inputSchema: Schema.object([
            "collection": Schema.string("Only this project, topic or list"),
            "kind": kindSchema,
            "status": Schema.string("open or done (for tasks)", enum: ["open", "done"]),
            "limit": Schema.integer("Maximum items (default 20)", minimum: 1, maximum: 50),
        ]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: false)

    func summary(for input: JSONValue) -> String {
        if let c = input.string("collection") { return "List what's in \(c)" }
        return "List your newest notes"
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let kind = try NoteText.parseKind(input.string("kind"))
        let limit = input.clampedInt("limit", default: 20, in: 1...50)
        var status: NotebookItem.Status?
        if let raw = input.string("status") {
            guard let s = NotebookItem.Status(rawValue: raw.lowercased()) else { throw ToolError.invalidInput("“status” must be open or done.") }
            status = s
        }
        var collectionId: String?
        var scope = "everywhere"
        if let name = input.string("collection") {
            // Reading "About you" is fine here; only filing into it is refused.
            let found = NotebookCollections.isProfileName(name)
                ? try await NotebookCollections.profile(notebook, create: false)
                : try await NotebookCollections.resolve(name, notebook: notebook)
            guard let c = found else { throw ToolError.notFound("a collection called “\(name)”") }
            collectionId = c.id
            scope = "in \(c.name)"
        }
        let items = try await notebook.items(collectionId: collectionId, kinds: kind.map { [$0] }, status: status, limit: limit)
        guard !items.isEmpty else {
            return ToolResult(text: "Nothing found \(scope).", card: ResultCard(kind: .list, title: "Nothing here yet", subtitle: scope))
        }
        let names = try await NotebookCollections.names(notebook)
        return ToolResult(
            text: "\(ToolFormat.count(items.count, "item")) \(scope), newest first:\n"
                + items.map { NoteFormat.line($0, collections: names) }.joined(separator: "\n"),
            card: ResultCard(kind: .list, title: ToolFormat.count(items.count, "item"), subtitle: scope),
            untrusted: NoteFormat.hasForeign(items))
    }
}

struct NotesUpdateTool: Tool {
    let notebook: NotebookStore
    let events: EventBus

    let spec = ToolSpec(
        name: "notes.update", title: "Change a note",
        description: """
            Change an existing note by id: replace its text (first line = title), move it to another collection, \
            mark a task open or done, or replace its tags. Find ids with notes.search or notes.list.
            """,
        inputSchema: Schema.object([
            "id": Schema.string("The note's id"),
            "text": Schema.string("New text; the first line becomes the title"),
            "collection": Schema.string("Move it to this project, topic or list (created if missing)"),
            "status": Schema.string("open or done", enum: ["open", "done"]),
            "tags": Schema.array("Replaces the tags; an empty list clears them", items: Schema.string("A tag")),
        ], required: ["id"]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: true)

    func summary(for input: JSONValue) -> String {
        var changes: [String] = []
        if input["text"] != nil { changes.append("text") }
        if let c = input.string("collection") { changes.append("move to \(c)") }
        if let s = input.string("status") { changes.append("mark \(s)") }
        if input["tags"] != nil { changes.append("tags") }
        return "Change a note (" + (changes.isEmpty ? "nothing" : changes.joined(separator: ", ")) + ")"
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let id = try input.requiredText("id", limit: 64)
        guard var item = try await notebook.item(id: id) else { throw ToolError.notFound("a note with that id") }
        guard item.deletedAt == nil else {
            throw UserFacingError("That note is in the Trash, so I left it alone.", recovery: "Restore it from the Trash first.")
        }
        if try await NotebookCollections.isProfile(collectionId: item.collectionId, notebook: notebook) {
            throw UserFacingError("That's a fact in “About you”. Use the profile tools to change it.")
        }
        let previous = item
        var changed: [String] = []

        if input.string("text") != nil {
            let (title, body) = NoteText.split(try input.requiredText("text", limit: NoteText.maxText))
            item.title = title
            item.body = body
            // Whoever last wrote the words is who they are attributed to, but an outsider's note never becomes
            // trusted just because Sidefolk's own agent edited it.
            if !(ItemProvenance.isForeign(item.source) && context.caller != .user) { item.source = context.caller.provenanceTag }
            changed.append("text")
        }
        var movedTo: (collection: NotebookCollection, created: Bool)?
        if let name = input.string("collection") {
            let target = try await NotebookCollections.resolveOrCreate(name, notebook: notebook, now: context.now)
            if target.collection.id != item.collectionId {
                item.collectionId = target.collection.id
                movedTo = target
                changed.append("moved to \(target.collection.name)")
            }
        }
        if let raw = input.string("status") {
            guard let status = NotebookItem.Status(rawValue: raw.lowercased()) else { throw ToolError.invalidInput("“status” must be open or done.") }
            if status != item.status { changed.append("marked \(status.rawValue)") }
            item.status = status
        }
        if let tags = input.textList("tags") {
            item.tags = NoteText.cleanTags(tags).joined(separator: " ")
            changed.append("tags")
        }
        guard !changed.isEmpty else {
            throw ToolError.invalidInput("nothing to change. Give new text, a collection, a status or tags.")
        }

        item.updatedAt = context.now
        try await notebook.update(item)
        events.changed(.notebook)

        var message = "Updated “\(item.title.clipped(80))”: \(changed.joined(separator: ", "))."
        if movedTo?.created == true { message += " Created the new project “\(movedTo!.collection.name)”." }
        let notebook = self.notebook, events = self.events
        return ToolResult(
            text: message,
            card: ResultCard(kind: .note, title: "Updated note", subtitle: item.title.clipped(80), detail: changed.joined(separator: ", "), refId: item.id),
            undo: UndoAction(label: "Restored “\(previous.title.clipped(40))”") {
                try await notebook.update(previous)
                events.changed(.notebook)
            })
    }
}

struct NotesTrashTool: Tool {
    let notebook: NotebookStore
    let events: EventBus

    let spec = ToolSpec(
        name: "notes.trash", title: "Move a note to the Trash",
        description: "Move a note to the Trash by id. It stays restorable for 30 days.",
        inputSchema: Schema.object(["id": Schema.string("The note's id")], required: ["id"]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: true)

    func summary(for input: JSONValue) -> String { "Move a note to the Trash" }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let id = try input.requiredText("id", limit: 64)
        guard let item = try await notebook.item(id: id) else { throw ToolError.notFound("a note with that id") }
        guard item.deletedAt == nil else { throw UserFacingError("That note is already in the Trash.") }
        if try await NotebookCollections.isProfile(collectionId: item.collectionId, notebook: notebook) {
            throw UserFacingError("That's a fact in “About you”. Use “forget” to remove it.")
        }
        _ = try await notebook.trash(itemId: id, now: context.now)
        events.changed(.notebook)
        let notebook = self.notebook, events = self.events
        return ToolResult(
            text: "Moved “\(item.title.clipped(80))” to the Trash. It can be restored for 30 days.",
            card: ResultCard(kind: .note, title: "Moved to Trash", subtitle: item.title.clipped(80), refId: id),
            undo: UndoAction(label: "Restored “\(item.title.clipped(40))”") {
                try await notebook.restore(itemId: id)
                events.changed(.notebook)
            })
    }
}

struct CollectionsListTool: Tool {
    let notebook: NotebookStore

    let spec = ToolSpec(
        name: "collections.list", title: "List collections",
        description: "List the notebook's collections (Inbox, projects, topics, lists) with how many items each holds.",
        inputSchema: Schema.object([:]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: false)

    func summary(for input: JSONValue) -> String { "List your notebook collections" }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let collections = try await notebook.collections()
        let counts = try await NotebookCollections.itemCounts(notebook)
        guard !collections.isEmpty else {
            return ToolResult(text: "The notebook has no collections yet. Notes go to the Inbox.",
                              card: ResultCard(kind: .collection, title: "No collections yet"))
        }
        let lines = collections.map { c in
            "\(c.name) (\(c.kind == .profile ? "about you" : c.kind.rawValue), \(ToolFormat.count(counts[c.id] ?? 0, "item")))"
        }
        return ToolResult(text: "Collections:\n" + lines.map { "- " + $0 }.joined(separator: "\n"),
                          card: ResultCard(kind: .collection, title: ToolFormat.count(collections.count, "collection"),
                                           subtitle: collections.prefix(4).map(\.name).joined(separator: " · ")))
    }
}

struct CollectionsCreateTool: Tool {
    let notebook: NotebookStore
    let events: EventBus

    let spec = ToolSpec(
        name: "collections.create", title: "Create a collection",
        description: "Create a project, topic or list to file notes in. If one with that name exists it is reused.",
        inputSchema: Schema.object([
            "name": Schema.string("Name, e.g. “Sidefolk” or “Reading list”"),
            "kind": Schema.string("project, topic or list (default project)", enum: ["project", "topic", "list"]),
        ], required: ["name"]),
        risk: .low, capabilities: [.notebook], category: .notes, mutates: true)

    func summary(for input: JSONValue) -> String { "Create the collection “\((input.string("name") ?? "").clipped(60))”" }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let name = try input.requiredText("name", limit: 60)
        var kind = NotebookCollection.Kind.project
        if let raw = input.string("kind") {
            guard let k = NotebookCollection.Kind(rawValue: raw.lowercased()), [.project, .topic, .list].contains(k) else {
                throw ToolError.invalidInput("“kind” must be project, topic or list.")
            }
            kind = k
        }
        if NotebookCollections.isProfileName(name) { throw NotebookCollections.profileRefusal }
        // Reuse only an exact (case-insensitive) match here; fuzzy matching is for filing notes.
        let existing = try await NotebookCollections.filable(notebook).first { $0.name.lowercased() == name.lowercased() }
        if let existing {
            return ToolResult(text: "“\(existing.name)” already exists.",
                              card: ResultCard(kind: .collection, title: existing.name, subtitle: "Already exists", refId: existing.id))
        }
        let created = try await NotebookCollections.create(name, kind: kind, notebook: notebook, now: context.now)
        events.changed(.notebook)
        let notebook = self.notebook, events = self.events, id = created.id
        return ToolResult(
            text: "Created the \(kind.rawValue) “\(created.name)”.",
            card: ResultCard(kind: .collection, title: created.name, subtitle: "New \(kind.rawValue)", refId: id),
            undo: UndoAction(label: "Removed “\(created.name.clipped(40))”") {
                // Never cascade-delete notes that were filed here since.
                guard try await NotebookCollections.totalItemCount(collectionId: id, notebook: notebook) == 0 else {
                    throw UserFacingError("“\(created.name)” has notes in it now, so I left it.")
                }
                try await notebook.deleteCollection(id: id)
                events.changed(.notebook)
            })
    }
}
