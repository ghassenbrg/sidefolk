import Foundation
import Observation
import SidefolkCore

/// What is live right now: things waiting for the user, reminders, watchers, running work and
/// what just finished. Reads come from the stores; actions that need an engine go through the facade.
@MainActor @Observable
final class NowModel {
    struct ReminderGroup: Identifiable {
        enum Day { case today, tomorrow, later }
        var day: Day
        var reminders: [Reminder]
        var id: Day { day }

        var title: String {
            switch day {
            case .today: String(localized: "Today")
            case .tomorrow: String(localized: "Tomorrow")
            case .later: String(localized: "Later")
            }
        }
    }

    struct RecentEntry: Identifiable {
        var id: String
        var symbol: String
        var folk: String
        var title: String
        var detail: String
        var date: Date
    }

    enum Snooze: CaseIterable {
        case tenMinutes, oneHour, tomorrowMorning
    }

    private(set) var attention: [AttentionItem] = []
    private(set) var sessionsNeedingYou: [AgentSession] = []
    private(set) var reminders: [Reminder] = []
    private(set) var watchers: [Watcher] = []
    /// Reports: values told every few seconds or minutes, with their latest readings.
    private(set) var reports: [Watcher] = []
    private(set) var readings: [String: WatchReading] = [:]
    private(set) var jobs: [Job] = []
    private(set) var workingSessions: [AgentSession] = []
    private(set) var recent: [RecentEntry] = []

    var newTitle = ""
    var newWhen = ""
    private(set) var newError: UserFacingError?
    private(set) var adding = false

    let services: AppServices
    private var runtime: SidefolkRuntime { services.runtime }

    init(services: AppServices) {
        self.services = services
    }

    var needsYouCount: Int { attention.count + sessionsNeedingYou.count }

    func reload() async {
        let rt = runtime
        let open = await rt.attention.open()
        let live = (try? await rt.sessions.live()) ?? []
        let needing = live.filter { $0.state == .needsYou }
        // A session that needs you may also have posted an attention item; show it once, as the session.
        let sessionIds = Set(needing.map(\.id))
        // Only things that need a decision: informational notices (gentle) live in Recently, not here.
        attention = open.filter { $0.level >= .attention && !($0.refKind == "session" && sessionIds.contains($0.refId ?? "")) }
        sessionsNeedingYou = needing
        workingSessions = live.filter { $0.state == .working }
        reminders = (try? await rt.reminderStore.pending()) ?? []
        // From the engine, not the database: routine check times are only saved every few minutes.
        let watching = await rt.watchers.list().filter { [.active, .paused, .error].contains($0.state) }
        watchers = watching.filter { $0.mode != .report }
        reports = watching.filter { $0.mode == .report }.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        readings = Dictionary(await rt.watchers.latestReadings().map { ($0.watcherId, $0) }, uniquingKeysWith: { a, _ in a })
        jobs = (try? await rt.jobs.running()) ?? []
        recent = await loadRecent()
    }

    private func loadRecent() async -> [RecentEntry] {
        let rt = runtime
        var entries: [RecentEntry] = []
        for r in (try? await rt.reminderStore.recentlyFinished(limit: 10)) ?? [] where r.state != .cancelled {
            let done = r.state == .done
            let at = done ? r.updatedAt : (r.lastFiredAt ?? r.updatedAt)
            entries.append(RecentEntry(id: "r" + r.id, symbol: done ? "checkmark.circle" : "alarm", folk: "tempo",
                                       title: r.title, detail: done ? String(localized: "Done") : String(localized: "Reminded you"),
                                       date: at))
        }
        for j in (try? await rt.jobs.recent(limit: 20)) ?? [] where j.state != .running {
            let at = j.endedAt ?? j.startedAt
            let took = TimeText.span(at.timeIntervalSince(j.startedAt))
            let detail = switch j.state {
            case .succeeded: String(localized: "Finished after \(took)")
            case .failed: j.exitCode.map { String(localized: "Failed with exit code \(String($0)) after \(took)") }
                ?? String(localized: "Failed after \(took)")
            case .cancelled: String(localized: "Stopped after \(took)")
            case .running: ""
            }
            entries.append(RecentEntry(id: "j" + j.id, symbol: j.state == .failed ? "xmark.octagon" : "terminal",
                                       folk: "byte", title: j.title, detail: detail, date: at))
        }
        for w in (try? await rt.watcherStore.all()) ?? [] where w.state == .triggered {
            entries.append(RecentEntry(id: "w" + w.id, symbol: "binoculars", folk: "scout", title: w.title,
                                       detail: String(localized: "Spotted the change"), date: w.updatedAt))
        }
        for s in (try? await rt.sessions.recent(limit: 20)) ?? [] where s.state == .finished {
            let end = s.endedAt ?? s.updatedAt
            let took = TimeText.span(end.timeIntervalSince(s.startedAt))
            entries.append(RecentEntry(id: "s" + s.id, symbol: "checkmark.seal", folk: "byte",
                                       title: Describe.session(s), detail: String(localized: "Finished after \(took)"), date: end))
        }
        return Array(entries.sorted { $0.date > $1.date }.prefix(10))
    }

    /// Pending reminders grouped Today / Tomorrow / Later (overdue ones count as today).
    func groups(now: Date = Date()) -> [ReminderGroup] {
        let cal = Calendar.current
        let startOfTomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)
        let startOfLater = cal.date(byAdding: .day, value: 1, to: startOfTomorrow) ?? startOfTomorrow
        var today: [Reminder] = [], tomorrow: [Reminder] = [], later: [Reminder] = []
        for r in reminders {
            let due = r.nextDue ?? r.fireAt
            if due < startOfTomorrow { today.append(r) } else if due < startOfLater { tomorrow.append(r) } else { later.append(r) }
        }
        return [ReminderGroup(day: .today, reminders: today), ReminderGroup(day: .tomorrow, reminders: tomorrow),
                ReminderGroup(day: .later, reminders: later)].filter { !$0.reminders.isEmpty }
    }

    // MARK: Actions

    func respond(_ item: AttentionItem, action: String?) async {
        await runtime.attention.respond(id: item.id, actionId: action)
        await reload()
    }

    func openSession(_ session: AgentSession) { services.openSession(session) }

    func complete(_ r: Reminder) async {
        await services.completeReminder(r.id)
        await reload()
    }

    func snooze(_ r: Reminder, _ option: Snooze) async {
        await services.snoozeReminder(r.id, until: date(for: option))
        await reload()
    }

    func edit(_ r: Reminder, title: String, when: String) async -> UserFacingError? {
        let error = await services.editReminder(r.id, title: title, when: when)
        await reload()
        return error
    }

    func cancel(_ r: Reminder) async {
        await services.cancelReminder(r.id)
        await reload()
    }

    func date(for option: Snooze, now: Date = Date()) -> Date {
        switch option {
        case .tenMinutes: return now.addingTimeInterval(600)
        case .oneHour: return now.addingTimeInterval(3600)
        case .tomorrowMorning:
            let cal = Calendar.current
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
            return cal.date(bySettingHour: runtime.settings.current.morningHour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
    }

    func title(for option: Snooze) -> String {
        switch option {
        case .tenMinutes: String(localized: "10 minutes")
        case .oneHour: String(localized: "1 hour")
        case .tomorrowMorning: String(localized: "Tomorrow morning (\(TimeText.hour(runtime.settings.current.morningHour)))")
        }
    }

    /// The same where no Snooze menu says it: "Snooze 10 minutes".
    func snoozeTitle(for option: Snooze) -> String {
        switch option {
        case .tenMinutes: String(localized: "Snooze 10 minutes")
        case .oneHour: String(localized: "Snooze 1 hour")
        case .tomorrowMorning: String(localized: "Snooze until tomorrow morning (\(TimeText.hour(runtime.settings.current.morningHour)))")
        }
    }

    var canAddReminder: Bool {
        !adding && !newTitle.trimmingCharacters(in: .whitespaces).isEmpty && !newWhen.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func addReminder() async {
        guard canAddReminder else { return }
        adding = true
        newError = await services.createReminder(title: newTitle.trimmingCharacters(in: .whitespaces),
                                                 when: newWhen.trimmingCharacters(in: .whitespaces))
        adding = false
        if newError == nil {
            newTitle = ""
            newWhen = ""
            await reload()
        }
    }

    func clearError() { newError = nil }

    func pause(_ w: Watcher) async {
        await services.pauseWatcher(w.id)
        await reload()
    }

    func resume(_ w: Watcher) async {
        await services.resumeWatcher(w.id)
        await reload()
    }

    /// A report read a new value: only its row changes, nothing is reloaded.
    func update(_ reading: WatchReading) {
        guard reports.contains(where: { $0.id == reading.watcherId }) else { return }
        readings[reading.watcherId] = reading
    }

    func checkNow(_ w: Watcher) async {
        await services.checkWatcherNow(w.id)
        await reload()
    }

    func stop(_ w: Watcher) async {
        await services.stopWatcher(w.id)
        await reload()
    }
}
