import Foundation
import GRDB

extension String {
    var trimmedText: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Finding and creating the collections notes are filed into. "About you" (the profile) is never a
/// filing target: facts about the user go through the `profile.*` tools (DECISIONS D6).
public enum NotebookCollections {
    static let profileName = "About you"

    static var profileRefusal: UserFacingError {
        UserFacingError("“About you” holds facts about you, so notes can't be filed there.",
                        recovery: "Use “remember” for facts and preferences.")
    }

    static func isProfileName(_ name: String) -> Bool { name.trimmedText.lowercased() == profileName.lowercased() }

    /// Collections a note may live in: everything except the profile.
    static func filable(_ notebook: NotebookStore) async throws -> [NotebookCollection] {
        try await notebook.collections().filter { $0.kind != .profile }
    }

    /// The exact name, or one unambiguous whole-word prefix (`NotebookStore.match`), among filable collections;
    /// failing that, the name without what kind of collection it is ("my shopping list" for "Shopping"), the way
    /// people name a list to another agent, which can't create one instead.
    static func resolve(_ name: String, notebook: NotebookStore) async throws -> NotebookCollection? {
        if isProfileName(name) { throw profileRefusal }
        let all = try await filable(notebook)
        if let found = NotebookStore.match(name, in: all) { return found }
        let bare = name.trimmedText.lowercased()
            .replacingOccurrences(of: #"^(my|the)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+(list|project|topic)$"#, with: "", options: .regularExpression)
        return bare.isEmpty || bare == name.trimmedText.lowercased() ? nil : NotebookStore.match(bare, in: all)
    }

    static func isInboxName(_ name: String) -> Bool { name.trimmedText.lowercased() == NotebookStore.inboxName.lowercased() }

    /// The kind to give a collection that has to be created: a project unless the tool input says topic or list.
    static func newKind(_ raw: JSONValue?) throws -> NotebookCollection.Kind {
        guard let text = raw?.stringValue?.trimmedText.lowercased(), !text.isEmpty else { return .project }
        guard let kind = NotebookCollection.Kind(rawValue: text), [.project, .topic, .list].contains(kind) else {
            throw ToolError.invalidInput(String(localized: "“collection_kind” must be project, topic or list."))
        }
        return kind
    }

    /// Finds or creates in one transaction, so parallel saves to a new project make it once. A new one
    /// records who named it; other agents only file into collections that exist (`mayCreate`).
    static func resolveOrCreate(_ name: String, kind: NotebookCollection.Kind = .project, notebook: NotebookStore,
                                context: ToolContext) async throws -> (collection: NotebookCollection, created: Bool) {
        if isInboxName(name) { return (try await notebook.inbox(now: context.now), false) }
        if isProfileName(name) { throw profileRefusal }
        guard mayCreate(context.caller) else {
            guard let found = try await resolve(name, notebook: notebook) else { throw creationRefusal(name, caller: context.caller) }
            return (found, false)
        }
        let (collection, created) = try await notebook.collection(named: name, kind: kind, excluding: [.profile],
                                                                  source: context.provenanceTag, now: context.now)
        return (collection, created)
    }

    static func create(_ name: String, kind: NotebookCollection.Kind, notebook: NotebookStore, context: ToolContext) async throws -> NotebookCollection {
        // What can't be seen goes first, so a name that only looks like About you or the Inbox is taken for what it looks like.
        let clean = cleanName(name)
        guard !clean.isEmpty else { throw ToolError.invalidInput(String(localized: "a collection needs a name.")) }
        if looksLikeProfile(clean) { throw profileRefusal }
        // The Inbox always exists (it is made on first use); a look-alike "inbox" project would split notes.
        if looksLikeInbox(clean) {
            throw UserFacingError("“Inbox” is always there: it's where notes go when no collection is named.")
        }
        // Another agent, only on the person's yes on a card (D160); `notes.save` never makes one for it.
        guard mayCreate(context.caller) || context.personWasAsked else { throw creationRefusal(clean, caller: context.caller) }
        return try await notebook.createCollection(name: clean, kind: kind, source: context.provenanceTag, now: context.now)
    }

    /// A name as it reads: compatibility forms folded, what can't be seen gone, case ignored. Letters from another script
    /// that look the same (a Cyrillic "Іnbox") aren't caught: a card shows them, and they're an accepted residual (D160).
    static func asItReads(_ name: String) -> String {
        let seen = String(String.UnicodeScalarView(cleanName(name, limit: .max).precomposedStringWithCompatibilityMapping.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint }))
        return seen.displaySafe.lowercased()
    }

    /// A collection's name with only what shows: no format, private or unassigned characters and none that draw nothing. What
    /// the card says is then what's kept, and a twin can't hide behind a character the check doesn't know.
    static func cleanName(_ name: String, limit: Int = 60) -> String {
        let shown = name.displaySafe.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .format, .control, .privateUse, .surrogate, .unassigned, .lineSeparator, .paragraphSeparator: false
            default: scalar.value != 0x2800 && scalar.value != 0xFFFC
            }
        }
        return String(String.UnicodeScalarView(shown)).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ").clipped(limit)
    }

    /// Another collection that reads the same as this name, whichever way it's spelled.
    static func twin(of name: String, excluding id: String? = nil, notebook: NotebookStore) async throws -> NotebookCollection? {
        try await notebook.collections(includeArchived: true).first { $0.id != id && asItReads($0.name) == asItReads(name) }
    }

    static func looksLikeProfile(_ name: String) -> Bool {
        [profileName, String(localized: "About you")].contains { asItReads($0) == asItReads(name) }
    }

    static func looksLikeInbox(_ name: String) -> Bool {
        [NotebookStore.inboxName, String(localized: "Inbox")].contains { asItReads($0) == asItReads(name) }
    }

    /// The notebook's shape is the user's: other agents and extensions file into what exists, and never
    /// add projects or lists whose names would sit next to the user's own (SECURITY T4).
    static func mayCreate(_ caller: Caller) -> Bool { caller.kind != "external" && caller.kind != "extension" }

    /// The way out is in the message itself: the agent that has to act on it reads the message, not the recovery.
    static func creationRefusal(_ name: String, caller: Caller) -> UserFacingError {
        // Another agent has a way to ask (D160), in English like everything written for it.
        if case .external = caller {
            return UserFacingError(verbatim: "There's no collection called “\(name.trimmedText.clipped(60))”, and saving a note doesn't make one. Save it without a collection (it goes to the Inbox), or make it with collections_create, which asks the user.")
        }
        return UserFacingError("There's no collection called “\(name.trimmedText.clipped(60))”, and other apps can't create one. Save it without a collection (it goes to the Inbox), or ask the user to create it in Sidefolk first.")
    }

    /// The name people see: the Inbox and “About you” in the app's language, any other as it was named.
    public static func shownName(_ c: NotebookCollection) -> String {
        switch c.kind {
        case .inbox: String(localized: "Inbox")
        case .profile: String(localized: "About you")
        case .project, .topic, .list: c.name
        }
    }

    /// "New project", under the name of a collection that was just made.
    static func newLabel(_ kind: NotebookCollection.Kind) -> String {
        switch kind {
        case .topic: String(localized: "New topic")
        case .list: String(localized: "New list")
        default: String(localized: "New project")
        }
    }

    /// "New project “Sidefolk” created.", on the card of a note that made its collection.
    static func createdNote(_ c: NotebookCollection) -> String {
        switch c.kind {
        case .topic: String(localized: "New topic “\(c.name)” created.")
        case .list: String(localized: "New list “\(c.name)” created.")
        default: String(localized: "New project “\(c.name)” created.")
        }
    }

    /// Whether the collection's name is someone else's words (another agent, an extension, a tainted turn).
    static func isForeign(_ c: NotebookCollection) -> Bool { !ContextBuilder.isUserSourced(c.source) }

    /// The "About you" collection; created on demand when `create` is true.
    static func profile(_ notebook: NotebookStore, create: Bool, now: Date = Date()) async throws -> NotebookCollection? {
        let kind = NotebookCollection.Kind.profile.rawValue
        if !create {
            return try await notebook.db.writer.read { db in try NotebookCollection.filter(Column("kind") == kind).fetchOne(db) }
        }
        return try await notebook.db.writer.write { db in
            if let existing = try NotebookCollection.filter(Column("kind") == kind).fetchOne(db) { return existing }
            let profile = NotebookCollection(name: profileName, kind: .profile, now: now)
            try profile.insert(db)
            return profile
        }
    }

    /// Whether `collectionId` is the profile collection.
    static func isProfile(collectionId: String, notebook: NotebookStore) async throws -> Bool {
        try await notebook.collection(id: collectionId)?.kind == .profile
    }

    /// id → collection for every collection, archived ones included, so old items still show where they live.
    static func byId(_ notebook: NotebookStore) async throws -> [String: NotebookCollection] {
        Dictionary(uniqueKeysWithValues: try await notebook.collections(includeArchived: true).map { ($0.id, $0) })
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
        throw ToolError.invalidInput(String(localized: "“kind” must be one of note, idea, task, link."))
    }

    /// "Updated idea", on the card of a changed item.
    static func updated(_ kind: NotebookItem.Kind) -> String {
        switch kind {
        case .note: String(localized: "Updated note")
        case .idea: String(localized: "Updated idea")
        case .task: String(localized: "Updated task")
        case .link: String(localized: "Updated link")
        }
    }

    /// On the card of an item that only got a reminder (D49).
    static var reminded: String { String(localized: "Reminder set") }

    static func plural(_ kind: NotebookItem.Kind) -> String {
        switch kind {
        case .note: String(localized: "Notes")
        case .idea: String(localized: "Ideas")
        case .task: String(localized: "Tasks")
        case .link: String(localized: "Links")
        }
    }
}

/// Compact one-line renderings of notebook items for the model.
/// When a task is due (D117), read from words or for the model. A date in the past is fine: it's late, not wrong. Not a
/// reminder: nothing comes of it by itself, except that it stands on the Calendar.
public enum NoteDue {
    enum Change {
        case clear
        case set(Date, allDay: Bool)
    }

    /// A day rather than a time is kept as noon that day, so moving a few time zones doesn't make it the day before.
    public static func dayInstant(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    /// What `due` asks for, nil when it isn't there, read before anything is changed so a bad one changes nothing. Empty clears.
    static func read(_ text: String?, parser: WhenParser, now: Date) throws -> Change? {
        guard let text else { return nil }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if words.isEmpty { return .clear }
        guard words.count <= 200, let found = parser.parse(words, now: now), found.confidence != .low else {
            throw UserFacingError("I couldn't read “\(words.clipped(60))” as a date.", recovery: "Try something like “friday”, “dec 5” or “tomorrow at 5pm”.")
        }
        guard found.recurrence == nil else {
            throw UserFacingError("A due date can't repeat. For something that comes back, set a repeating reminder instead.")
        }
        return found.hasTime ? .set(found.date, allDay: false) : .set(dayInstant(found.date, calendar: parser.calendar), allDay: true)
    }

    /// Whether this kind can have what's asked.
    static func check(_ change: Change?, kind: NotebookItem.Kind) throws {
        if case .set = change, kind != .task { throw UserFacingError("Only a task has a due date. For a note, set a reminder instead.") }
    }

    /// True when it changed anything.
    static func apply(_ change: Change?, to item: inout NotebookItem) -> Bool {
        switch change {
        case nil: return false
        case .clear:
            guard item.dueAt != nil else { return false }
            item.dueAt = nil
            item.dueAllDay = false
        case .set(let date, let allDay):
            item.dueAt = date
            item.dueAllDay = allDay
        }
        return true
    }

    static func line(_ item: NotebookItem) -> String? {
        guard let due = item.dueAt, item.kind == .task else { return nil }
        return "due " + (item.dueAllDay ? ToolFormat.day(due) : TimeFormat.full(due, calendar: .current))
    }
}

enum NoteFormat {
    /// - Parameter reminder: the item's next reminder (D49), so "move my reminder for the report" has an id to use.
    static func line(_ item: NotebookItem, collections: [String: NotebookCollection], snippet: Bool = true, reminder: Reminder? = nil) -> String {
        var parts = ["[\(item.kind.rawValue)] \(ToolFormat.oneLine(ExternalText.clean(item.title), 100))"]
        let place = collections[item.collectionId].map { ToolFormat.oneLine(ExternalText.clean($0.name), 60) }
        var meta = [place ?? "?", ToolFormat.day(item.createdAt)]
        if item.status == .done { meta.append("done") }
        if let due = NoteDue.line(item) { meta.append(due) }
        if let reminder, let due = reminder.nextDue { meta.append("reminder \(TimeFormat.full(due, calendar: .current)) (reminder \(reminder.id))") }
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

    /// The next reminder of each of these items, for `line`.
    static func reminders(_ items: [NotebookItem], notebook: NotebookStore) async -> [String: Reminder] {
        (try? await ReminderStore(notebook.db).next(forItems: items.map(\.id))) ?? [:]
    }

    /// True when any item was written by something other than the user or Sidefolk's own agent.
    static func hasForeign(_ items: [NotebookItem]) -> Bool { items.contains { ItemProvenance.isForeign($0.source) } }

    /// The same, counting the collection names `line` quotes next to each item.
    static func hasForeign(_ items: [NotebookItem], collections: [String: NotebookCollection]) -> Bool {
        hasForeign(items) || items.contains { collections[$0.collectionId].map(NotebookCollections.isForeign) == true }
    }
}
