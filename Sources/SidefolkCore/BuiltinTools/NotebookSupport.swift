import Foundation
import GRDB

extension String {
    var trimmedText: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Finding and creating the collections notes are filed into. "About you" (the profile) is never a
/// filing target: facts about the user go through the `profile.*` tools (DECISIONS D6).
enum NotebookCollections {
    static let profileName = "About you"

    static var profileRefusal: UserFacingError {
        UserFacingError("“\(profileName)” holds facts about you, so notes can't be filed there.",
                        recovery: "Use “remember” for facts and preferences.")
    }

    static func isProfileName(_ name: String) -> Bool { name.trimmedText.lowercased() == profileName.lowercased() }

    /// Collections a note may live in: everything except the profile.
    static func filable(_ notebook: NotebookStore) async throws -> [NotebookCollection] {
        try await notebook.collections().filter { $0.kind != .profile }
    }

    /// Exact name, then prefix, then containment (case-insensitive), among filable collections.
    static func resolve(_ name: String, notebook: NotebookStore) async throws -> NotebookCollection? {
        let wanted = name.trimmedText.lowercased()
        guard !wanted.isEmpty else { return nil }
        if isProfileName(wanted) { throw profileRefusal }
        let all = try await filable(notebook)
        if let exact = all.first(where: { $0.name.lowercased() == wanted }) { return exact }
        if let prefix = all.first(where: { $0.name.lowercased().hasPrefix(wanted) }) { return prefix }
        return all.first { c in
            let n = c.name.lowercased()
            return n.contains(wanted) || (n.count >= 3 && wanted.contains(n))
        }
    }

    /// The kind to give a collection that has to be created: a project unless the tool input says topic or list.
    static func newKind(_ raw: JSONValue?) throws -> NotebookCollection.Kind {
        guard let text = raw?.stringValue?.trimmedText.lowercased(), !text.isEmpty else { return .project }
        guard let kind = NotebookCollection.Kind(rawValue: text), [.project, .topic, .list].contains(kind) else {
            throw ToolError.invalidInput("“collection_kind” must be project, topic or list.")
        }
        return kind
    }

    static func resolveOrCreate(_ name: String, kind: NotebookCollection.Kind = .project, notebook: NotebookStore,
                                now: Date) async throws -> (collection: NotebookCollection, created: Bool) {
        if name.trimmedText.lowercased() == NotebookStore.inboxName.lowercased() {
            return (try await notebook.inbox(now: now), false)
        }
        if let found = try await resolve(name, notebook: notebook) { return (found, false) }
        return (try await create(name, kind: kind, notebook: notebook, now: now), true)
    }

    static func create(_ name: String, kind: NotebookCollection.Kind, notebook: NotebookStore, now: Date) async throws -> NotebookCollection {
        let clean = name.trimmedText.clipped(60)
        guard !clean.isEmpty else { throw ToolError.invalidInput("a collection needs a name.") }
        if isProfileName(clean) { throw profileRefusal }
        let collection = NotebookCollection(name: clean, kind: kind, now: now)
        try await notebook.db.writer.write { db in try collection.insert(db) }
        return collection
    }

    /// The "About you" collection; created on demand when `create` is true.
    static func profile(_ notebook: NotebookStore, create: Bool, now: Date = Date()) async throws -> NotebookCollection? {
        let kind = NotebookCollection.Kind.profile.rawValue
        if !create {
            return try await notebook.db.writer.read { db in try NotebookCollection.filter(Column("kind") == kind).fetchOne(db) }
        }
        return try await notebook.db.writer.write { db in
            if let existing = try NotebookCollection.filter(Column("kind") == kind).fetchOne(db) { return existing }
            let profile = NotebookCollection(name: profileName, kind: .profile, emoji: "👤", now: now)
            try profile.insert(db)
            return profile
        }
    }

    /// Whether `collectionId` is the profile collection.
    static func isProfile(collectionId: String, notebook: NotebookStore) async throws -> Bool {
        try await notebook.collection(id: collectionId)?.kind == .profile
    }

    /// id → name for every collection, archived ones included, so old items still show where they live.
    static func names(_ notebook: NotebookStore) async throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try await notebook.collections(includeArchived: true).map { ($0.id, $0.name) })
    }

    /// Live (not trashed) item counts per collection.
    static func itemCounts(_ notebook: NotebookStore) async throws -> [String: Int] {
        try await notebook.db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT collection_id, COUNT(*) AS n FROM items WHERE deleted_at IS NULL GROUP BY collection_id")
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["collection_id"] as String, $0["n"] as Int) })
        }
    }

    /// Items of any state in a collection, trashed ones included (used to decide whether it is empty).
    static func totalItemCount(collectionId: String, notebook: NotebookStore) async throws -> Int {
        try await notebook.db.writer.read { db in
            try NotebookItem.filter(Column("collection_id") == collectionId).fetchCount(db)
        }
    }
}

enum NoteText {
    static let maxTitle = 120
    static let maxText = 20_000

    /// First line is the title, the rest the body. A first line too long for a title is clipped and
    /// the whole text kept as the body, so nothing is lost.
    static func split(_ text: String) -> (title: String, body: String) {
        // "\r\n" is a single Character to Swift and would never match "\n": pasted Windows text became one long title.
        let all = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").trimmedText
        let parts = all.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let first = String(parts.first ?? "").trimmedText
        let rest = parts.count > 1 ? String(parts[1]).trimmedText : ""
        guard first.count > maxTitle else { return (first, rest) }
        var cut = String(first.prefix(maxTitle - 1))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > maxTitle / 2 {
            cut = String(cut[..<space])
        }
        return (cut + "…", all)
    }

    /// An http(s) URL with a host and no whitespace, or nil.
    static func httpURL(_ text: String) -> URL? {
        guard !text.isEmpty, text.count <= 2_048, !text.contains(where: \.isWhitespace),
              let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// The URL when the whole text is one link.
    static func singleURL(in text: String) -> URL? { httpURL(text.trimmedText) }

    static func firstURL(in text: String) -> URL? {
        let edge = CharacterSet(charactersIn: "([<.,;:!?)]}>\"'")
        for token in text.split(whereSeparator: \.isWhitespace) {
            if let url = httpURL(token.trimmingCharacters(in: edge)) { return url }
        }
        return nil
    }

    /// "example.com/pricing" from "https://www.example.com/pricing/".
    static func displayTitle(for url: URL) -> String {
        var host = url.host ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return (host + path).clipped(maxTitle)
    }

    /// Tags are stored space-separated, so a tag can't contain spaces.
    static func cleanTags(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for tag in raw {
            let t = tag.trimmingCharacters(in: CharacterSet(charactersIn: "# \t\n"))
                .split(whereSeparator: \.isWhitespace).joined(separator: "-").lowercased().clipped(30)
            if !t.isEmpty, seen.insert(t).inserted { out.append(t) }
            if out.count == 10 { break }
        }
        return out
    }

    static func parseKind(_ raw: String?) throws -> NotebookItem.Kind? {
        guard let raw = raw?.trimmedText.lowercased(), !raw.isEmpty else { return nil }
        if let kind = NotebookItem.Kind(rawValue: raw) ?? NotebookItem.Kind(rawValue: String(raw.dropLast())) { return kind }
        throw ToolError.invalidInput("“kind” must be one of note, idea, task, link.")
    }

    static func plural(_ kind: NotebookItem.Kind) -> String {
        switch kind {
        case .note: "Notes"
        case .idea: "Ideas"
        case .task: "Tasks"
        case .link: "Links"
        }
    }
}

/// Compact one-line renderings of notebook items for the model.
enum NoteFormat {
    static func line(_ item: NotebookItem, collections: [String: String], snippet: Bool = true) -> String {
        var parts = ["[\(item.kind.rawValue)] \(ToolFormat.oneLine(ExternalText.clean(item.title), 100))"]
        var meta = [collections[item.collectionId] ?? "?", ToolFormat.day(item.createdAt)]
        if item.status == .done { meta.append("done") }
        if !item.tagList.isEmpty { meta.append("#" + item.tagList.joined(separator: " #")) }
        if let origin = ItemProvenance.note(for: item.source) { meta.append(origin) }
        parts.append("— " + meta.joined(separator: ", "))
        var text = "\(item.id)  " + parts.joined(separator: " ")
        if snippet {
            let body = ToolFormat.oneLine(ExternalText.clean(item.body), 110)
            if !body.isEmpty, body != ToolFormat.oneLine(ExternalText.clean(item.title), 110) { text += "\n    " + body }
        }
        return text
    }

    /// True when any item was written by something other than the user or Sidefolk's own agent.
    static func hasForeign(_ items: [NotebookItem]) -> Bool { items.contains { ItemProvenance.isForeign($0.source) } }
}
