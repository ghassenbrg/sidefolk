import AppKit
import SidefolkCore

/// What the Calendar changes (D66, D97), each through the path the rest of the app uses: a reminder's time is
/// `moveReminder`; adding, removing and every change to the Mac's calendar run as the person's own calls through
/// ToolExecutor, so Guard sees them, History lists them and ⌘Z takes them back.
extension CalendarModel {
    // MARK: Reminders

    /// Moves a reminder's next time, as dragging it on Today's line does, and lets ⌘Z put it back while that time is
    /// still to come. Never into the past.
    func move(_ reminder: Reminder, from due: Date, to target: Date, undo: UndoManager?) async {
        guard target > Date() else {
            problem = UserFacingError("That time has already passed.", recovery: "Pick a time in the future.")
            return
        }
        guard abs(target.timeIntervalSince(due)) >= 60 else { return }
        problem = await services.moveReminder(reminder.id, to: target)
        await reload()
        guard problem == nil, let undo else { return }
        undo.registerUndo(withTarget: self) { model in
            guard due > Date() else { return }
            Task { @MainActor in
                _ = await model.services.moveReminder(reminder.id, to: due)
                await model.reload()
            }
        }
        undo.setActionName(String(localized: "Move Reminder"))
    }

    /// A thing dropped on a day (keeping its time of day) or at a time: a reminder's next time, or an event (keeping
    /// its length).
    func drop(_ entryId: String, on day: Date, at time: Date? = nil, undo: UndoManager?) async {
        guard let entry = entries.first(where: { $0.id == entryId && $0.movable }) else { return }
        let target: Date
        if let time {
            target = time
        } else {
            let clock = calendar.dateComponents([.hour, .minute], from: entry.start)
            target = calendar.date(bySettingHour: clock.hour ?? 9, minute: clock.minute ?? 0, second: 0, of: day) ?? day
        }
        await move(entry, to: target, undo: undo)
    }

    /// Moves a thing to start at `start`: a reminder's time, or an event with its length kept.
    func move(_ entry: Entry, to start: Date, undo: UndoManager?) async {
        switch entry {
        case .reminder(let o) where o.isNext:
            await move(o.reminder, from: o.at, to: start, undo: undo)
        case .event(let e) where e.changeable:
            guard abs(start.timeIntervalSince(e.start)) >= 60 else { return }
            var draft = e.draft
            draft.start = start
            draft.end = start.addingTimeInterval(e.end.timeIntervalSince(e.start))
            change(e, to: draft, undo: undo, action: String(localized: "Move Event"))
        default:
            return
        }
    }

    /// The bottom edge of an event dragged: its end, a quarter hour after its start at the least.
    func resize(_ event: CalendarEvent, end: Date, undo: UndoManager?) {
        let end = max(end, event.start.addingTimeInterval(15 * 60))
        guard event.changeable, abs(end.timeIntervalSince(event.end)) >= 60 else { return }
        var draft = event.draft
        draft.end = end
        change(event, to: draft, undo: undo, action: String(localized: "Change Event Length"))
    }

    // MARK: The Mac's events (D97)

    /// An event changed as the editor or a drag says, once the person allowed changes.
    func change(_ event: CalendarEvent, to draft: CalendarDraft, undo: UndoManager?, action: String = String(localized: "Change Event")) {
        var input: [String: JSONValue] = [
            "id": .string(event.id), "title": .string(draft.title), "start": .string(draft.start.formatted(.iso8601)),
            "end": .string(draft.end.formatted(.iso8601)), "all_day": .bool(draft.allDay),
            "location": .string(draft.location ?? ""), "notes": .string(draft.notes ?? ""),
        ]
        if let id = draft.calendarId, id != event.calendarId { input["calendar"] = .string(id) }
        whenWritesAllowed { [weak self] in
            await self?.call("calendar.update", .object(input), undo: undo, action: action)
        }
    }

    func openInCalendar(_ event: CalendarEvent) { MacCalendar.open(event) }

    /// A task due on the Calendar, done from there (D117): as its own tool, so it's in History and Undo takes it back.
    func finish(_ item: NotebookItem, undo: UndoManager?) async {
        _ = await call("notes.update", ["id": .string(item.id), "status": "done"], undo: undo, action: String(localized: "Mark Done"))
    }

    // MARK: Adding

    /// What a new thing on the Calendar can be.
    enum NewKind: String, CaseIterable, Identifiable {
        case reminder, task, event
        var id: Self { self }
    }

    /// Adds what the editor describes: a reminder (`reminders.create`) or a task in a collection with its time
    /// (`notes.save` with `remind`), at the when field's words (a repeat included); or an event in one of the person's
    /// calendars (`calendar.create`, D97) from `start` to `end`.
    func add(_ kind: NewKind, title: String, when: String, start: Date, end: Date, allDay: Bool, calendarId: String?,
             collection: String?, location: String?, undo: UndoManager?) async -> UserFacingError? {
        let words = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let when = when.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return nil }
        switch kind {
        case .reminder:
            return await call("reminders.create", ["title": .string(words), "when": .string(when)],
                              undo: undo, action: String(localized: "New Reminder"))
        case .task:
            var input: [String: JSONValue] = ["text": .string(words), "kind": "task"]
            if !when.isEmpty { input["remind"] = .string(when) }
            if let collection { input["collection"] = .string(collection) }
            return await call("notes.save", .object(input), undo: undo, action: String(localized: "New Task"))
        case .event:
            var input: [String: JSONValue] = [
                "title": .string(words), "start": .string(start.formatted(.iso8601)), "end": .string(end.formatted(.iso8601)),
                "all_day": .bool(allDay),
            ]
            if let calendarId { input["calendar"] = .string(calendarId) }
            if let location = location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty { input["location"] = .string(location) }
            guard writesOn else {
                // The sheet asks first; the editor closes, and the event is added once the person says yes.
                whenWritesAllowed { [weak self] in
                    _ = await self?.call("calendar.create", .object(input), undo: undo, action: String(localized: "New Event"))
                }
                return nil
            }
            return await call("calendar.create", .object(input), undo: undo, action: String(localized: "New Event"))
        }
    }

    /// Where a double-click on a day (not at a time) puts a new thing: the morning, or the next hour today.
    func newTime(on day: Date) -> Date {
        let morning = calendar.date(bySettingHour: runtime.settings.current.morningHour, minute: 0, second: 0, of: day) ?? day
        guard calendar.isDateInToday(day), morning < Date() else { return morning }
        let next = calendar.dateInterval(of: .hour, for: Date())?.end ?? Date()
        return calendar.isDate(next, inSameDayAs: day) ? next : Date().addingTimeInterval(900)
    }

    /// Opens the editor for a new thing at a time (an hour long, as Calendar's).
    func startNew(at start: Date, end: Date? = nil, allDay: Bool = false, fromButton: Bool = false) {
        selection = nil
        inspecting = nil
        draft = CalendarNewDraft(start: start, end: end ?? start.addingTimeInterval(3600), allDay: allDay, fromButton: fromButton)
    }

    // MARK: Removing

    /// Delete: a reminder's time comes off the calendar (a task keeps its place in the Notebook), an event is deleted
    /// (one time of a repeating one); ⌘Z puts either back.
    func delete(_ entry: Entry, undo: UndoManager?) {
        switch entry {
        case .reminder(let o):
            Task { await call("reminders.cancel", ["id": .string(o.reminder.id)], undo: undo, action: String(localized: "Remove Reminder")) }
        case .event(let e) where e.changeable:
            whenWritesAllowed { [weak self] in
                await self?.call("calendar.delete", ["id": .string(e.id)], undo: undo, action: String(localized: "Delete Event"))
            }
        default:
            return
        }
        if selection == entry.id { selection = nil }
        if inspecting == entry.id { inspecting = nil }
    }

    func complete(_ reminder: Reminder) async {
        await now.complete(reminder)
        await reload()
    }

    // MARK: Running a tool as the person

    /// One call as the person's own (Guard lets their click through and logs it in History); its undo goes to ⌘Z.
    @discardableResult
    private func call(_ tool: String, _ input: JSONValue, undo: UndoManager?, action: String) async -> UserFacingError? {
        let executor = runtime.executor
        let out = await executor.execute(name: tool, input: input, caller: .user)
        problem = out.problem
        await reload()
        guard out.isOK else { return out.problem }
        if let undo {
            let id = out.activity.id
            undo.registerUndo(withTarget: self) { model in
                Task { @MainActor in
                    do {
                        if try await executor.undo.undo(id) == nil {
                            model.problem = UserFacingError("That can't be undone anymore.")
                        }
                    } catch {
                        model.problem = UserFacingError("I couldn't undo that.")
                    }
                    await model.reload()
                }
            }
            undo.setActionName(action)
        }
        return nil
    }
}
