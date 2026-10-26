import Foundation

/// The person's open reminders in Apple's Reminders app, read through Apple Events (DECISIONS D38).
/// Read only: Sidefolk's own reminders stay Sidefolk's (`reminders.create`), so nothing here writes.
public struct AppleReminders: Sendable {
    public struct Item: Sendable, Hashable {
        public var title: String
        public var list: String
        public var due: Date?
        /// Due on a day, at no particular time.
        public var allDay: Bool
        /// 0 none, 1–4 high, 5 medium, 6–9 low (Reminders' own scale).
        public var priority: Int
        public var flagged: Bool
        public var notes: String
    }

    public struct Snapshot: Sendable {
        /// Every list with how many open reminders it holds, in Reminders' order.
        public var lists: [(name: String, open: Int)]
        /// Open reminders, soonest due first; those without a date last.
        public var items: [Item]
    }

    static let timeout: TimeInterval = 75
    private let runner: any AppleEventsRunner

    public init(runner: any AppleEventsRunner) { self.runner = runner }

    public func open() async throws -> Snapshot {
        let raw = try await runner.run(RemindersScripts.open, name: "reminders.open", params: .object([:]), app: .reminders,
                                       timeout: Self.timeout)
        var names: [String: String] = [:]
        var lists: [(name: String, open: Int)] = []
        for l in raw["lists"]?.arrayValue ?? [] {
            guard let id = l["id"]?.stringValue else { continue }
            let name = l["name"]?.stringValue ?? ""
            names[id] = name
            lists.append((name, l["open"]?.intValue ?? 0))
        }
        let items = (raw["reminders"]?.arrayValue ?? []).map { r -> Item in
            let allDay = AppleNotes.date(r["allday"])
            return Item(title: r["name"]?.stringValue ?? "", list: names[r["list"]?.stringValue ?? ""] ?? "",
                        due: allDay ?? AppleNotes.date(r["due"]), allDay: allDay != nil, priority: r["priority"]?.intValue ?? 0,
                        flagged: r["flagged"]?.boolValue ?? false, notes: r["body"]?.stringValue ?? "")
        }.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?) where x != y: x < y
            case (_?, nil): true
            case (nil, _?): false
            default: a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }
        return Snapshot(lists: lists, items: items)
    }
}

enum RemindersScripts {
    /// Every list, and each list's open reminders with their title, dates, priority, flag and the start
    /// of their notes. Property names follow /System/Applications/Reminders.app/Contents/Resources/Reminders.sdef.
    static let open = """
        function main(app, params) {
          const lists = [], reminders = [];
          const ls = app.lists;
          const ids = ls.id(), names = ls.name();
          for (let i = 0; i < ids.length; i++) {
            const open = ls.byId(ids[i]).reminders.whose({ completed: false });
            const rIds = open.id();
            lists.push({ id: ids[i], name: names[i], open: rIds.length });
            if (rIds.length === 0) continue;
            const titles = open.name(), due = open.dueDate(), allday = open.alldayDueDate(), priority = open.priority(),
                  flagged = open.flagged(), body = open.body();
            for (let j = 0; j < rIds.length; j++) {
              reminders.push({ list: ids[i], name: titles[j], due: due[j], allday: allday[j], priority: priority[j],
                               flagged: flagged[j], body: body[j] ? String(body[j]).slice(0, 300) : '' });
            }
          }
          return { lists: lists, reminders: reminders };
        }
        """
}

struct AppleRemindersListTool: Tool {
    let reminders: AppleReminders
    static let pageSize = 50

    let spec = ToolSpec(
        name: "applereminders.list", title: String(localized: "List Apple Reminders"),
        description: """
            List the open reminders in the user's Reminders app (Apple's, not Sidefolk's own reminders): every list with \
            its count, then open reminders soonest due first, with list, due date, priority, flag and the start of their \
            notes. Narrow with `list` or `query`; page with `offset`. Read only: to have Sidefolk remind the user, use \
            reminders_create.
            """,
        inputSchema: Schema.object([
            "list": Schema.string("Only this list, by name, e.g. “Groceries”"),
            "query": Schema.string("Words the reminder's title must contain"),
            "offset": Schema.integer("How many reminders to skip (for the next page)", minimum: 0, maximum: 100_000),
            "limit": Schema.integer("Reminders per page (default and maximum 50)", minimum: 1, maximum: 50),
        ]),
        risk: .medium, capabilities: [.macApps], category: .time, mutates: false)

    func summary(for input: JSONValue) -> String {
        if let list = input.string("list") { return String(localized: "Read your open reminders in the list “\(list.clipped(60))” in Apple Reminders") }
        return String(localized: "Read your open reminders in Apple Reminders")
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let limit = input.clampedInt("limit", default: Self.pageSize, in: 1...Self.pageSize)
        let offset = input.clampedInt("offset", default: 0, in: 0...100_000)
        let listName = try input.optionalText("list", limit: 200)
        let query = try input.optionalText("query", limit: 200)
        return try await MacAppAccess.run(.reminders) {
            let snapshot = try await reminders.open()
            let total = snapshot.items.count
            var lines = ["Apple Reminders on this Mac: \(ToolFormat.count(total, "open reminder")) in \(ToolFormat.count(snapshot.lists.count, "list")): "
                         + snapshot.lists.prefix(40).map { "\(MacAppAccess.line($0.name, 60)) (\($0.open))" }.joined(separator: "; ")]
            var pool = snapshot.items
            var scope = "all lists"
            if let listName {
                pool = pool.filter { $0.list.caseInsensitiveCompare(listName) == .orderedSame }
                scope = "list “\(MacAppAccess.line(listName, 60))”"
            }
            if let query {
                pool = pool.filter { $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                scope += ", title has “\(MacAppAccess.line(query, 60))”"
            }
            let page = Array(pool.dropFirst(offset).prefix(limit))
            if page.isEmpty {
                lines.append(pool.isEmpty ? "No open reminders in \(scope)." : "No reminders after offset \(offset) in \(scope) (there are \(pool.count)).")
            } else {
                lines.append("Open reminders \(offset + 1)–\(offset + page.count) of \(pool.count) (\(scope)), soonest due first:")
                for item in page { lines += Self.lines(for: item) }
                if offset + page.count < pool.count { lines.append("More: call again with offset \(offset + page.count).") }
            }
            return ToolResult(text: lines.joined(separator: "\n"),
                              card: ResultCard(kind: .list, title: String(localized: "\(total) open reminders in Apple Reminders")),
                              untrusted: true)
        }
    }

    static func lines(for item: AppleReminders.Item) -> [String] {
        var meta = [MacAppAccess.line(item.list, 60)]
        if let due = item.due { meta.append("due " + (item.allDay ? ToolFormat.day(due) : ToolFormat.minute(due))) }
        switch item.priority {
        case 1...4: meta.append("high priority")
        case 5: meta.append("medium priority")
        case 6...9: meta.append("low priority")
        default: break
        }
        if item.flagged { meta.append("flagged") }
        var out = ["- “\(MacAppAccess.line(item.title, 120))” · " + meta.joined(separator: " · ")]
        let notes = MacAppAccess.line(item.notes, 160)
        if !notes.isEmpty { out.append("  " + notes) }
        return out
    }
}
