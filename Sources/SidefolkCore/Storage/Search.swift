import Foundation
import GRDB

/// What one search finds across Sidefolk (D58): the one bar in Home and the Ask panel show it grouped, a few of each.
public struct SearchResults: Sendable, Equatable {
    public var notes: [NotebookItem] = []
    public var conversations: [ConversationSummary] = []
    /// Reminders still to come.
    public var reminders: [Reminder] = []
    public var watches: [Watcher] = []
    public var activity: [ActivityEntry] = []

    public init() {}

    public var isEmpty: Bool { notes.isEmpty && conversations.isEmpty && reminders.isEmpty && watches.isEmpty && activity.isEmpty }
}

extension SidefolkRuntime {
    /// The shortest words worth searching for: one letter would match nearly everything.
    public static let shortestSearch = 2

    /// Everything that matches `query`, up to `limit` of each kind: notes by the notebook's own search, the rest when
    /// every word appears in their title or words (case and accents ignored). Trashed notes and finished reminders
    /// stay out; watches show whatever their state, since a stopped one is still worth finding.
    public func find(_ query: String, limit: Int = 5) async throws -> SearchResults {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= Self.shortestSearch else { return SearchResults() }
        let words = query.split(whereSeparator: \.isWhitespace).prefix(8).map(String.init)
        func matches(_ text: String) -> Bool {
            words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }

        var found = SearchResults()
        found.notes = try await notebook.search(query, limit: limit)
        found.conversations = try await exchanges.conversations(matching: query, limit: limit)
        found.reminders = Array(try await reminderStore.pending().filter { matches($0.title) }.prefix(limit))
        found.watches = Array(try await watcherStore.all().filter { matches($0.title) }.prefix(limit))
        found.activity = try await activity.matching(words, limit: limit)
        return found
    }
}

extension ActivityStore {
    /// The newest rows whose summary has every word (as typed: `%` and `_` are literal).
    public func matching(_ words: [String], limit: Int) async throws -> [ActivityEntry] {
        guard !words.isEmpty else { return [] }
        return try await db.writer.read { db in
            var request = ActivityEntry.all()
            for word in words {
                request = request.filter(sql: #"summary LIKE ? ESCAPE '\'"#, arguments: ["%" + NotebookStore.escapeLike(word) + "%"])
            }
            return try request.order(Column("at").desc, Column("id").desc).limit(limit).fetchAll(db)
        }
    }
}
