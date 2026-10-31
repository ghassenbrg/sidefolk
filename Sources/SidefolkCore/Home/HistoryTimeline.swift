import Foundation

/// Home › History (D84): one timeline of what happened, made of what the app already keeps: Activity's rows, the kept
/// conversations, what Sidefolk told the person (attention items) and other agents' sessions. Nothing new is stored;
/// this only merges, groups and filters, so the app's view stays a list of plain sentences.
public struct HistoryEvent: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// A tool call, by anyone, as Activity logged it.
        case action(ActivityEntry)
        /// A conversation with the AI, at its latest request.
        case conversation(ConversationSummary)
        /// Something Sidefolk told the person: a watch that fired, a reminder, a notice.
        case alert(AttentionItem)
        /// Another agent's session as a receipt: its calls to Sidefolk while it ran, oldest first.
        case session(AgentSession, calls: [ActivityEntry])
    }

    public var kind: Kind
    public var at: Date

    public init(_ kind: Kind, at: Date) {
        self.kind = kind
        self.at = at
    }

    public var id: String {
        switch kind {
        case .action(let e): "a" + (e.id.map(String.init) ?? "\(e.at.timeIntervalSince1970)\(e.tool)")
        case .conversation(let c): "c" + c.id
        case .alert(let a): "n" + a.id
        case .session(let s, _): "s" + s.id
        }
    }

    /// The words a search looks in.
    public var searchable: [String] {
        switch kind {
        case .action(let e): [e.summary, e.outcome ?? "", e.caller]
        case .conversation(let c): [c.title]
        case .alert(let a): [a.title, a.body ?? "", a.source]
        case .session(let s, let calls): [s.agent, s.projectName ?? "", s.title ?? "", s.detail ?? ""] + calls.map(\.summary)
        }
    }
}

public enum HistoryFilter: String, Sendable, CaseIterable, Identifiable {
    case all, conversations, actions, agents, alerts
    public var id: Self { self }
}

public enum HistoryTimeline {
    /// Everything, newest first. Calls an agent made while one of its sessions ran belong to that session's receipt and
    /// don't show twice; calls with no session stay rows of their own.
    public static func merge(activity: [ActivityEntry], conversations: [ConversationSummary], alerts: [AttentionItem],
                             sessions: [AgentSession], now: Date = Date()) -> [HistoryEvent] {
        var used = Set<Int64>()
        var events: [HistoryEvent] = []
        for session in sessions {
            let end = session.endedAt ?? (session.state == .finished ? session.updatedAt : now)
            let calls = activity.filter { entry in
                guard let id = entry.id, !used.contains(id), agent(of: entry) == session.agent.lowercased() else { return false }
                return entry.at >= session.startedAt.addingTimeInterval(-1) && entry.at <= end.addingTimeInterval(1)
            }
            calls.compactMap(\.id).forEach { used.insert($0) }
            events.append(HistoryEvent(.session(session, calls: calls.sorted { $0.at < $1.at }), at: session.updatedAt))
        }
        for entry in activity where entry.id.map({ !used.contains($0) }) ?? true {
            events.append(HistoryEvent(.action(entry), at: entry.at))
        }
        events += conversations.map { HistoryEvent(.conversation($0), at: $0.updatedAt) }
        events += alerts.map { HistoryEvent(.alert($0), at: $0.createdAt) }
        return events.sorted { ($0.at, $0.id) > ($1.at, $1.id) }
    }

    /// The agent an Activity row came from ("claude-code"), or nil when it wasn't another agent.
    static func agent(of entry: ActivityEntry) -> String? {
        guard entry.caller.hasPrefix("external:") else { return nil }
        return String(entry.caller.dropFirst("external:".count)).lowercased()
    }

    /// Whether an event shows under a filter and matches the searched words (every word, any field, any case).
    public static func shows(_ event: HistoryEvent, filter: HistoryFilter, query: String = "") -> Bool {
        let kindMatches: Bool = switch (filter, event.kind) {
        case (.all, _): true
        case (.conversations, .conversation): true
        case (.actions, .action(let e)): agent(of: e) == nil
        case (.agents, .session): true
        case (.agents, .action(let e)): agent(of: e) != nil
        case (.alerts, .alert): true
        default: false
        }
        guard kindMatches else { return false }
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let text = event.searchable.joined(separator: " ").lowercased()
        return words.allSatisfy { text.contains($0) }
    }

    /// Events by the hour they happened in, newest hour first, as History draws them.
    public static func hours(_ events: [HistoryEvent], calendar: Calendar = .autoupdatingCurrent) -> [(start: Date, events: [HistoryEvent])] {
        var groups: [(start: Date, events: [HistoryEvent])] = []
        for event in events {
            let start = calendar.dateInterval(of: .hour, for: event.at)?.start ?? event.at
            if let last = groups.indices.last, groups[last].start == start {
                groups[last].events.append(event)
            } else {
                groups.append((start, [event]))
            }
        }
        return groups
    }
}
