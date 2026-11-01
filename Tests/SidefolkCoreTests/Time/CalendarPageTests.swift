import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// The Calendar page's arithmetic and colours (D97): stacked all-day bars, the continuous month's weeks and title,
/// the year's months, and calendar colours made readable in light and dark without changing their hue.
@Suite struct CalendarPageTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.firstWeekday = 2
        return c
    }

    func day(_ text: String) -> Date { try! Date(text + "T12:00:00+01:00", strategy: .iso8601) }

    @Test func allDayBarsStackLongerFirstInTheFirstFreeRow() {
        // A trip Thu–Sat, a holiday on Fri, a week-long offsite from Mon, a day on Mon.
        let lanes = CalendarGrid.lanes([(first: 3, last: 5), (first: 4, last: 4), (first: 0, last: 6), (first: 0, last: 0)])
        #expect(lanes[2] == 0) // the longest starts first, at the top
        #expect(lanes[3] == 1)
        #expect(lanes[0] == 1) // fits beside Monday's in the second row
        #expect(lanes[1] == 2)
    }

    @Test func theContinuousMonthIsWholeWeeksAndNamedByTheMonthMostOnScreen() {
        let weeks = CalendarGrid.weeks(from: day("2026-11-04"), count: 6, calendar: calendar)
        #expect(weeks.count == 42)
        #expect(calendar.component(.weekday, from: weeks[0]) == 2)
        #expect(calendar.isDate(weeks[0], inSameDayAs: day("2026-11-02")))
        let main = CalendarGrid.mainMonth(of: weeks, calendar: calendar)
        #expect(main.map { calendar.component(.month, from: $0) } == 11)
        // Scrolled three weeks on, December has most of the rows.
        let later = CalendarGrid.weeks(from: day("2026-11-23"), count: 6, calendar: calendar)
        #expect(CalendarGrid.mainMonth(of: later, calendar: calendar).map { calendar.component(.month, from: $0) } == 12)
    }

    /// The Week's reminder every 30 minutes is one pill: its next time that day, with how many times it comes.
    @Test func whatComesBackThroughTheDayIsKeptOnce() {
        let at = { (h: Double) in self.day("2026-11-01").addingTimeInterval((h - 12) * 3600) }
        let series: [String?] = ["water", nil, "water", "water", "stretch", "water"]
        let starts = [at(9), at(10), at(9.5), at(14), at(15), at(14.5)]
        let kept = CalendarGrid.oncePerDay(series: series, starts: starts, now: at(13))
        #expect(kept.map(\.index) == [1, 3, 4])
        #expect(kept.map(\.count) == [1, 4, 1])
        // All passed: the first is kept.
        #expect(CalendarGrid.oncePerDay(series: series, starts: starts, now: at(20)).map(\.index) == [0, 1, 4])
    }

    @Test func aYearIsTwelveMonths() {
        let months = CalendarGrid.yearMonths(of: day("2026-11-01"), calendar: calendar)
        #expect(months.count == 12)
        #expect(months.map { calendar.component(.month, from: $0) } == Array(1...12))
    }

    /// Apple's calendar colours on Harbor's cards: text 4.5:1 on its fill, the edge 3:1 on the card, a selected
    /// event's words 4.5:1, in light and dark; only lightness moves.
    @Test func calendarColoursReadInLightAndDarkAndKeepTheirHue() {
        let surface = ThemeTokens.harbor.colors.surfaceRaised
        for color: UInt32 in [0xFF2968, 0xFF9500, 0xFFCC00, 0x63DA38, 0x1BADF8, 0xCC73E1, 0xA2845E, 0x8E8E93, 0x5B8DEF, 0xC99A5B, 0xA68BFA] {
            for dark in [false, true] {
                let back = dark ? surface.dark : surface.light
                let c = CalendarPalette.colors(color, surface: back, dark: dark)
                #expect(ThemeCheck.contrast(c.text, c.fill) >= 4.5, "text \(String(color, radix: 16)) dark \(dark)")
                #expect(ThemeCheck.contrast(c.edge, back) >= 3, "edge \(String(color, radix: 16)) dark \(dark)")
                #expect(ThemeCheck.contrast(c.onSelected, c.selectedFill) >= 4.5, "selected \(String(color, radix: 16)) dark \(dark)")
                let hue = CalendarPalette.hsl(color).0
                for shade in [c.text, c.edge, c.selectedFill] {
                    let (h, s, l) = CalendarPalette.hsl(shade)
                    // Rounding to bytes moves a hue a little; black, white and greys have none.
                    if s > 0.1, l > 0.06, l < 0.94, CalendarPalette.hsl(color).1 > 0.1 {
                        let off = min(abs(h - hue), 360 - abs(h - hue))
                        #expect(off < 6, "hue of \(String(color, radix: 16)) moved \(off)° (dark \(dark))")
                    }
                }
            }
        }
    }
}

/// Changing the Mac's calendar (D97): only once the person allowed it, through Guard with an Undo, never an event
/// with people invited or on a calendar that can't change; the AI is offered it only then, and a turn that read
/// outside content never changes it without the person, even in Full access.
@Suite struct CalendarWriteTests {
    final class FakeCalendar: PlatformBridge, Sendable {
        let events: Mutex<[CalendarEvent]>
        let counter = Mutex(0)
        let infos = [
            CalendarInfo(id: "work", title: "Work", color: CalendarColor(hex: 0xFF9500), account: "iCloud", writable: true, isDefault: true),
            CalendarInfo(id: "home", title: "Home", color: CalendarColor(hex: 0x1BADF8), account: "iCloud", writable: true),
            CalendarInfo(id: "holidays", title: "Holidays", color: CalendarColor(hex: 0xFF2968), account: "Subscribed"),
        ]
        init(_ events: [CalendarEvent]) { self.events = Mutex(events) }

        func clipboardText() async -> String? { nil }
        func setClipboard(_ text: String) async {}
        func open(url: URL) async -> Bool { false }
        func openApplication(_ nameOrBundleId: String) async -> Bool { false }
        func reveal(path: String) async {}
        func frontmostApplication() async -> FrontmostApp? { nil }
        func calendarEvents(from: Date, to: Date) async -> [CalendarEvent]? { events.withLock { $0 } }
        func calendars() async -> [CalendarInfo]? { infos }
        func calendarEvent(id: String) async -> CalendarEvent? { events.withLock { $0.first { $0.id == id } } }
        func createCalendarEvent(_ draft: CalendarDraft) async throws -> CalendarEvent {
            let id = "n\(counter.withLock { $0 += 1; return $0 })"
            let info = infos.first { $0.id == draft.calendarId } ?? infos[0]
            let event = CalendarEvent(id: id, title: draft.title, start: draft.start, end: draft.end, allDay: draft.allDay, calendar: info.title,
                                      calendarId: info.id, location: draft.location, notes: draft.notes, writable: info.writable, alarms: draft.alarms)
            events.withLock { $0.append(event) }
            return event
        }
        func updateCalendarEvent(id: String, to draft: CalendarDraft) async throws -> CalendarEvent {
            guard var event = await calendarEvent(id: id) else { throw PlatformCalendarError.unavailable }
            event.title = draft.title
            event.start = draft.start
            event.end = draft.end
            event.allDay = draft.allDay
            event.location = draft.location
            event.notes = draft.notes
            if let id = draft.calendarId, let info = infos.first(where: { $0.id == id }) {
                event.calendarId = info.id
                event.calendar = info.title
            }
            let next = event
            events.withLock { list in list = list.map { $0.id == id ? next : $0 } }
            return next
        }
        func deleteCalendarEvent(id: String) async throws { events.withLock { $0.removeAll { $0.id == id } } }
    }

    let clock = ManualClock(TestEnv.referenceDate)
    let platform: FakeCalendar
    let runtime: SidefolkRuntime
    let at: @Sendable (Double) -> Date

    init() async throws {
        let start = Calendar.autoupdatingCurrent.startOfDay(for: TestEnv.referenceDate)
        let at: @Sendable (Double) -> Date = { start.addingTimeInterval($0 * 3600) }
        self.at = at
        platform = FakeCalendar([
            CalendarEvent(id: "lunch", title: "Lunch", start: at(13), end: at(14), calendar: "Home", calendarId: "home", writable: true, alarms: [-600]),
            CalendarEvent(id: "review", title: "Design review", start: at(15), end: at(16), calendar: "Work", calendarId: "work",
                          attendees: [CalendarAttendee(name: "Priya", answer: .accepted, organizer: true)], writable: true),
            CalendarEvent(id: "armistice", title: "Armistice Day", start: at(0), end: at(24), allDay: true, calendar: "Holidays", calendarId: "holidays"),
        ])
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-calw-\(UUID().uuidString)", isDirectory: true)
        runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: platform, clock: clock)
        await runtime.settings.update { $0.showCalendar = true }
    }

    func run(_ tool: String, _ input: JSONValue, caller: Caller = .user) async -> ToolOutcome {
        await runtime.executor.execute(name: tool, input: input, caller: caller)
    }

    @Test func nothingChangesUntilThePersonAllowsIt() async {
        let out = await run("calendar.create", ["title": "Dentist", "start": .string(at(9).formatted(.iso8601))])
        #expect(!out.isOK)
        #expect(platform.events.withLock { $0.count } == 3)
    }

    @Test func thePersonAddsMovesAndDeletesWithUndo() async throws {
        await runtime.settings.update { $0.calendarPage.writes = true }
        let made = await run("calendar.create", ["title": "Dentist", "start": .string(at(9).formatted(.iso8601)), "calendar": "Home",
                                                 "location": "12 rue des Martyrs"])
        #expect(made.isOK)
        let dentist = try #require(platform.events.withLock { $0.first { $0.title == "Dentist" } })
        #expect(dentist.calendarId == "home")
        #expect(dentist.end == at(10)) // an hour by default

        // A new start alone keeps the length.
        let moved = await run("calendar.update", ["id": "lunch", "start": .string(at(12.5).formatted(.iso8601))])
        #expect(moved.isOK)
        #expect(await platform.calendarEvent(id: "lunch")?.end == at(13.5))
        _ = try await runtime.executor.undo.undo(moved.activity.id)
        #expect(await platform.calendarEvent(id: "lunch")?.start == at(13))

        let deleted = await run("calendar.delete", ["id": "lunch"])
        #expect(deleted.isOK)
        #expect(await platform.calendarEvent(id: "lunch") == nil)
        _ = try await runtime.executor.undo.undo(deleted.activity.id)
        let back = try #require(platform.events.withLock { $0.first { $0.title == "Lunch" } })
        #expect(back.start == at(13) && back.alarms == [-600])

        _ = try await runtime.executor.undo.undo(made.activity.id)
        #expect(platform.events.withLock { $0.allSatisfy { $0.title != "Dentist" } })
        // Each change is in History.
        let logged = try await runtime.activity.recent(limit: 20).map(\.tool)
        #expect(logged.contains("calendar.create") && logged.contains("calendar.update") && logged.contains("calendar.delete"))
    }

    @Test func neverAMeetingWithPeopleNorACalendarThatCantChange() async {
        await runtime.settings.update { $0.calendarPage.writes = true }
        let meeting = await run("calendar.update", ["id": "review", "title": "Moved"])
        #expect(!meeting.isOK)
        #expect(meeting.problem?.message.contains("invited") == true)
        #expect(!(await run("calendar.delete", ["id": "armistice"])).isOK)
        #expect(!(await run("calendar.create", ["title": "X", "start": .string(at(9).formatted(.iso8601)), "calendar": "Holidays"])).isOK)
        #expect(platform.events.withLock { $0.count } == 3)
    }

    @Test func allDayEventsCoverWholeDays() async throws {
        await runtime.settings.update { $0.calendarPage.writes = true }
        #expect(await run("calendar.create", ["title": "Trip", "start": .string(at(10).formatted(.iso8601)), "all_day": true]).isOK)
        let trip = try #require(platform.events.withLock { $0.first { $0.title == "Trip" } })
        #expect(trip.start == at(0) && trip.end == Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: at(0)))
    }

    @Test func hiddenCalendarsAreLeftOutEverywhere() async throws {
        await runtime.settings.update { $0.calendarPage.hidden = ["home"] }
        let titles = try #require(await runtime.calendarReader.events(on: at(12))).map(\.title)
        #expect(!titles.contains("Lunch") && titles.contains("Design review"))
    }

    @Test func theAIIsOfferedChangesOnlyOnceAllowed() async throws {
        func offered() async throws -> Set<String> {
            let model = ScriptedModel([.turn(.reply("Done."))])
            var settings = runtime.settings.current
            settings.provider.kind = .anthropic
            let clock = self.clock
            let factory = BrainFactory { _, _ in BrainChoice(backend: LoopBackend(model: model, checkModel: "m", clock: clock), model: "test-model") }
            let context = ContextBuilder(notebook: runtime.notebook, exchanges: runtime.exchanges, clock: clock)
            let agent = AgentRuntime(executor: runtime.executor, db: runtime.db, events: runtime.events, context: context, factory: factory,
                                     settings: { [settings] in settings }, clock: clock)
            for await _ in await agent.submit(AgentRequest(text: "Add lunch tomorrow")).events {}
            return Set(try #require(model.requests.first).tools.map(\.name).filter { $0.hasPrefix("calendar") })
        }
        #expect(try await offered() == ["calendar.today"])
        await runtime.settings.update { $0.calendarPage.writes = true }
        #expect(try await offered() == ["calendar.today", "calendar.create", "calendar.update", "calendar.delete"])
    }

    /// The calendar syncs and may be shared: after outside content (an invitation's title) Full access still asks.
    @Test func aSteeredTurnNeverChangesTheCalendarWithoutThePerson() {
        let spec = ToolSpec(name: "calendar.create", title: "Add", description: "", inputSchema: .object([:]), risk: .medium,
                            capabilities: [.calendarWrite], category: .time, mutates: true)
        let engine = PermissionEngine()
        let clean = engine.evaluate(spec: spec, input: .object([:]), summary: "s", scope: .none, caller: .agent(runId: "r"), tainted: false,
                                    policy: GuardPolicy(mode: .fullAccess), grants: [], folders: [])
        #expect(clean == .allow(.fullAccess))
        guard case .ask = engine.evaluate(spec: spec, input: .object([:]), summary: "s", scope: .none, caller: .agent(runId: "r"), tainted: true,
                                          policy: GuardPolicy(mode: .fullAccess), grants: [], folders: []) else {
            Issue.record("expected the person to be asked")
            return
        }
    }
}
