import Foundation

/// What other agents may do with a group of Sidefolk's tools (D52).
public enum AgentPermission: String, Codable, Sendable, CaseIterable {
    case allow
    /// A card asks every time, and never offers "Always allow" (T1).
    case ask
    /// The tools are hidden from other agents, and a call is refused.
    case off
}

/// Settings › Privacy › Other agents: what Claude Code, Codex and other MCP clients may do through `sidefolk mcp`
/// (SECURITY T4). Only the groups in `ExternalToolPolicy`; anything else never reaches them, whatever is set here.
public struct AgentAccess: Codable, Sendable, Equatable {
    /// Save notes, set and cancel their own reminders, start their own watches and live values.
    public var save: AgentPermission = .allow
    /// Read notes, reminders and today's plan.
    public var read: AgentPermission = .ask
    /// Change notes and move them to the Trash (restorable for 30 days; only the person empties it).
    public var change: AgentPermission = .allow

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decode(AgentPermission.self, forKey: .save) { save = v }
        if let v = try? c.decode(AgentPermission.self, forKey: .read) { read = v }
        if let v = try? c.decode(AgentPermission.self, forKey: .change) { change = v }
    }
}
