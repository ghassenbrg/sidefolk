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
            watches are running. Use it for "what's on my plate today" or "what do I have today". With day, that day's \
            reminders and the tasks due then.
            """,
            inputSchema: Schema.object(["day": Schema.string("Another day (\"tomorrow\", \"friday\", \"dec 5\" or ISO 8601). Leave out for today.")]),
            risk: .low, capabilities: [.time, .notebook], category: .time, mutates: false, external: true)
    }

    func summary(for input: JSONValue) -> String {
        input.string("day").map { String(localized: "Read your reminders and tasks for \($0.clipped(40))") } ?? String(localized: "Read today's reminders and open tasks")
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let calendar = reminders.calendar
        if let day = input.string("day"), let window = try DateWindow.read(from: day, to: day, parser: reminders.parser(), now: context.now),
           let start = window.start, !calendar.isDate(start, inSameDayAs: context.now) {
            return try await another(DateWindow.day(start, calendar: calendar), day: start, calendar: calendar, context: context)
        }
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
        let dueToday = try await notebook.dueTasks(from: start, to: end)
        if !dueToday.isEmpty {
            lines.append("Tasks due today (\(dueToday.count)):")
            lines += dueToday.map { "- " + NoteFormat.line($0, collections: collections, snippet: false) }
        }
        lines.append(tasks.isEmpty ? "No open tasks." : "Open tasks, newest first (\(found.count > tasks.count ? "\(tasks.count)+" : "\(tasks.count)")):")
        let next = await NoteFormat.reminders(tasks, notebook: notebook)
        lines += tasks.map { "- " + NoteFormat.line($0, collections: collections, snippet: false, reminder: next[$0.id]) }
        lines.append("Watching \(ToolFormat.count(watching, "thing")).")

        let subtitle = [String(localized: "\(today.count) reminders today"), String(localized: "\(tasks.count) open tasks")].joined(separator: " · ")
        let detail = today.prefix(5).map { "\(TimeFormat.clock($0.nextDue ?? $0.fireAt, calendar: calendar)) \($0.title)" }.joined(separator: "\n")
        // Titles another agent or app wrote are their words, not the user's (T2, T3).
        return ToolResult(text: lines.joined(separator: "\n"),
                          card: ResultCard(kind: .list, title: String(localized: "Today"), subtitle: subtitle, detail: detail.isEmpty ? nil : detail),
                          untrusted: today.contains(where: ReminderTools.Shared.isForeign) || NoteFormat.hasForeign(tasks + dueToday, collections: collections))
    }

    /// Another day has no running count of open tasks or watches: just what comes then.
    private func another(_ window: DateWindow, day: Date, calendar: Calendar, context: ToolContext) async throws -> ToolResult {
        let coming = await reminders.scheduler.upcoming().filter { window.contains($0.nextDue ?? $0.fireAt) }
            .sorted { ($0.nextDue ?? $0.fireAt) < ($1.nextDue ?? $1.fireAt) }
        let due = try await notebook.dueTasks(from: window.start ?? day, to: window.end ?? day)
        let collections = try await NotebookCollections.byId(notebook)
        let items = await reminders.items(for: coming)
        var lines = ["\(TimeFormat.full(day, calendar: calendar).split(separator: " ").prefix(4).joined(separator: " ")):"]
        lines.append(coming.isEmpty ? "No reminders." : "Reminders (\(coming.count)):")
        lines += coming.map { "- " + reminders.line($0, item: $0.itemId.flatMap { items[$0] }) }
        lines.append(due.isEmpty ? "No tasks due." : "Tasks due (\(due.count)):")
        lines += due.map { "- " + NoteFormat.line($0, collections: collections, snippet: false) }
        let shown = coming.prefix(5).map { "\(TimeFormat.clock($0.nextDue ?? $0.fireAt, calendar: calendar)) \($0.title)" } + due.prefix(5).map(\.title)
        return ToolResult(text: lines.joined(separator: "\n"),
                          card: ResultCard(kind: .list, title: TimeFormat.day(day, now: context.now, calendar: calendar),
                                           subtitle: String(localized: "\(coming.count) reminders"), detail: shown.isEmpty ? nil : shown.joined(separator: "\n")),
                          untrusted: coming.contains(where: ReminderTools.Shared.isForeign) || NoteFormat.hasForeign(due, collections: collections))
    }
}
