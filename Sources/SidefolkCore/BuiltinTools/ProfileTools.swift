import Foundation

/// Facts and preferences about the user. Per DECISIONS D6 they are ordinary notebook items in a
/// pinned "About you" collection, so the user sees and edits them in one place.
public enum ProfileFacts {
    /// The facts Sidefolk keeps in mind in every conversation, oldest first (a stable order keeps the
    /// prompt prefix stable). Facts written by external agents, extensions or routines are left out
    /// unless `includeUntrusted` is true: they must not steer the model unseen (docs/SECURITY.md T3).
    /// Returns an empty list when nothing is stored or the notebook can't be read.
    public static func all(notebook: NotebookStore, includeUntrusted: Bool = false) async -> [NotebookItem] {
        do {
            guard let profile = try await NotebookCollections.profile(notebook, create: false) else { return [] }
            let items = try await notebook.items(collectionId: profile.id, limit: ProfileLimits.maxFacts + 50)
            return items.reversed().filter { includeUntrusted || !ItemProvenance.isForeign($0.source) }
        } catch {
            return []
        }
    }
}

enum ProfileLimits {
    static let maxFacts = 200
    static let maxFactLength = 500
}

/// A fact as a single line of text.
private func factText(_ item: NotebookItem) -> String {
    if item.body.isEmpty { return item.title }
    // A clipped title means the body already holds the whole text.
    if item.title.hasSuffix("…"), item.body.hasPrefix(item.title.dropLast()) {
        return ToolFormat.oneLine(item.body, ProfileLimits.maxFactLength)
    }
    return ToolFormat.oneLine(item.title + " " + item.body, ProfileLimits.maxFactLength)
}

private func normalized(_ text: String) -> String { ToolFormat.oneLine(text, 1_000).lowercased() }

struct ProfileRememberTool: Tool {
    let notebook: NotebookStore
    let events: EventBus

    let spec = ToolSpec(
        name: "profile.remember", title: "Remember about you",
        description: """
            Remember a lasting fact or preference about the user ("prefers short answers", "dog is called Bo", \
            "works in UTC+1"). Only for things worth knowing in future conversations, never for one-off tasks \
            (use notes for those) and never secrets such as passwords.
            """,
        inputSchema: Schema.object(["fact": Schema.string("One short statement, e.g. “Prefers metric units”")], required: ["fact"]),
        risk: .low, capabilities: [.memory], category: .memory, mutates: true, external: true)

    func summary(for input: JSONValue) -> String { "Remember: “\((input.string("fact") ?? "").clipped(100))”" }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let fact = try input.requiredText("fact", limit: ProfileLimits.maxFactLength)
        let existing = await ProfileFacts.all(notebook: notebook, includeUntrusted: true)
        if let same = existing.first(where: { normalized(factText($0)) == normalized(fact) }) {
            return ToolResult(text: "Already remembered: “\(factText(same).clipped(100))”.",
                              card: ResultCard(kind: .memory, title: "Already remembered", subtitle: factText(same).clipped(80), refId: same.id))
        }
        guard existing.count < ProfileLimits.maxFacts else {
            throw UserFacingError("“About you” already holds \(ProfileLimits.maxFacts) facts.",
                                  recovery: "Forget a few that no longer matter, then try again.")
        }
        guard let profile = try await NotebookCollections.profile(notebook, create: true, now: context.now) else {
            throw ToolError.unavailable("I couldn't open “About you”.")
        }
        let (title, body) = NoteText.split(fact)
        let item = NotebookItem(collectionId: profile.id, kind: .note, title: title, body: body,
                                source: context.caller.sourceTag, now: context.now)
        try await notebook.add(item)
        events.changed(.notebook)
        events.changed(.memories)

        let notebook = self.notebook, events = self.events, id = item.id
        return ToolResult(
            text: "Remembered: “\(fact.clipped(100))” (id \(id)).",
            card: ResultCard(kind: .memory, title: "Remembered", subtitle: fact.clipped(80), refId: id),
            undo: UndoAction(label: "Forgot “\(fact.clipped(40))”") {
                _ = try await notebook.trash(itemId: id)
                events.changed(.notebook)
                events.changed(.memories)
            })
    }
}

struct ProfileListTool: Tool {
    let notebook: NotebookStore

    let spec = ToolSpec(
        name: "profile.list", title: "What I know about you",
        description: "List the facts and preferences remembered about the user, with ids.",
        inputSchema: Schema.object([:]),
        risk: .low, capabilities: [.memory], category: .memory, mutates: false)

    func summary(for input: JSONValue) -> String { "List what Sidefolk remembers about you" }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let facts = await ProfileFacts.all(notebook: notebook, includeUntrusted: true)
        guard !facts.isEmpty else {
            return ToolResult(text: "Nothing is remembered about the user yet.",
                              card: ResultCard(kind: .memory, title: "Nothing remembered yet"))
        }
        let lines = facts.map { f -> String in
            var meta = ToolFormat.day(f.createdAt)
            if let origin = ItemProvenance.note(for: f.source) { meta += ", \(origin)" }
            return "\(f.id)  \(factText(f).clipped(200)) (\(meta))"
        }
        return ToolResult(
            text: "\(ToolFormat.count(facts.count, "fact")) about the user:\n" + lines.joined(separator: "\n"),
            card: ResultCard(kind: .memory, title: ToolFormat.count(facts.count, "fact") + " remembered"),
            untrusted: NoteFormat.hasForeign(facts))
    }
}

struct ProfileForgetTool: Tool {
    let notebook: NotebookStore
    let events: EventBus

    let spec = ToolSpec(
        name: "profile.forget", title: "Forget a fact",
        description: "Forget one remembered fact by id (from profile.list). It moves to the Trash and can be restored.",
        inputSchema: Schema.object(["id": Schema.string("The fact's id")], required: ["id"]),
        risk: .low, capabilities: [.memory], category: .memory, mutates: true)

    func summary(for input: JSONValue) -> String { "Forget a fact about you" }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let id = try input.requiredText("id", limit: 64)
        guard let item = try await notebook.item(id: id), item.deletedAt == nil else {
            throw ToolError.notFound("a remembered fact with that id")
        }
        guard let profile = try await NotebookCollections.profile(notebook, create: false), item.collectionId == profile.id else {
            throw UserFacingError("That isn't one of the facts about you. Use the notes tools for notes.")
        }
        _ = try await notebook.trash(itemId: id, now: context.now)
        events.changed(.notebook)
        events.changed(.memories)
        let text = factText(item)
        let notebook = self.notebook, events = self.events
        return ToolResult(
            text: "Forgot “\(text.clipped(100))”.",
            card: ResultCard(kind: .memory, title: "Forgot", subtitle: text.clipped(80), refId: id),
            undo: UndoAction(label: "Remembered “\(text.clipped(40))” again") {
                try await notebook.restore(itemId: id)
                events.changed(.notebook)
                events.changed(.memories)
            })
    }
}
