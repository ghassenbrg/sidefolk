import Foundation

/// Adding, changing and deleting events in the person's Mac calendars (D95). Every change, the person's own drag in
/// the Calendar included, goes through Guard and History with an Undo. Never offered while the person hasn't allowed
/// changes; never a whole series (one time of it), and never an event other people are invited to (changing it would
/// tell them), nor one on a calendar that can't be changed.
enum CalendarWriteTools {
    static func make(reader: CalendarReader, platform: any PlatformBridge, settings: SettingsStore) -> [any Tool] {
        let shared = Shared(reader: reader, platform: platform, settings: settings)
        return [CalendarCreateTool(shared: shared), CalendarUpdateTool(shared: shared), CalendarDeleteTool(shared: shared)]
    }

    struct Shared: Sendable {
        let reader: CalendarReader
        let platform: any PlatformBridge
        let settings: SettingsStore
        var calendar: Calendar { .autoupdatingCurrent }

        func checkOn() throws {
            guard reader.isOn else {
                throw ToolError.unavailable("The user's calendar is off. They can show it in Sidefolk's Settings › Trust › Your calendar.")
            }
            guard reader.writesOn else {
                throw ToolError.unavailable("Sidefolk isn't allowed to change the user's calendar. They can allow it in Settings › Trust › Your calendar.")
            }
        }

        /// The event to change, as it is now, if Sidefolk may change it.
        func changeable(_ id: String) async throws -> CalendarEvent {
            guard let event = await reader.event(id: id) else {
                throw UserFacingError("That event isn't on your calendar anymore.")
            }
            guard event.writable else {
                throw UserFacingError("That calendar can't be changed from here.", recovery: "Open the event in Calendar to change it.")
            }
            guard event.attendees.isEmpty else {
                throw UserFacingError("Other people are invited to that event, so it changes in Calendar, where you see who is told.",
                                      recovery: "Open the event in Calendar to change it.")
            }
            return event
        }

        /// A time: an exact ISO 8601 moment (what the Calendar writes), else the words people type ("friday 3pm").
        func date(_ text: String, now: Date) throws -> Date {
            if let exact = try? Date(text, strategy: .iso8601) { return exact }
            guard let parsed = WhenParser(calendar: calendar, settings: settings.current).parse(text, now: now) else {
                throw UserFacingError("I didn't understand “\(text.clipped(60))” as a time.",
                                      recovery: "Use an ISO date and time such as 2026-11-12T09:00:00, or words like “friday 3pm”.")
            }
            return parsed.date
        }

        /// A calendar by name or id, among those that take changes; nil for the default one.
        func calendarId(_ wanted: String?) async throws -> String? {
            guard let wanted else { return nil }
            let all = await reader.calendars() ?? []
            let writable = all.filter(\.writable)
            if let found = writable.first(where: { $0.id == wanted })
                ?? writable.first(where: { $0.title.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                return found.id
            }
            let names = writable.map(\.title).joined(separator: ", ")
            throw UserFacingError(verbatim: String(localized: "There's no calendar called “\(wanted.clipped(40))” that can be changed."),
                                  recovery: names.isEmpty ? nil : String(localized: "These can: \(names)."))
        }

        /// All-day events cover whole days: from the first's start to the start of the day after the last.
        func wholeDays(_ draft: inout CalendarDraft) {
            guard draft.allDay else { return }
            draft.start = calendar.startOfDay(for: draft.start)
            let last = calendar.startOfDay(for: max(draft.start, draft.end.addingTimeInterval(-1)))
            draft.end = calendar.date(byAdding: .day, value: 1, to: last) ?? draft.start.addingTimeInterval(86400)
        }

        func check(_ draft: CalendarDraft) throws {
            guard !draft.title.isEmpty else { throw UserFacingError("An event needs a title.") }
            guard draft.end > draft.start else { throw UserFacingError("An event has to end after it starts.") }
            guard draft.end.timeIntervalSince(draft.start) <= 366 * 86400 else { throw UserFacingError("An event can last a year at most.") }
        }

        /// "Tue 3 Nov, 13:00–14:00", "Tue 3 Nov, all day".
        func when(_ draft: CalendarDraft, now: Date) -> String {
            draft.allDay ? TimeFormat.day(draft.start, now: now, calendar: calendar) + ", " + String(localized: "all day")
                : TimeFormat.when(draft.start, now: now, calendar: calendar) + "–" + TimeFormat.clock(draft.end, calendar: calendar)
        }

        func line(_ event: CalendarEvent) -> String {
            "“\(event.title)” (id \(event.id)), \(when(event.draft, now: Date()))"
        }
    }
}

private let fieldSchemas: [String: JSONValue] = [
    "title": Schema.string("The event's title."),
    "start": Schema.string("When it starts: ISO 8601 (2026-11-12T09:00:00) or words like “friday 3pm”."),
    "end": Schema.string("When it ends, the same way. Defaults to an hour after the start, or the same day when all day."),
    "all_day": Schema.boolean("A whole-day event."),
    "calendar": Schema.string("Which calendar, by name (“Work”). Defaults to the user's default calendar."),
    "location": Schema.string("Where it is."),
    "notes": Schema.string("Notes."),
]

struct CalendarCreateTool: Tool {
    let shared: CalendarWriteTools.Shared

    let spec = ToolSpec(
        name: "calendar.create", title: String(localized: "Add to your calendar"),
        description: """
            Add an event to the user's Mac calendar. Only when the user asks for an event on their calendar; a reminder \
            (something to be told about) is reminders.create.
            """,
        inputSchema: Schema.object(fieldSchemas, required: ["title", "start"]),
        risk: .medium, capabilities: [.calendarWrite], category: .time, mutates: true)

    func summary(for input: JSONValue) -> String {
        String(localized: "Add “\((input.string("title") ?? "").clipped(60))” to your calendar")
            + (input.string("start").map { " · \($0.clipped(40))" } ?? "")
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        try shared.checkOn()
        let title = try input.requiredText("title", limit: 500)
        let start = try shared.date(try input.requiredText("start", limit: 200), now: context.now)
        let allDay = input["all_day"]?.boolValue ?? false
        let end = try input.optionalText("end", limit: 200).map { try shared.date($0, now: context.now) }
            ?? (allDay ? start : start.addingTimeInterval(3600))
        var draft = CalendarDraft(title: title, start: start, end: end, allDay: allDay,
                                  calendarId: try await shared.calendarId(input.string("calendar")),
                                  location: try input.optionalText("location", limit: 500), notes: try input.optionalText("notes", limit: 4_000))
        shared.wholeDays(&draft)
        try shared.check(draft)
        let event = try await shared.platform.createCalendarEvent(draft)
        let platform = shared.platform, id = event.id
        return ToolResult(
            text: "Added \(shared.line(event)) to the user's \(event.calendar) calendar.",
            card: ResultCard(kind: .info, title: String(localized: "Added to your calendar"),
                             subtitle: "\(event.title.clipped(60)) · \(shared.when(draft, now: context.now))", refId: event.id),
            undo: UndoAction(label: String(localized: "Removed “\(event.title.clipped(40))” from your calendar")) {
                try await platform.deleteCalendarEvent(id: id)
            })
    }
}

struct CalendarUpdateTool: Tool {
    let shared: CalendarWriteTools.Shared

    let spec = ToolSpec(
        name: "calendar.update", title: String(localized: "Change an event"),
        description: """
            Change an event on the user's Mac calendar: its title, time, calendar, place or notes. `id` comes from \
            calendar.today. Only this one time of a repeating event changes. Events with other people invited can't be \
            changed here.
            """,
        inputSchema: Schema.object(fieldSchemas.merging(["id": Schema.string("The event's id.")]) { a, _ in a }, required: ["id"]),
        risk: .medium, capabilities: [.calendarWrite], category: .time, mutates: true)

    func summary(for input: JSONValue) -> String {
        if let title = input.string("title") { return String(localized: "Change the event “\(title.clipped(60))”") }
        return String(localized: "Change an event on your calendar") + (input.string("start").map { " · \($0.clipped(40))" } ?? "")
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        try shared.checkOn()
        let id = try input.requiredText("id", limit: 400)
        let before = try await shared.changeable(id)
        var draft = before.draft
        if let title = try input.optionalText("title", limit: 500) { draft.title = title }
        if let allDay = input["all_day"]?.boolValue { draft.allDay = allDay }
        if let start = try input.optionalText("start", limit: 200) {
            // A new start alone keeps the length.
            let length = draft.end.timeIntervalSince(draft.start)
            draft.start = try shared.date(start, now: context.now)
            draft.end = draft.start.addingTimeInterval(length)
        }
        if let end = try input.optionalText("end", limit: 200) { draft.end = try shared.date(end, now: context.now) }
        if let calendar = input.string("calendar") { draft.calendarId = try await shared.calendarId(calendar) }
        if input["location"] != nil { draft.location = input.string("location") }
        if input["notes"] != nil { draft.notes = input.string("notes") }
        shared.wholeDays(&draft)
        try shared.check(draft)
        let after = try await shared.platform.updateCalendarEvent(id: id, to: draft)
        let platform = shared.platform, old = before.draft, newId = after.id
        return ToolResult(
            text: "Changed \(shared.line(after)).",
            card: ResultCard(kind: .info, title: String(localized: "Changed on your calendar"),
                             subtitle: "\(after.title.clipped(60)) · \(shared.when(draft, now: context.now))", refId: after.id),
            undo: UndoAction(label: String(localized: "Put “\(before.title.clipped(40))” back as it was")) {
                _ = try await platform.updateCalendarEvent(id: newId, to: old)
            })
    }
}

struct CalendarDeleteTool: Tool {
    let shared: CalendarWriteTools.Shared

    let spec = ToolSpec(
        name: "calendar.delete", title: String(localized: "Delete an event"),
        description: """
            Delete an event from the user's Mac calendar (`id` from calendar.today). Only this one time of a repeating \
            event. Events with other people invited can't be deleted here.
            """,
        inputSchema: Schema.object(["id": Schema.string("The event's id.")], required: ["id"]),
        risk: .high, capabilities: [.calendarWrite], category: .time, mutates: true)

    func summary(for input: JSONValue) -> String { String(localized: "Delete an event from your calendar") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        try shared.checkOn()
        let event = try await shared.changeable(try input.requiredText("id", limit: 400))
        try await shared.platform.deleteCalendarEvent(id: event.id)
        // The whole event is kept, so Undo puts it back (a repeating event's time comes back on its own).
        let platform = shared.platform, copy = event.draft
        return ToolResult(
            text: "Deleted \(shared.line(event)).",
            card: ResultCard(kind: .info, title: String(localized: "Deleted from your calendar"),
                             subtitle: "\(event.title.clipped(60)) · \(shared.when(copy, now: context.now))"),
            undo: UndoAction(label: String(localized: "Put “\(event.title.clipped(40))” back on your calendar")) {
                _ = try await platform.createCalendarEvent(copy)
            })
    }
}
