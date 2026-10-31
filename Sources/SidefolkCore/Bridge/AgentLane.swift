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
}

public enum AgentLane {
    /// At most this many chips stand on the floor; the rest are in Home.
    public static let shown = 3

    /// Waiting ones first (they matter), then the longest running.
    public static func chips(_ sessions: [AgentSession]) -> [AgentChip] {
        sessions.filter { $0.endedAt == nil && ($0.state == .working || $0.state == .needsYou) }
            .sorted { ($0.state == .needsYou ? 0 : 1, $0.startedAt) < ($1.state == .needsYou ? 0 : 1, $1.startedAt) }
            .prefix(shown)
            .map { AgentChip(id: $0.id, agent: AgentFacingTools.displayName($0.agent), project: $0.projectName,
                             needsYou: $0.state == .needsYou, since: $0.startedAt) }
    }
}
