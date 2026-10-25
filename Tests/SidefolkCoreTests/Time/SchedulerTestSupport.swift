import Foundation
@testable import SidefolkCore

/// A scheduler wired to an in-memory database, a hand-moved clock and the real attention center.
/// "Restarting the app" is `restarted()`: a new scheduler over the same database.
struct SchedulerEnv {
    let env: TestEnv
    let attention: AttentionCenter
    let settings: SettingsStore
    let scheduler: ReminderScheduler
    let brief: MorningBrief
    let store: ReminderStore
    let calendar: Calendar
    let prompts = PromptLog()

    var clock: ManualClock { env.clock }

    init(now: Date = TimeTest.wednesday10, calendar: Calendar = TimeTest.utc, withPrompts: Bool = false) async throws {
        env = try TestEnv(now: now)
        self.calendar = calendar
        attention = AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock)
        settings = await SettingsStore(db: env.db, events: env.events)
        store = ReminderStore(env.db)
        brief = MorningBrief(db: env.db, attention: attention, settings: settings, clock: env.clock, calendar: calendar)
        let log = prompts
        var runner: ReminderScheduler.PromptRunner?
        if withPrompts { runner = { reminder in await log.add(reminder) } }
        scheduler = ReminderScheduler(
            store: store, attention: attention, events: env.events, settings: settings, clock: env.clock, calendar: calendar,
            brief: brief, runPrompt: runner
        )
    }

    /// A new scheduler over the same data, as after quitting and reopening the app.
    func restarted() -> ReminderScheduler {
        ReminderScheduler(store: store, attention: attention, events: env.events, settings: settings, clock: env.clock,
                          calendar: calendar, brief: brief, runPrompt: nil)
    }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date { TimeTest.date(y, m, d, h, min, in: calendar) }

    /// Everything posted to the attention center so far, oldest first.
    func posted() async -> [AttentionItem] {
        ((try? await AttentionStore(env.db).recent(limit: 200)) ?? []).sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    func reminder(_ id: String) async -> Reminder? { try? await store.reminder(id: id) }
}

actor PromptLog {
    private(set) var reminders: [Reminder] = []
    func add(_ r: Reminder) { reminders.append(r) }
}
