import Foundation

// Reading Apple Notes: a page of the list, then whole notes. Both are medium risk (another app's
// private data) and return untrusted text: a note can hold anything, including words aimed at the model.

struct AppleNotesListTool: Tool {
    let notes: AppleNotes
    let ledger: AppleNotesLedger
    static let pageSize = 50
    /// Folders named in one result; a library with more is summarised.
    static let folderLines = 40

    let spec = ToolSpec(
        name: "applenotes.list", title: String(localized: "List Apple Notes"),
        description: """
            List the user's Apple Notes (the Notes app on this Mac): accounts and folders with how many notes each holds, \
            then one page of notes, newest first, with id, title, folder, modified date and the start of the text. Page \
            through with `offset`. Narrow with `folder` (name or path) or `query` (words in the title); `not_copied` leaves \
            out notes already copied into the notebook. Read whole notes with applenotes_read; copy them into the notebook \
            with applenotes_copy. Notes' Recently Deleted folder is never listed.
            """,
        inputSchema: Schema.object([
            "folder": Schema.string("Only this folder, by name or path, e.g. “Recipes” or “iCloud › Recipes”"),
            "query": Schema.string("Words the note's title must contain"),
            "not_copied": Schema.boolean("Leave out notes already copied into the notebook"),
            "offset": Schema.integer("How many notes to skip (for the next page)", minimum: 0, maximum: 1_000_000),
            "limit": Schema.integer("Notes per page (default and maximum 50)", minimum: 1, maximum: 50),
        ]),
        risk: .medium, capabilities: [.macApps], category: .notes, mutates: false)

    func summary(for input: JSONValue) -> String {
        let limit = input.clampedInt("limit", default: Self.pageSize, in: 1...Self.pageSize)
        if let folder = input.string("folder") {
            return String(localized: "Read the titles, folders and dates of up to \(limit) notes in “\(folder.clipped(60))” in Apple Notes")
        }
        if let query = input.string("query") {
            return String(localized: "Read the titles, folders and dates of up to \(limit) Apple Notes whose title has “\(query.clipped(60))”")
        }
        return String(localized: "Read the titles, folders and dates of up to \(limit) of your Apple Notes")
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let limit = input.clampedInt("limit", default: Self.pageSize, in: 1...Self.pageSize)
        let offset = input.clampedInt("offset", default: 0, in: 0...1_000_000)
        let query = try input.optionalText("query", limit: 200)
        let folderName = try input.optionalText("folder", limit: 300)
        return try await MacAppAccess.run(.notes) {
            // A new list starts from what Notes holds now; later pages reuse it so they line up.
            let index = try await notes.index(refresh: offset == 0)
            let copied = try await ledger.load()
            let visible = index.folders.filter { !$0.isRecentlyDeleted }
            let trashed = index.notes.count - index.live.count

            var lines = [Self.header(index: index, visible: visible, trashed: trashed)]
            let copiedLive = index.live.filter { copied[$0.id] != nil }.count
            if copiedLive > 0 { lines.append("Already copied into the notebook: \(copiedLive) of \(index.live.count).") }

            var scope = "all folders"
            var pool = index.live
            if let folderName {
                let matches = Self.folders(matching: folderName, in: visible)
                guard !matches.isEmpty else {
                    lines.append("No folder matches “\(MacAppAccess.line(folderName, 80))”. Use one of the folders above.")
                    return ToolResult(text: lines.joined(separator: "\n"),
                                      card: ResultCard(kind: .list, title: String(localized: "No such folder in Apple Notes"),
                                                       subtitle: folderName.clipped(60)),
                                      untrusted: true)
                }
                let ids = Set(matches.map(\.id))
                pool = pool.filter { ids.contains($0.folderId) }
                scope = matches.map { MacAppAccess.line($0.place, 80) }.joined(separator: ", ")
            }
            if let query {
                pool = pool.filter { $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                scope += ", title has “\(MacAppAccess.line(query, 60))”"
            }
            if input["not_copied"]?.boolValue == true {
                pool = pool.filter { copied[$0.id] == nil }
                scope += ", not copied yet"
            }

            let page = Array(pool.dropFirst(offset).prefix(limit))
            guard !page.isEmpty else {
                lines.append(pool.isEmpty ? "No notes in \(scope)." : "No notes after offset \(offset) in \(scope) (there are \(pool.count)).")
                return ToolResult(text: lines.joined(separator: "\n"),
                                  card: ResultCard(kind: .list, title: String(localized: "No matching Apple Notes")), untrusted: true)
            }
            let snippets = try await notes.snippets(page.filter { !$0.locked }.map(\.id), maxChars: 240)
            lines.append("Notes \(offset + 1)–\(offset + page.count) of \(pool.count) (\(scope)), newest first:")
            for note in page {
                lines += Self.lines(for: note, index: index, snippet: snippets[note.id], copied: copied[note.id] != nil)
            }
            if offset + page.count < pool.count {
                lines.append("More: call again with offset \(offset + page.count).")
            }
            return ToolResult(
                text: lines.joined(separator: "\n"),
                card: ResultCard(kind: .list, title: String(localized: "\(pool.count) notes in Apple Notes"),
                                 subtitle: String(localized: "Showing \(offset + 1)–\(offset + page.count)")),
                untrusted: true)
        }
    }

    static func header(index: NotesIndex, visible: [NotesFolder], trashed: Int) -> String {
        var header = "Apple Notes on this Mac: \(ToolFormat.count(index.live.count, "note")) in \(ToolFormat.count(visible.count, "folder"))"
        header += trashed > 0 ? " (Recently Deleted, with \(ToolFormat.count(trashed, "note")), is left out)." : "."
        let shown = visible.prefix(folderLines).map { "\(MacAppAccess.line($0.place, 80)) (\($0.noteCount))" }
        var folders = "Folders: " + shown.joined(separator: "; ")
        if visible.count > folderLines { folders += "; and \(visible.count - folderLines) more (ask for one by name)" }
        return header + "\n" + folders
    }

    static func lines(for note: NoteSummary, index: NotesIndex, snippet: (text: String, attachments: Int)?, copied: Bool) -> [String] {
        let title = note.title.isEmpty ? "(untitled)" : "“\(MacAppAccess.line(note.title, 100))”"
        var meta = [MacAppAccess.line(index.place(of: note), 80)]
        if let modified = note.modified { meta.append("modified \(ToolFormat.day(modified))") }
        if let n = snippet?.attachments, n > 0 { meta.append(ToolFormat.count(n, "attachment")) }
        if note.locked { meta.append("locked (can't be read or copied)") }
        if copied { meta.append("copied") }
        var out = ["- \(note.handle) \(title) · " + meta.joined(separator: " · ")]
        if let text = snippet?.text {
            let start = MacAppAccess.line(NoteMarkdown.droppingTitle(note.title, from: text), 120)
            if !start.isEmpty { out.append("  " + start) }
        }
        return out
    }

    /// Folders whose path, place or name is `query`, with "›", "/" or ">" between levels and any case.
    static func folders(matching query: String, in folders: [NotesFolder]) -> [NotesFolder] {
        func key(_ parts: [String]) -> String { parts.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.joined(separator: "/") }
        let wanted = key(query.components(separatedBy: CharacterSet(charactersIn: "›/>")))
        return folders.filter { f in
            key([f.accountName] + f.path) == wanted || key(f.path) == wanted || f.name.lowercased() == wanted
        }
    }
}

struct AppleNotesReadTool: Tool {
    let notes: AppleNotes
    static let maxNotes = 5
    /// Untrusted results are cut at 20 KB; the notes share a little less than that.
    static let budget = 18_000

    let spec = ToolSpec(
        name: "applenotes.read", title: String(localized: "Read Apple Notes"),
        description: """
            Read up to 5 Apple Notes in full, by the ids applenotes_list shows: title, folder, dates, attachment names and \
            the text as Markdown. Long notes are cut. Attachments themselves are not read. To put notes in the notebook use \
            applenotes_copy, which keeps the whole text without you rewriting it.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(["ids": .object([
                "type": "array", "description": "Note ids from applenotes_list, e.g. [\"n1a2b3c4d\"]",
                "items": Schema.string("A note id"), "maxItems": .number(Double(maxNotes)),
            ])]),
            "required": ["ids"],
            "additionalProperties": false,
        ]),
        risk: .medium, capabilities: [.macApps], category: .notes, mutates: false)

    func summary(for input: JSONValue) -> String {
        let ids = input.textList("ids") ?? []
        let places = AppleNotesPlaces.folders(of: ids, index: notes.cachedIndex)
        if places.isEmpty { return String(localized: "Read \(ids.count) notes from Apple Notes") }
        return String(localized: "Read \(ids.count) notes from Apple Notes in \(Wording.names(places))")
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let ids = try MacAppAccess.ids(input, max: Self.maxNotes)
        return try await MacAppAccess.run(.notes) {
            let (found, unknown) = try await AppleNotesPlaces.resolve(ids, notes: notes)
            let fetched = try await notes.fetch(found.map(\.id), maxChars: 400_000)
            let index = try await notes.index()
            let share = Self.budget / max(fetched.count, 1)
            var parts: [String] = []
            for note in fetched {
                let handle = AppleNotes.handle(for: note.id)
                var lines = ["Note \(handle) “\(MacAppAccess.line(note.title, 120))”"]
                var meta = [MacAppAccess.line(index.folder(note.folderId)?.place ?? note.folderName, 80)]
                if let created = note.created { meta.append("created \(ToolFormat.day(created))") }
                if let modified = note.modified { meta.append("modified \(ToolFormat.day(modified))") }
                lines.append(meta.joined(separator: " · "))
                if !note.attachments.isEmpty {
                    lines.append("Attachments (not read): " + note.attachments.map { MacAppAccess.line($0, 60) }.joined(separator: ", "))
                }
                if note.locked {
                    lines.append("It is locked: the user has to unlock it in Notes before it can be read.")
                } else {
                    let (body, cut) = ExternalText.prepare(note.markdown, limit: share)
                    lines.append(body.isEmpty ? "(no text besides the title)" : body)
                    if cut || note.truncated { lines.append("[cut: the note is longer]") }
                }
                parts.append(lines.joined(separator: "\n"))
            }
            let missing = unknown + found.filter { f in !fetched.contains { $0.id == f.id } }.map(\.handle)
            if !missing.isEmpty {
                parts.append("Not found (deleted, or list the notes again): " + missing.map { MacAppAccess.line($0, 40) }.joined(separator: ", "))
            }
            let first = fetched.first.map { $0.title.clipped(60) } ?? ""
            return ToolResult(
                text: parts.joined(separator: "\n\n---\n\n"),
                card: ResultCard(kind: .list, title: String(localized: "Read \(fetched.count) notes from Apple Notes"), subtitle: first),
                untrusted: true)
        }
    }
}

/// Finding the notes a call names, and where they are, for the Apple Notes tools.
enum AppleNotesPlaces {
    /// The notes the ids name, in order, and the ids nothing matched. Asks Notes again when an id
    /// isn't in the last index (the list was a while ago, or Sidefolk restarted since).
    static func resolve(_ ids: [String], notes: AppleNotes) async throws -> (found: [NoteSummary], unknown: [String]) {
        var index = try await notes.index()
        if ids.contains(where: { index.note($0) == nil }) { index = try await notes.index(refresh: true) }
        var found: [NoteSummary] = []
        var unknown: [String] = []
        for id in ids {
            if let note = index.note(id) { found.append(note) } else { unknown.append(id) }
        }
        return (found, unknown)
    }

    /// Distinct folder names of the notes the ids name, from the last index (no Apple Event).
    static func folders(of ids: [String], index: NotesIndex?) -> [String] {
        guard let index else { return [] }
        var names: [String] = []
        for id in ids {
            guard let note = index.note(id), let folder = index.folder(note.folderId) else { continue }
            let name = folder.name.clipped(40)
            if !names.contains(name) { names.append(name) }
        }
        return names.map { "“\($0)”" }
    }
}
