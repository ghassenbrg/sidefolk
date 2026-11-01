import Foundation

/// The agents lane on the desktop (D84): a chip on the floor line for each Claude Code or Codex session that is working
/// or waiting for the person right now, from the sessions Sidefolk follows. A session that finished its turn or ended
/// has no chip; its notice says so.
public struct AgentChip: Sendable, Equatable, Identifiable {
    public var id: String
    /// "Claude Code", "Codex".
    public var agent: String
    /// The folder it works in ("pockito"), when known.
    public var project: String?
    /// It waits for the person in its own terminal.
    public var needsYou: Bool
    public var since: Date
    /// Sessions of the same agent in the same folder, standing as this one face (D88).
    public var count: Int

    public init(id: String, agent: String, project: String?, needsYou: Bool, since: Date, count: Int = 1) {
        self.id = id
        self.agent = agent
        self.project = project
        self.needsYou = needsYou
        self.since = since
        self.count = count
    }
}

/// Sessions of one agent in one folder, in the same state, shown once with how many (D88): subagents and a second
/// terminal in the same project would otherwise read as the same line three times.
public struct AgentSessionGroup: Sendable, Equatable, Identifiable {
    /// The one that stands for the rest: the most recently active.
    public var session: AgentSession
    public var count: Int
    public var id: String { session.id }

    /// Grouped in the order they came, each group at its first session's place.
    public static func of(_ sessions: [AgentSession]) -> [AgentSessionGroup] {
        var groups: [AgentSessionGroup] = []
        var index: [String: Int] = [:]
        for s in sessions {
            let key = "\(s.agent)|\(s.cwd ?? s.id)|\(s.state.rawValue)"
            if let i = index[key] {
                groups[i].count += 1
                if s.updatedAt > groups[i].session.updatedAt { groups[i].session = s }
            } else {
                index[key] = groups.count
                groups.append(AgentSessionGroup(session: s, count: 1))
            }
        }
        return groups
    }
}

public enum AgentLane {
    /// At most this many chips stand on the floor; the rest are in Home.
    public static let shown = 3

    /// Waiting ones first (they matter), then the longest running.
    public static func chips(_ sessions: [AgentSession]) -> [AgentChip] {
        let live = sessions.filter { $0.endedAt == nil && ($0.state == .working || $0.state == .needsYou) }
            .sorted { ($0.state == .needsYou ? 0 : 1, $0.startedAt) < ($1.state == .needsYou ? 0 : 1, $1.startedAt) }
        return AgentSessionGroup.of(live).prefix(shown).map { group in
            let s = group.session
            return AgentChip(id: s.id, agent: AgentFacingTools.displayName(s.agent), project: s.projectName,
                             needsYou: s.state == .needsYou, since: live.first { $0.cwd == s.cwd && $0.agent == s.agent }?.startedAt ?? s.startedAt,
                             count: group.count)
        }
    }
}
