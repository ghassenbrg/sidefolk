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

    /// One thing in Today's queue (D58): a question Guard is waiting on, an agent session that needs you, something
    /// Sidefolk noticed, or a step nobody answered in time.
    enum Decision: Identifiable {
        case approval(ApprovalRequest)
        case session(AgentSession)
        case attention(AttentionItem)
        case skipped(SkippedStep)

        var id: String {
            switch self {
            case .approval(let r): "a" + r.id
            case .session(let s): "s" + s.id
            case .attention(let a): "n" + a.id
            case .skipped(let s): "k" + s.id
            }
        }
    }

    private(set) var attention: [AttentionItem] = []
    /// Guard's questions still waiting (D58). The Ask panel shows them too; an answer in either place answers both.
    private(set) var approvals: [ApprovalRequest] = []
    /// Icons and names of the extensions whose tools are asking.
    private(set) var extensionLooks: [String: ExtensionLook] = [:]
    /// Steps nobody answered in time; they wait here with "Run it now" (D37).
    private(set) var skipped: [SkippedStep] = []
    /// What the last "Run it now" did, said under the list.
    private(set) var skippedRun: Result<String, UserFacingError>?
    /// Full access shows as a banner at the top of Now while it is on (D37).
    private(set) var mode: GuardMode = .askOncePerKind
    private(set) var sessionsNeedingYou: [AgentSession] = []
    private(set) var reminders: [Reminder] = []
    /// The notes and tasks reminders belong to (D49), by id.
    private(set) var linked: [String: NotebookItem] = [:]
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

    var needsYouCount: Int { approvals.count + attention.count + sessionsNeedingYou.count + skipped.count }

    /// What needs you, soonest deadline first: Guard's questions stop on their own, so they lead; then sessions,
    /// what Sidefolk noticed, and steps already skipped.
    var queue: [Decision] {
        approvals.sorted { ($0.expiresAt ?? .distantFuture, $0.createdAt) < ($1.expiresAt ?? .distantFuture, $1.createdAt) }
            .map(Decision.approval)
            + sessionsNeedingYou.map(Decision.session) + attention.map(Decision.attention) + skipped.map(Decision.skipped)
    }

    /// Reminders still to come today, for the header.
    var remindersLeftToday: Int { groups().first { $0.day == .today }?.reminders.count ?? 0 }

    func reload() async {
        let rt = runtime
        approvals = await rt.broker.pending()
        if approvals.contains(where: { $0.extensionId.map { extensionLooks[$0] == nil } ?? false }) {
            extensionLooks = Dictionary(await services.extensions().map { ($0.id, $0.look) }, uniquingKeysWith: { a, _ in a })
        }
        skipped = await rt.executor.skipped.list()
        mode = (try? await rt.permissions.policy())?.mode ?? .askOncePerKind
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
        let items = (try? await rt.notebook.items(ids: Array(Set(reminders.compactMap(\.itemId))))) ?? []
        linked = Dictionary(items.filter { $0.deletedAt == nil }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
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
                                       title: r.title, detail: done ? String(localized: "state.done", defaultValue: "Done", comment: "Checkbox and status: the task or reminder is finished") : String(localized: "Reminded you"),
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

    /// The person's click answers the question the step's card asked; Guard still checks everything
    /// else, and asks in the Ask panel if something changed since.
    func runSkipped(_ step: SkippedStep) async {
        guard let out = await runtime.executor.runSkipped(id: step.id) else {
            skippedRun = .failure(UserFacingError("That step can't run anymore. Nothing was changed."))
            await reload()
            return
        }
        if let problem = out.problem {
            skippedRun = .failure(problem)
        } else {
            skippedRun = .success(out.activity.card?.title ?? out.activity.summary)
        }
        await reload()
    }

    func dismissSkipped(_ step: SkippedStep) async {
        skippedRun = nil
        await runtime.executor.skipped.dismiss(step.id)
        await reload()
    }

    /// The banner's way out of Full access, back to the default.
    func turnOffFullAccess() async {
        try? await runtime.permissions.updatePolicy { $0.mode = .askOncePerKind }
        runtime.events.changed(.permissions)
        await reload()
    }

    /// Answers Guard's question, the same way the Ask panel's card does.
    func answer(_ request: ApprovalRequest, _ decision: ApprovalDecision) async {
        await runtime.broker.resolve(id: request.id, decision: decision)
        await reload()
    }

    func respond(_ item: AttentionItem, action: String?) async {
        await runtime.attention.respond(id: item.id, actionId: action)
        await reload()
    }

    func openSession(_ session: AgentSession) { services.openSession(session) }

    /// The note or task a reminder belongs to, while it is in the notebook.
    func item(of r: Reminder) -> NotebookItem? { r.itemId.flatMap { linked[$0] } }

    func open(_ item: NotebookItem) { services.open(item: item) }

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
