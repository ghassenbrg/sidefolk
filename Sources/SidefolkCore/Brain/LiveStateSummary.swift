import Foundation

/// The "Right now" lines of the context: what is scheduled, watched and running. Short on purpose;
/// the model asks the tools for details. Titles set by other agents, apps or extensions are counted
/// but not quoted, so their text never reaches the system prompt (docs/SECURITY.md T3).
public enum LiveStateSummary {
    public static let maxPerLine = 4

    public static func make(reminders: [Reminder], watchers: [Watcher], jobs: [Job], sessions: [AgentSession], now: Date,
                            timeZone: TimeZone) -> String {
        var lines: [String] = []

        let horizon = now.addingTimeInterval(86_400)
        let due = reminders.compactMap { r in r.nextDue.map { (r, $0) } }.filter { $0.1 <= horizon }.sorted { $0.1 < $1.1 }
        if !due.isEmpty {
            let shown = due.filter { trusted($0.0.source) }.map { r, at in "“\(title(r.title))” \(when(at, now: now, timeZone: timeZone))" }
            lines.append("- Reminders in the next 24 h: " + list(shown, total: due.count))
        }

        let active = watchers.filter { $0.state == .active }
        if !active.isEmpty {
            lines.append("- Watching: " + list(active.filter { trusted($0.source) }.map { "“\(title($0.title))”" }, total: active.count))
        }

        // Job titles are command lines reported over the socket, so they are counted, never quoted.
        let running = jobs.filter { $0.state == .running }
        if !running.isEmpty {
            let since = running.map(\.startedAt).min().map { " (the first since \(ContextBuilder.format($0, "HH:mm", timeZone)))" } ?? ""
            lines.append("- Running: \(running.count) \(running.count == 1 ? "command" : "commands") started from a terminal or another agent\(since)")
        }

        // Session titles, folder names and agent names all come from hook payloads that any local
        // process can send (a cloned repo's folder name is the attacker's text), so only known agent
        // names and the state appear.
        let live = sessions.filter { $0.endedAt == nil && $0.state != .finished }
        if !live.isEmpty {
            let shown = live.map { s in
                let state = switch s.state {
                case .needsYou: "needs you"
                case .working: "working"
                case .idle, .finished: "idle"
                }
                return "\(agentName(s.agent)) (\(state))"
            }
            lines.append("- Agent sessions: " + list(shown, total: live.count))
        }

        return lines.isEmpty ? "- No reminders in the next 24 h, nothing watched, nothing running." : lines.joined(separator: "\n")
    }

    /// Reads the stores each time the context is built.
    public static func provider(db: AppDatabase, clock: any Clock = SystemClock(),
                                timeZone: TimeZone = .current) -> @Sendable () async -> String? {
        { () async -> String? in
            let reminders = (try? await ReminderStore(db).pending()) ?? []
            let watchers = (try? await WatcherStore(db).active()) ?? []
            let jobs = (try? await JobStore(db).running()) ?? []
            let sessions = (try? await SessionStore(db).live()) ?? []
            return make(reminders: reminders, watchers: watchers, jobs: jobs, sessions: sessions, now: clock.now, timeZone: timeZone)
        }
    }

    /// Only the user's own words are quoted. Sidefolk's agent records "user:agent" for what it does in
    /// a clean turn; plain "agent" marks something made while untrusted content steered the turn.
    static func trusted(_ source: String) -> Bool { ContextBuilder.isUserSourced(source) }

    static func agentName(_ agent: String) -> String {
        switch agent.lowercased() {
        case "claude-code", "claude": "Claude Code"
        case "codex": "Codex"
        default: "another agent"
        }
    }

    static func title(_ text: String) -> String { ContextBuilder.oneLine(text).clipped(80) }

    static func list(_ shown: [String], total: Int) -> String {
        let named = shown.prefix(maxPerLine)
        let rest = total - named.count
        if named.isEmpty { return "\(total) set by other apps or agents" }
        return named.joined(separator: "; ") + (rest > 0 ? " (+\(rest) more)" : "")
    }

    static func when(_ date: Date, now: Date, timeZone: TimeZone) -> String {
        let time = ContextBuilder.format(date, "HH:mm", timeZone)
        if date < now { return "overdue since \(time)" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(date, inSameDayAs: now) ? "at \(time)" : "tomorrow at \(time)"
    }
}
