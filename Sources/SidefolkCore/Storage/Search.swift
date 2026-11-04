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
    /// Extensions installed here or in the gallery's last checked list, matched on this Mac (B1).
    public var extensions: [ExtensionHit] = []

    public init() {}

    public var isEmpty: Bool {
        notes.isEmpty && conversations.isEmpty && reminders.isEmpty && watches.isEmpty && activity.isEmpty && extensions.isEmpty
    }
}

/// An extension a search found, to open where it lives: its page or its row in Settings when installed, the Gallery when not.
public struct ExtensionHit: Sendable, Equatable, Identifiable {
    public enum Place: Sendable, Equatable {
        case installed(enabled: Bool)
        case gallery
    }

    public var id: String
    public var name: String
    public var tagline: String
    public var place: Place
    /// The words are in its name, not only in what it says about itself: the one bar opens it on Return, never asks the AI.
    public var byName: Bool
    /// The installed copy's icon, or the gallery's picture.
    public var iconPath: String?

    public init(id: String, name: String, tagline: String, place: Place, byName: Bool, iconPath: String? = nil) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.place = place
        self.byName = byName
        self.iconPath = iconPath
    }

    /// Installed extensions first, then the gallery's that aren't installed, each by name first. The gallery's are the
    /// ones its offer lists on `channel` (D65), read from the last catalog on this Mac: no network, no AI.
    public static func matching(_ query: String, installed: [ExtensionInfo], catalog: AddonCatalog?, channel: UpdateChannel,
                                limit: Int) -> [ExtensionHit] {
        let words = ExtensionListQuery(text: query)
        guard words.isSearching else { return [] }
        func hit(_ id: String, _ name: String, _ tagline: String, _ about: [String], _ place: Place, _ icon: String?) -> ExtensionHit? {
            let byName = words.matches([name])
            guard byName || words.matches([name, tagline] + about) else { return nil }
            return ExtensionHit(id: id, name: name, tagline: tagline, place: place, byName: byName, iconPath: icon)
        }
        let here = installed.compactMap { e in
            hit(e.id, e.name, e.tagline ?? "", [e.description ?? ""] + e.tools.map(\.title), .installed(enabled: e.enabled), e.iconPath)
        }
        let have = Set(installed.map(\.id))
        let offered = (catalog?.offered(on: channel) ?? []).filter { $0.kind == .extension && !have.contains($0.id) }.compactMap { e in
            hit(e.id, e.shownName, e.shownTagline, [e.shownDescription], .gallery, catalog?.preview(for: e)?.path)
        }
        // The name the words spell out comes first, then names holding them, then the rest.
        let typed = ExtensionListQuery.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        func rank(_ hit: ExtensionHit) -> Int { ExtensionListQuery.fold(hit.name) == typed ? 0 : hit.byName ? 1 : 2 }
        func byNameFirst(_ hits: [ExtensionHit]) -> [ExtensionHit] { hits.sorted { (rank($0), $0.name) < (rank($1), $1.name) } }
        return Array((byNameFirst(here) + byNameFirst(offered)).prefix(limit))
    }
}

extension SidefolkRuntime {
    /// The shortest words worth searching for: one letter would match nearly everything.
    public static let shortestSearch = 2

    /// Everything that matches `query`, up to `limit` of each kind: notes by the notebook's own search, the rest when
    /// every word appears in their title or words (case and accents ignored), and extensions installed or in the gallery's
    /// last checked list by name first (never the network or the AI). Trashed notes and finished reminders
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
        found.extensions = ExtensionHit.matching(query, installed: await extensions.extensions(), catalog: await addons.stored(),
                                                 channel: settings.current.updates.effectiveChannel, limit: limit)
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
