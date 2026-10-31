import Foundation

/// Home › On duty (D84): everything working for the person right now, grouped by the folk who does it, from what the
/// app already runs: Scout's watches, live values (reports), Tempo's repeating reminders and routines, Byte's agent
/// sessions and commands. Extensions working in the background are the app's to add (their pages say so), and count
/// through `extra`. The rule everywhere: the count is what runs now; paused things are listed but not counted.
public struct OnDuty: Sendable, Equatable {
    public var watches: [Watcher]
    public var reports: [Watcher]
    public var repeating: [Reminder]
    public var sessions: [AgentSession]
    public var jobs: [Job]

    public init(watchers: [Watcher], reminders: [Reminder], sessions: [AgentSession], jobs: [Job]) {
        let live = watchers.filter { [.active, .paused, .error].contains($0.state) }
        watches = live.filter { $0.mode != .report }
        reports = live.filter { $0.mode == .report }
        // A reminder that comes back, or runs a prompt (a routine): one-off reminders are the day's, not duty.
        repeating = reminders.filter { ($0.recurrence != nil || $0.action?.kind == .prompt) && [.scheduled, .snoozed, .fired].contains($0.state) }
        self.sessions = sessions.filter { $0.state == .working || $0.state == .needsYou }
        self.jobs = jobs.filter { $0.state == .running }
    }

    /// Running now: watches still checking (one having trouble keeps trying, so it counts), live values, repeating
    /// reminders and routines, live agent sessions and commands.
    public func running(extra: Int = 0) -> Int {
        (watches + reports).filter { $0.state != .paused }.count + repeating.count + sessions.count + jobs.count + extra
    }

    /// Paused by the person: listed, not counted.
    public var paused: Int { (watches + reports).filter { $0.state == .paused }.count }

    /// Watches and live values that are running, for Pause all.
    public var pausable: [Watcher] { (watches + reports).filter { $0.state == .active || $0.state == .error } }

    public var isEmpty: Bool { watches.isEmpty && reports.isEmpty && repeating.isEmpty && sessions.isEmpty && jobs.isEmpty }
}
