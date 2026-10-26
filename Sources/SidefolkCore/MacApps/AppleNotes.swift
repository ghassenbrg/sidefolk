import Foundation
import Synchronization

public struct NotesFolder: Sendable, Hashable {
    public var id: String
    public var name: String
    public var accountName: String
    public var parentId: String?
    /// Folder names from the account down to this one.
    public var path: [String]
    /// Notes' own Recently Deleted folder: its notes are never listed, copied or removed again.
    public var isRecentlyDeleted: Bool
    public var noteCount: Int

    /// "iCloud › Recipes › Weeknight".
    public var place: String { ([accountName] + path).joined(separator: " › ") }
}

public struct NoteSummary: Sendable, Hashable {
    /// Notes' own id (`x-coredata://…/ICNote/p123`).
    public var id: String
    /// The short id tools show and take: stable for a note, and short enough to copy without mistakes.
    public var handle: String
    public var title: String
    public var folderId: String
    public var created: Date?
    public var modified: Date?
    /// Locked notes can't be read until the person unlocks them in Notes.
    public var locked: Bool
}

/// Every account, folder and note (no bodies) at one moment.
public struct NotesIndex: Sendable {
    public var folders: [NotesFolder]
    /// Newest first.
    public var notes: [NoteSummary]
    public var takenAt: Date
    private var foldersById: [String: NotesFolder]
    private var notesByHandle: [String: NoteSummary]

    init(folders: [NotesFolder], notes: [NoteSummary], takenAt: Date) {
        self.folders = folders
        self.notes = notes
        self.takenAt = takenAt
        foldersById = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        notesByHandle = Dictionary(notes.map { ($0.handle, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public func folder(_ id: String) -> NotesFolder? { foldersById[id] }

    /// A note by its short id, or by Notes' own id.
    public func note(_ handleOrId: String) -> NoteSummary? {
        notesByHandle[handleOrId] ?? notesByHandle[AppleNotes.handle(for: handleOrId)].flatMap { $0.id == handleOrId ? $0 : nil }
    }

    public func isRecentlyDeleted(_ note: NoteSummary) -> Bool { folder(note.folderId)?.isRecentlyDeleted ?? false }

    /// Notes outside Recently Deleted.
    public var live: [NoteSummary] { notes.filter { !isRecentlyDeleted($0) } }

    public func place(of note: NoteSummary) -> String { folder(note.folderId)?.place ?? "Notes" }

    /// Whether the account holding `note` has a Recently Deleted folder. Only then does deleting a
    /// note move it there (an IMAP notes account deletes for good).
    public func canMoveToRecentlyDeleted(_ note: NoteSummary) -> Bool {
        guard let account = folder(note.folderId)?.accountName else { return false }
        return folders.contains { $0.isRecentlyDeleted && $0.accountName == account }
    }
}

/// A whole note, read for the model or for copying.
public struct FetchedNote: Sendable, Hashable {
    public var id: String
    public var title: String
    public var folderId: String
    public var folderName: String
    public var created: Date?
    public var modified: Date?
    public var locked: Bool
    /// The body as Markdown, without the title line. Empty for a locked note.
    public var markdown: String
    /// Attachment file names; the files themselves stay in Notes.
    public var attachments: [String]
    /// The body was longer than the cap and was cut.
    public var truncated: Bool
}

/// Sidefolk's view of Apple Notes, through `AppleEventsRunner` (DECISIONS D38). Reading is the
/// default; `remove` exists only for "move", after the tools' own checks and a high-risk approval.
public final class AppleNotes: Sendable {
    /// Lets a page or two of a list, and a copy right after it, reuse one index.
    static let indexLifetime: TimeInterval = 120
    /// Below the executor's 90 s, so a stuck Notes ends as a clear message rather than a timeout.
    static let timeout: TimeInterval = 75

    private let runner: any AppleEventsRunner
    private let clock: any Clock
    private let cache = Mutex<NotesIndex?>(nil)

    public init(runner: any AppleEventsRunner, clock: any Clock = SystemClock()) {
        self.runner = runner
        self.clock = clock
    }

    /// The short id for one of Notes' ids: "n" and 8 hex digits of its SHA-256.
    public static func handle(for id: String) -> String {
        "n" + ExtensionHash.sha256(Data(id.utf8)).prefix(8)
    }

    /// The last index taken, if any, without asking Notes (for approval summaries).
    public var cachedIndex: NotesIndex? { cache.withLock { $0 } }

    public func index(refresh: Bool = false) async throws -> NotesIndex {
        let now = clock.now
        if !refresh, let cached = cache.withLock({ $0 }), now.timeIntervalSince(cached.takenAt) < Self.indexLifetime {
            return cached
        }
        let raw = try await runner.run(NotesScripts.index, name: "notes.index", params: .object([:]), app: .notes, timeout: Self.timeout)
        let index = Self.buildIndex(raw, takenAt: now)
        cache.withLock { $0 = index }
        return index
    }

    /// The first `maxChars` characters of each note's text and its attachment count, by Notes' id.
    public func snippets(_ ids: [String], maxChars: Int) async throws -> [String: (text: String, attachments: Int)] {
        guard !ids.isEmpty else { return [:] }
        let raw = try await runner.run(NotesScripts.snippets, name: "notes.snippets",
                                       params: ["ids": .array(ids.map { .string($0) }), "maxChars": .number(Double(maxChars))],
                                       app: .notes, timeout: Self.timeout)
        var out: [String: (text: String, attachments: Int)] = [:]
        for (id, value) in raw.objectValue ?? [:] {
            out[id] = (value["text"]?.stringValue ?? "", value["attachments"]?.intValue ?? 0)
        }
        return out
    }

    /// Whole notes, in the order asked; a note that no longer exists is left out.
    /// - Parameter maxChars: cap on each note's HTML, before it becomes Markdown.
    public func fetch(_ ids: [String], maxChars: Int) async throws -> [FetchedNote] {
        guard !ids.isEmpty else { return [] }
        let raw = try await runner.run(NotesScripts.fetch, name: "notes.fetch",
                                       params: ["ids": .array(ids.map { .string($0) }), "maxChars": .number(Double(maxChars))],
                                       app: .notes, timeout: Self.timeout)
        return (raw.arrayValue ?? []).compactMap { item -> FetchedNote? in
            guard item["missing"]?.boolValue != true, let id = item["id"]?.stringValue else { return nil }
            let names = (item["attachments"]?.arrayValue ?? []).map { $0.stringValue ?? "" }
            let cids = (item["cids"]?.arrayValue ?? []).map { $0.stringValue ?? "" }
            var byCid: [String: String] = [:]
            for (cid, name) in zip(cids, names) where !cid.isEmpty { byCid[cid] = name }
            let title = item["name"]?.stringValue ?? ""
            let markdown = NoteMarkdown.convert(item["html"]?.stringValue ?? "", attachments: byCid)
            return FetchedNote(
                id: id, title: title, folderId: item["folder"]?.stringValue ?? "", folderName: item["folderName"]?.stringValue ?? "",
                created: Self.date(item["created"]), modified: Self.date(item["modified"]), locked: item["locked"]?.boolValue ?? false,
                markdown: NoteMarkdown.droppingTitle(title, from: markdown),
                attachments: names.map { $0.isEmpty ? "attachment" : $0 }, truncated: item["truncated"]?.boolValue ?? false)
        }
    }

    public enum Removal: Sendable, Equatable {
        /// Seen in Recently Deleted afterwards.
        case movedToRecentlyDeleted
        /// Deleted, but Notes no longer reports where it is.
        case removed
        /// It was already gone.
        case missing
    }

    /// Deletes notes the caller already checked. Notes moves them to its Recently Deleted folder.
    public func remove(_ ids: [String]) async throws -> [String: Removal] {
        guard !ids.isEmpty else { return [:] }
        defer { cache.withLock { $0 = nil } }
        let raw = try await runner.run(NotesScripts.remove, name: "notes.remove", params: ["ids": .array(ids.map { .string($0) })],
                                       app: .notes, timeout: Self.timeout)
        var out: [String: Removal] = [:]
        for item in raw.arrayValue ?? [] {
            guard let id = item["id"]?.stringValue else { continue }
            switch item["status"]?.stringValue {
            case "missing": out[id] = .missing
            case "deleted" where NotesTrash.names.contains(item["folder"]?.stringValue ?? ""): out[id] = .movedToRecentlyDeleted
            default: out[id] = .removed
            }
        }
        return out
    }

    // MARK: Building the index

    static func buildIndex(_ raw: JSONValue, takenAt: Date) -> NotesIndex {
        var accounts: [String: String] = [:]
        var accountOrder: [String] = []
        for a in raw["accounts"]?.arrayValue ?? [] {
            guard let id = a["id"]?.stringValue else { continue }
            accounts[id] = a["name"]?.stringValue ?? "Notes"
            accountOrder.append(id)
        }
        struct RawFolder { var id: String; var name: String; var account: String; var parents: [String] }
        let rawFolders: [RawFolder] = (raw["folders"]?.arrayValue ?? []).compactMap { f in
            guard let id = f["id"]?.stringValue else { return nil }
            return RawFolder(id: id, name: f["name"]?.stringValue ?? "", account: f["account"]?.stringValue ?? "",
                             parents: (f["parents"]?.arrayValue ?? []).compactMap(\.stringValue))
        }
        let byId = Dictionary(rawFolders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // A folder may be listed by its parent and, depending on how Notes reports nesting, by its
        // grandparents and its account too: its parent is the deepest folder that lists it.
        var depthMemo: [String: Int] = [:]
        func depth(_ id: String, _ guardSet: Set<String> = []) -> Int {
            if let d = depthMemo[id] { return d }
            guard let f = byId[id], !guardSet.contains(id) else { return 0 }
            let d = f.parents.isEmpty ? 0 : 1 + (f.parents.map { depth($0, guardSet.union([id])) }.max() ?? 0)
            depthMemo[id] = d
            return d
        }
        func parent(of f: RawFolder) -> String? { f.parents.filter { byId[$0] != nil }.max { depth($0) < depth($1) } }
        func path(of f: RawFolder) -> [String] {
            var names = [f.name]
            var current = parent(of: f)
            var seen: Set<String> = [f.id]
            while let id = current, let p = byId[id], seen.insert(id).inserted {
                names.insert(p.name, at: 0)
                current = parent(of: p)
            }
            return names
        }

        // A note listed under several folders belongs to the deepest.
        var noteFolder: [String: (folder: String, depth: Int, raw: JSONValue)] = [:]
        var noteOrder: [String] = []
        for n in raw["notes"]?.arrayValue ?? [] {
            guard let id = n["id"]?.stringValue, let folder = n["folder"]?.stringValue else { continue }
            let d = depth(folder)
            if let existing = noteFolder[id] {
                if d > existing.depth { noteFolder[id] = (folder, d, n) }
            } else {
                noteFolder[id] = (folder, d, n)
                noteOrder.append(id)
            }
        }
        var counts: [String: Int] = [:]
        for entry in noteFolder.values { counts[entry.folder, default: 0] += 1 }

        let trash = NotesTrash.names
        var folders = rawFolders.map { f in
            let isTop = parent(of: f) == nil
            return NotesFolder(id: f.id, name: f.name, accountName: accounts[f.account] ?? "Notes", parentId: parent(of: f), path: path(of: f),
                               isRecentlyDeleted: isTop && trash.contains(f.name), noteCount: counts[f.id] ?? 0)
        }
        // Accounts in Notes' order, then each account's folders as a tree (parents before children).
        let rank = Dictionary(accountOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let accountOf = Dictionary(rawFolders.map { ($0.id, $0.account) }, uniquingKeysWith: { a, _ in a })
        folders.sort { a, b in
            let ra = rank[accountOf[a.id] ?? ""] ?? .max, rb = rank[accountOf[b.id] ?? ""] ?? .max
            if ra != rb { return ra < rb }
            if a.isRecentlyDeleted != b.isRecentlyDeleted { return !a.isRecentlyDeleted }
            return a.path.lexicographicallyPrecedes(b.path) { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        let notes = noteOrder.compactMap { id -> NoteSummary? in
            guard let entry = noteFolder[id] else { return nil }
            let n = entry.raw
            return NoteSummary(id: id, handle: handle(for: id), title: n["name"]?.stringValue ?? "", folderId: entry.folder,
                               created: date(n["created"]), modified: date(n["modified"]), locked: n["locked"]?.boolValue ?? false)
        }.sorted { a, b in
            let ma = a.modified ?? .distantPast, mb = b.modified ?? .distantPast
            return ma != mb ? ma > mb : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        return NotesIndex(folders: folders, notes: notes, takenAt: takenAt)
    }

    /// JavaScript dates arrive as ISO 8601 text with milliseconds.
    static func date(_ value: JSONValue?) -> Date? {
        guard let text = value?.stringValue else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// The names Notes gives its Recently Deleted folder: English, and Notes' own word in the Mac's
/// language, read from Notes' strings (a folder's name is all scripting tells apart). If the strings
/// can't be read, only the English name is known, and removing notes is refused rather than risked.
enum NotesTrash {
    static let names: Set<String> = load()

    static func load(table: String = "/System/Library/PrivateFrameworks/NotesShared.framework/Resources/Localizable.loctable",
                     preferences: [String] = Locale.preferredLanguages) -> Set<String> {
        var names: Set<String> = ["Recently Deleted"]
        guard let data = FileManager.default.contents(atPath: table),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return names }
        for language in Bundle.preferredLocalizations(from: Array(plist.keys), forPreferences: preferences) {
            if let name = (plist[language] as? [String: Any])?["Recently Deleted"] as? String, !name.isEmpty { names.insert(name) }
        }
        return names
    }
}
