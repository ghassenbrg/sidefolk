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
    /// What its own app calls the conversation, when it says (D118).
    public var title: String? = nil
    /// It waits for the person in its own terminal.
    public var needsYou: Bool
    public var since: Date
    /// Sessions of the same agent in the same folder, standing as this one face (D90).
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

/// Sessions of one agent in one folder, in the same state, shown once with how many (D90): subagents and a second
/// terminal in the same project would otherwise read as the same line three times.
public struct AgentSessionGroup: Sendable, Equatable, Identifiable {
    /// The one that stands for the rest: the most recently active.
    public var session: AgentSession
    public var count: Int
    /// When the earliest of them started.
    public var since: Date
    public var id: String { session.id }

    /// Grouped in the order they came, each group at its first session's place.
    public static func of(_ sessions: [AgentSession]) -> [AgentSessionGroup] {
        var groups: [AgentSessionGroup] = []
        // Titled conversations stand apart (D118), which is why they have titles; one with no title, like a subagent,
        // joins whichever of them it can.
        for s in sessions {
            let same = { (g: AgentSessionGroup) in g.session.agent == s.agent && (g.session.cwd ?? g.session.id) == (s.cwd ?? s.id) && g.session.state == s.state }
            let match = groups.firstIndex { same($0) && (s.conversationTitle == nil || $0.session.conversationTitle == nil || $0.session.conversationTitle == s.conversationTitle) }
            if let i = match {
                groups[i].count += 1
                groups[i].since = min(groups[i].since, s.startedAt)
                // What opens is the session the row names: one with a title stands for the rest over one without.
                let standing = groups[i].session
                let titled = standing.conversationTitle != nil, joinerTitled = s.conversationTitle != nil
                if (joinerTitled && !titled) || (joinerTitled == titled && s.updatedAt > standing.updatedAt) { groups[i].session = s }
            } else {
                groups.append(AgentSessionGroup(session: s, count: 1, since: s.startedAt))
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
            var chip = AgentChip(id: s.id, agent: AgentFacingTools.displayName(s.agent), project: s.projectName,
                             needsYou: s.state == .needsYou, since: group.since,
                             count: group.count)
            chip.title = s.conversationTitle
            return chip
        }
    }
}
