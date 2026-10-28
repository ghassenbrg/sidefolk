import Foundation

/// `agenda.today`: "what's on my plate today" in one read, today's reminders, open tasks and the watches
/// running. Other agents would otherwise need `reminders.list` (every reminder, not today's) and
/// `notes.list` for tasks: two approval cards for one question (T4 asks before every read).
struct AgendaTool: Tool {
    let reminders: ReminderTools.Shared
    let notebook: NotebookStore
    let watchers: WatcherEngine

    static let tasksShown = 15

    init(scheduler: ReminderScheduler, notebook: NotebookStore, watchers: WatcherEngine, parser: @escaping @Sendable () -> WhenParser) {
        reminders = ReminderTools.Shared(scheduler: scheduler, parser: parser)
        self.notebook = notebook
        self.watchers = watchers
    }

    var spec: ToolSpec {
        ToolSpec(
            name: "agenda.today", title: String(localized: "What's on today"),
            description: """
            What's on the user's plate today: today's reminders with their times, open tasks (newest first) and how many \
            watches are running. Use it for "what's on my plate today" or "what do I have today".
            """,
            inputSchema: Schema.object([:]), risk: .low, capabilities: [.time, .notebook], category: .time, mutates: false, external: true)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Read today's reminders and open tasks") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let calendar = reminders.calendar
        let start = calendar.startOfDay(for: context.now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let today = await reminders.scheduler.upcoming()
            .filter { ($0.nextDue).map { $0 >= start && $0 < end } ?? false }
            .sorted { ($0.nextDue ?? $0.fireAt) < ($1.nextDue ?? $1.fireAt) }
        let found = try await notebook.items(kinds: [.task], status: .open, limit: Self.tasksShown + 1)
        let tasks = Array(found.prefix(Self.tasksShown))
        let watching = await watchers.list().filter { $0.state == .active }.count
        let collections = try await NotebookCollections.byId(notebook)

        var lines = ["Today, \(TimeFormat.full(context.now, calendar: calendar)):"]
        lines.append(today.isEmpty ? "No reminders today." : "Reminders today (\(today.count)):")
        let items = await reminders.items(for: today)
        lines += today.map { "- " + reminders.line($0, item: $0.itemId.flatMap { items[$0] }) }
        lines.append(tasks.isEmpty ? "No open tasks." : "Open tasks, newest first (\(found.count > tasks.count ? "\(tasks.count)+" : "\(tasks.count)")):")
        let next = await NoteFormat.reminders(tasks, notebook: notebook)
        lines += tasks.map { "- " + NoteFormat.line($0, collections: collections, snippet: false, reminder: next[$0.id]) }
        lines.append("Watching \(ToolFormat.count(watching, "thing")).")

        let subtitle = [String(localized: "\(today.count) reminders today"), String(localized: "\(tasks.count) open tasks")].joined(separator: " · ")
        let detail = today.prefix(5).map { "\(TimeFormat.clock($0.nextDue ?? $0.fireAt, calendar: calendar)) \($0.title)" }.joined(separator: "\n")
        // Titles another agent or app wrote are their words, not the user's (T2, T3).
        return ToolResult(text: lines.joined(separator: "\n"),
                          card: ResultCard(kind: .list, title: String(localized: "Today"), subtitle: subtitle, detail: detail.isEmpty ? nil : detail),
                          untrusted: today.contains(where: ReminderTools.Shared.isForeign) || NoteFormat.hasForeign(tasks, collections: collections))
    }
}
