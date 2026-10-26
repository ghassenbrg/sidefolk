import Foundation

/// The reminder tools the agent and external MCP clients can call. Times are natural language or
/// ISO 8601, parsed by `WhenParser`, so a model can pass "tomorrow morning" without doing date math.
public enum ReminderTools {
    /// - Parameter parser: called for every request so changes to the morning/afternoon/evening hours apply at once.
    public static func make(scheduler: ReminderScheduler, parser: @escaping @Sendable () -> WhenParser) -> [any Tool] {
        let shared = Shared(scheduler: scheduler, parser: parser)
        return [CreateTool(shared), ListTool(shared), CancelTool(shared), CompleteTool(shared), SnoozeTool(shared)]
    }

    /// Reads the day-part hours from the user's settings on every call.
    public static func make(scheduler: ReminderScheduler, settings: SettingsStore, calendar: Calendar = .autoupdatingCurrent) -> [any Tool] {
        make(scheduler: scheduler, parser: { WhenParser(calendar: calendar, settings: settings.current) })
    }

    // MARK: Shared pieces

    /// Active reminders one external client may keep, and all external clients together (their names
    /// are self-chosen, so the shared cap is what really bounds them).
    public static let maxActivePerExternalClient = 20
    public static let maxActiveExternal = 50

    struct Shared: Sendable {
        let scheduler: ReminderScheduler
        let parser: @Sendable () -> WhenParser
        /// Quota checks and creation run one at a time, so parallel calls can't all see room.
        let quotas = AsyncGate()

        var calendar: Calendar { parser().calendar }

        /// Titles written by anyone but the user (another agent, an extension, Sidefolk's agent in a
        /// tainted turn) are someone else's words: a result quoting them is untrusted (SECURITY T2, T3).
        static func isForeign(_ r: Reminder) -> Bool { !ContextBuilder.isUserSourced(r.source) }

        /// A time the tool can use: in the future, understood, and unambiguous enough to act on.
        func future(_ text: String, now: Date) throws -> WhenResult {
            let p = parser()
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Models often pass a bare "10 minutes" or "2 hours".
            guard let r = p.parse(clean, now: now) ?? p.parse("in " + clean, now: now) else {
                throw UserFacingError(
                    "I couldn't read “\(clean.clipped(60))” as a time.",
                    recovery: "Use something like “tomorrow 9am”, “in 20 minutes”, “friday at 3pm”, “every weekday at 9” or an ISO date such as 2025-11-12T09:00:00."
                )
            }
            if r.isExplicitInstant, r.date <= now {
                throw UserFacingError("“\(clean.clipped(60))” is in the past (\(TimeFormat.full(r.date, calendar: p.calendar))).",
                                      recovery: "Pick a time in the future.")
            }
            if r.confidence == .low {
                throw UserFacingError(
                    "“\(clean.clipped(60))” has already passed.",
                    recovery: "The next one would be \(TimeFormat.full(r.date, calendar: p.calendar)); ask the user whether that works, or pick another time."
                )
            }
            return r
        }

        /// Another agent may keep a bounded number of reminders going (T4, T24).
        func checkExternalQuota(source: String) async throws {
            let external = await scheduler.upcoming().filter { $0.source.hasPrefix("external:") }
            if external.filter({ $0.source == source }).count >= ReminderTools.maxActivePerExternalClient
                || external.count >= ReminderTools.maxActiveExternal {
                throw UserFacingError("Other agents already have as many reminders set as Sidefolk allows.",
                                      recovery: "Ask the user to cancel some first.")
            }
        }

        /// One reminder for the model, in English.
        func line(_ r: Reminder) -> String {
            var s = "\(r.id) · \(r.title)"
            if let due = r.nextDue { s += " · \(TimeFormat.full(due, calendar: calendar))" }
            if let rule = r.recurrence { s += " · \(TimeFormat.recurrenceForModel(rule))" }
            if r.state != .scheduled { s += " · \(r.state.rawValue)" }
            return s
        }

        func card(_ r: Reminder, now: Date, prefix: String? = nil) -> ResultCard {
            var parts: [String] = []
            if let due = r.nextDue { parts.append(TimeFormat.when(due, now: now, calendar: calendar)) }
            if let rule = r.recurrence { parts.append(TimeFormat.recurrence(rule, calendar: calendar)) }
            if let prefix { parts.insert(prefix, at: 0) }
            return ResultCard(kind: .reminder, title: r.title, subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "), refId: r.id)
        }

        func existing(_ input: JSONValue) async throws -> Reminder {
            guard let id = input.string("id") else { throw ToolError.invalidInput(String(localized: "“id” is required")) }
            guard let r = await scheduler.reminder(matching: id) else { throw ToolError.notFound(String(localized: "a reminder with id \(id)")) }
            return r
        }
    }

    // MARK: reminders.create

    struct CreateTool: Tool {
        let shared: Shared
        init(_ shared: Shared) { self.shared = shared }

        var spec: ToolSpec {
            ToolSpec(
                name: "reminders.create", title: String(localized: "Set a reminder"),
                description: """
                Remind the user about something at a time. `when` takes plain language ("tomorrow morning", "in 20 minutes", \
                "friday at 3pm", "every weekday at 9") or ISO 8601. Reminders survive restarts and show a bubble with Done and Snooze. \
                Only set one when the user actually asked and the time is clear; ask first if it is not.
                """,
                inputSchema: Schema.object([
                    "title": Schema.string("What to remind about, as a short phrase (\"Send the document\")."),
                    "when": Schema.string("When: natural language or ISO 8601. May include a repeat such as \"every monday at 10am\"."),
                    "recurrence": Schema.object([
                        "frequency": Schema.string("How often.", enum: Recurrence.Frequency.allCases.map(\.rawValue)),
                        "interval": Schema.integer("Every N units (default 1).", minimum: 1),
                        "weekdays": Schema.array("For weekly: ISO weekdays, 1 = Monday ... 7 = Sunday (day names work too).",
                                                 items: ["type": ["integer", "string"], "description": "Weekday", "minimum": 1, "maximum": 7]),
                        "until": Schema.string("Stop repeating after this date (natural language or ISO 8601)."),
                    ], required: ["frequency"]),
                    "notes": Schema.string("Optional extra detail shown under the title."),
                    "level": Schema.string("How loudly to interrupt. Default attention.", enum: ["gentle", "attention", "critical"]),
                ], required: ["title", "when"]),
                risk: .low, capabilities: [.time], category: .time, mutates: true, external: true
            )
        }

        func summary(for input: JSONValue) -> String {
            String(localized: "Remind you “\((input.string("title") ?? "…").clipped(80))” \(input.string("when") ?? "")")
                .trimmingCharacters(in: .whitespaces)
        }

        func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
            guard let title = input.string("title") else { throw ToolError.invalidInput(String(localized: "“title” is required")) }
            guard let whenText = input.string("when") else { throw ToolError.invalidInput(String(localized: "“when” is required")) }
            let now = context.now
            let parsed = try shared.future(whenText, now: now)
            let calendar = shared.calendar

            var date = parsed.date
            var rule = parsed.recurrence
            var anchor = parsed.anchor
            if let explicit = try recurrence(from: input["recurrence"], now: now) {
                // The first fire is the first time that fits the rule on or after the requested moment.
                guard let first = RecurrenceMath.nextOccurrence(after: parsed.date.addingTimeInterval(-1), recurrence: explicit,
                                                                anchor: parsed.date, calendar: calendar) else {
                    throw UserFacingError("That repeat ends before it starts.", recovery: "Choose a later end date.")
                }
                date = first
                anchor = parsed.date
                rule = explicit
            }

            let asked = input.string("level").map { $0.lowercased() }.flatMap(AttentionLevel.init(rawValue:)) ?? .attention
            guard asked != .ambient else { throw ToolError.invalidInput(String(localized: "“level” must be gentle, attention or critical")) }
            // Critical breaks through Quiet mode, full screen and the away hold with sound, so only the
            // user's own click sets it (SECURITY T24); agents get attention at most.
            let level = context.caller == .user ? asked : min(asked, .attention)
            // Recorded as the agent's when the turn was tainted, so a title a web page dictated is
            // never quoted to the model as the user's (T3).
            let source = context.provenanceTag
            let shared = self.shared
            let notes = input.string("notes")
            let (first, repeating, seriesAnchor) = (date, rule, anchor)
            let reminder = try await shared.quotas.run {
                if case .external = context.caller { try await shared.checkExternalQuota(source: source) }
                return try await shared.scheduler.create(title: title, at: first, recurrence: repeating, anchor: seriesAnchor,
                                                         notes: notes, level: level, source: source)
            }
            let id = reminder.id
            let scheduler = shared.scheduler
            var text = "Reminder set: “\(reminder.title)” for \(TimeFormat.full(date, calendar: calendar))"
            if let rule { text += ", repeating \(TimeFormat.recurrenceForModel(rule))" }
            if reminder.level < asked { text += ", as an ordinary alert (only the user can set critical reminders)" }
            text += ". id: \(id)"
            return ToolResult(
                text: text, card: shared.card(reminder, now: now),
                undo: UndoAction(label: String(localized: "Cancel reminder")) { _ = try await scheduler.cancel(id: id) }
            )
        }

        private func recurrence(from json: JSONValue?, now: Date) throws -> Recurrence? {
            guard let json, json.objectValue != nil else { return nil }
            guard let name = json.string("frequency")?.lowercased() else { throw ToolError.invalidInput(String(localized: "recurrence needs a “frequency”")) }
            let synonyms = ["hour": "hourly", "day": "daily", "week": "weekly", "month": "monthly", "year": "yearly", "weekday": "weekdays"]
            guard let frequency = Recurrence.Frequency(rawValue: synonyms[name] ?? name) else {
                let names = Recurrence.Frequency.allCases.map(\.rawValue).joined(separator: ", ")
                throw ToolError.invalidInput(String(localized: "recurrence frequency must be one of \(names)"))
            }
            var days: [Int] = []
            for value in json["weekdays"]?.arrayValue ?? [] {
                guard let d = Self.isoWeekday(value) else { throw ToolError.invalidInput(String(localized: "weekdays are 1 (Monday) to 7 (Sunday)")) }
                days.append(d)
            }
            var rule = Recurrence(frequency: frequency, interval: json["interval"]?.intValue ?? 1, weekdays: Array(Set(days)).sorted())
            if let untilText = json.string("until") {
                let p = shared.parser()
                guard let until = p.parse(untilText, now: now) else {
                    throw ToolError.invalidInput(String(localized: "couldn't read the end date “\(untilText.clipped(40))”"))
                }
                // A date without a time ends at the end of that day.
                rule.until = until.hasTime ? until.date : (p.calendar.date(byAdding: .day, value: 1, to: p.calendar.startOfDay(for: until.date))?.addingTimeInterval(-1) ?? until.date)
            }
            return rule
        }

        static func isoWeekday(_ value: JSONValue) -> Int? {
            if let n = value.intValue { return (1...7).contains(n) ? n : nil }
            guard let s = value.stringValue?.lowercased() else { return nil }
            if let n = WhenLexicon.weekdayShorts[s] { return n }
            return WhenLexicon.weekdays.firstIndex(of: s).map { $0 + 1 }
        }
    }

    // MARK: reminders.list

    struct ListTool: Tool {
        let shared: Shared
        init(_ shared: Shared) { self.shared = shared }

        var spec: ToolSpec {
            ToolSpec(
                name: "reminders.list", title: String(localized: "List reminders"),
                description: "List the user's upcoming reminders, soonest first, with their ids. Set include_done to also see recently finished ones.",
                inputSchema: Schema.object(["include_done": Schema.boolean("Also list recently fired, done and cancelled reminders.")]),
                risk: .low, capabilities: [.time], category: .time, mutates: false, external: true
            )
        }

        func summary(for input: JSONValue) -> String { String(localized: "List your reminders") }

        func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
            let now = context.now
            let upcoming = await shared.scheduler.upcoming()
            var lines = upcoming.map { shared.line($0) }
            let includeDone = input["include_done"]?.boolValue ?? false
            var finished: [Reminder] = []
            if includeDone {
                finished = await shared.scheduler.recent(limit: 20)
                lines += finished.map { shared.line($0) }
            }
            let count = upcoming.count
            let title = count == 0 ? String(localized: "No upcoming reminders") : String(localized: "\(count) upcoming reminders")
            let body = lines.isEmpty ? "You have no reminders." : lines.joined(separator: "\n")
            let detail = upcoming.prefix(5).map { "\(TimeFormat.when($0.nextDue ?? $0.fireAt, now: now, calendar: shared.calendar)) \($0.title)" }.joined(separator: "\n")
            return ToolResult(text: body, card: ResultCard(kind: .list, title: title, detail: detail.isEmpty ? nil : detail),
                              untrusted: (upcoming + finished).contains(where: Shared.isForeign))
        }
    }

    // MARK: reminders.cancel / complete / snooze

    struct CancelTool: Tool {
        let shared: Shared
        init(_ shared: Shared) { self.shared = shared }

        var spec: ToolSpec {
            ToolSpec(
                name: "reminders.cancel", title: String(localized: "Cancel a reminder"),
                description: "Cancel a reminder by id (from reminders.list). A repeating reminder stops repeating.",
                inputSchema: Schema.object(["id": Schema.string("The reminder's id.")], required: ["id"]),
                risk: .low, capabilities: [.time], category: .time, mutates: true
            )
        }

        func summary(for input: JSONValue) -> String { String(localized: "Cancel a reminder") }

        func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
            let r = try await shared.existing(input)
            let scheduler = shared.scheduler
            let foreign = Shared.isForeign(r)
            guard let before = try await scheduler.cancel(id: r.id), before.state != .cancelled else {
                return ToolResult(text: "“\(r.title)” was already cancelled.",
                                  card: shared.card(r, now: context.now, prefix: String(localized: "Already cancelled")),
                                  untrusted: foreign)
            }
            return ToolResult(text: "Cancelled “\(r.title)”.",
                              card: ResultCard(kind: .reminder, title: r.title, subtitle: String(localized: "Cancelled"), refId: r.id),
                              undo: UndoAction(label: String(localized: "Bring back reminder")) { try await scheduler.restore(before) },
                              untrusted: foreign)
        }
    }

    struct CompleteTool: Tool {
        let shared: Shared
        init(_ shared: Shared) { self.shared = shared }

        var spec: ToolSpec {
            ToolSpec(
                name: "reminders.complete", title: String(localized: "Mark a reminder done"),
                description: "Mark a reminder as done by id. A repeating reminder keeps repeating; use reminders.cancel to stop it.",
                inputSchema: Schema.object(["id": Schema.string("The reminder's id.")], required: ["id"]),
                risk: .low, capabilities: [.time], category: .time, mutates: true
            )
        }

        func summary(for input: JSONValue) -> String { String(localized: "Mark a reminder done") }

        func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
            let r = try await shared.existing(input)
            let scheduler = shared.scheduler
            let foreign = Shared.isForeign(r)
            // A cancelled reminder stays cancelled; saying "done" would claim a change that didn't happen.
            if r.state == .cancelled {
                throw UserFacingError("That reminder was cancelled, so there's nothing to mark done.")
            }
            guard let before = try await scheduler.complete(id: r.id) else { throw ToolError.notFound(String(localized: "a reminder with id \(r.id)")) }
            let after = await scheduler.reminder(matching: r.id) ?? r
            let next = after.nextDue.map { TimeFormat.full($0, calendar: shared.calendar) } ?? "later"
            let note = after.recurrence != nil ? "It will remind you again \(next)." : ""
            return ToolResult(text: "Marked “\(r.title)” done. \(note)".trimmingCharacters(in: .whitespaces),
                              card: ResultCard(kind: .reminder, title: r.title,
                                               subtitle: after.recurrence == nil ? String(localized: "Done") : String(localized: "Done for now"), refId: r.id),
                              undo: before == after ? nil : UndoAction(label: String(localized: "Undo done")) { try await scheduler.restore(before) },
                              untrusted: foreign)
        }
    }

    struct SnoozeTool: Tool {
        let shared: Shared
        init(_ shared: Shared) { self.shared = shared }

        var spec: ToolSpec {
            ToolSpec(
                name: "reminders.snooze", title: String(localized: "Snooze a reminder"),
                description: "Postpone a reminder to a later time. `when` is plain language (\"in 10 minutes\", \"tomorrow morning\") or ISO 8601.",
                inputSchema: Schema.object([
                    "id": Schema.string("The reminder's id."),
                    "when": Schema.string("When it should come back."),
                ], required: ["id", "when"]),
                risk: .low, capabilities: [.time], category: .time, mutates: true
            )
        }

        func summary(for input: JSONValue) -> String {
            String(localized: "Snooze a reminder \(input.string("when") ?? "")").trimmingCharacters(in: .whitespaces)
        }

        func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
            guard let whenText = input.string("when") else { throw ToolError.invalidInput(String(localized: "“when” is required")) }
            let r = try await shared.existing(input)
            let parsed = try shared.future(whenText, now: context.now)
            guard parsed.recurrence == nil else { throw ToolError.invalidInput(String(localized: "snooze takes a single time, not a repeat")) }
            let scheduler = shared.scheduler
            guard let before = try await scheduler.snooze(id: r.id, until: parsed.date), before.state == .scheduled || before.state == .snoozed || before.state == .fired else {
                throw r.state == .cancelled ? UserFacingError("“\(r.title)” was cancelled, so it can't be snoozed.")
                    : UserFacingError("“\(r.title)” is done, so it can't be snoozed.")
            }
            let when = TimeFormat.when(parsed.date, now: context.now, calendar: shared.calendar)
            return ToolResult(text: "Snoozed “\(r.title)” until \(TimeFormat.full(parsed.date, calendar: shared.calendar)).",
                              card: ResultCard(kind: .reminder, title: r.title, subtitle: String(localized: "Snoozed to \(when)"), refId: r.id),
                              undo: UndoAction(label: String(localized: "Undo snooze")) { try await scheduler.restore(before) },
                              untrusted: Shared.isForeign(r))
        }
    }
}
