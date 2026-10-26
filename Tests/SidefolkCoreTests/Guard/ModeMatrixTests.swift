import Foundation
import Testing
@testable import SidefolkCore

/// Approval modes (D37): every mode × risk × taint × caller, for each kind of tool Guard tells apart.
@Suite struct ModeMatrixTests {
    /// What Guard does: run without a question (`.run`), ask (`.ask`), or run because the mode answered
    /// for the person (`.auto` for Auto, `.full` for Full access).
    enum Outcome: Equatable, CustomStringConvertible {
        case run, ask, auto, full
        var description: String { "\(self)" }
    }

    /// The kinds of tool the rules distinguish.
    enum Shape: CaseIterable {
        /// Changes something inside Sidefolk only.
        case plain
        /// Reaches the network at an address the person didn't type.
        case network
        /// Opens an address the person typed in this request.
        case typedLink
        /// Moves, renames or trashes files.
        case files
        /// Writes memory.
        case memory
        /// Runs a program.
        case shell
        /// Hands input to an extension or MCP server.
        case extensionTool
        /// Saves text the person must read in full (a skill).
        case fullText

        var capabilities: Set<Capability> {
            switch self {
            case .plain, .fullText: []
            case .network: [.network]
            case .typedLink: [.apps]
            case .files: [.filesWrite]
            case .memory: [.memory]
            case .shell: [.shell]
            case .extensionTool: [.extensions]
            }
        }

        var scope: ToolScope {
            switch self {
            case .typedLink: ToolScope(url: "https://example.com/a")
            case .fullText: ToolScope(text: "Skill “weekly-plan”\nSteps…")
            default: .none
            }
        }
    }

    struct Row {
        var shape: Shape
        var risk: Risk
        var tainted: Bool
        /// For Sidefolk's own agent, in order: Ask every time, Ask once per kind, Auto, Full access.
        var agent: [Outcome]
    }

    // Read across: what Sidefolk's own agent gets in each mode. Other callers always get the first
    // column (Ask every time) or the second (every other mode): modes never loosen their rules.
    static let rows: [Row] = [
        Row(shape: .plain, risk: .low, tainted: false, agent: [.run, .run, .run, .run]),
        Row(shape: .plain, risk: .low, tainted: true, agent: [.run, .run, .run, .run]),
        Row(shape: .plain, risk: .medium, tainted: false, agent: [.ask, .ask, .auto, .full]),
        Row(shape: .plain, risk: .medium, tainted: true, agent: [.ask, .ask, .ask, .full]),
        Row(shape: .plain, risk: .high, tainted: false, agent: [.ask, .ask, .ask, .full]),
        Row(shape: .plain, risk: .high, tainted: true, agent: [.ask, .ask, .ask, .full]),

        Row(shape: .network, risk: .low, tainted: false, agent: [.run, .run, .run, .run]),
        Row(shape: .network, risk: .low, tainted: true, agent: [.ask, .ask, .ask, .ask]),
        Row(shape: .network, risk: .medium, tainted: false, agent: [.ask, .ask, .auto, .full]),
        Row(shape: .network, risk: .medium, tainted: true, agent: [.ask, .ask, .ask, .ask]),
        Row(shape: .network, risk: .high, tainted: false, agent: [.ask, .ask, .ask, .full]),
        Row(shape: .network, risk: .high, tainted: true, agent: [.ask, .ask, .ask, .ask]),

        Row(shape: .typedLink, risk: .low, tainted: false, agent: [.run, .run, .run, .run]),
        Row(shape: .typedLink, risk: .low, tainted: true, agent: [.run, .run, .run, .run]),
        Row(shape: .typedLink, risk: .medium, tainted: false, agent: [.ask, .ask, .auto, .full]),
        Row(shape: .typedLink, risk: .medium, tainted: true, agent: [.ask, .ask, .ask, .full]),
        Row(shape: .typedLink, risk: .high, tainted: false, agent: [.ask, .ask, .ask, .full]),
        Row(shape: .typedLink, risk: .high, tainted: true, agent: [.ask, .ask, .ask, .full]),

        Row(shape: .files, risk: .low, tainted: false, agent: [.run, .run, .run, .run]),
        Row(shape: .files, risk: .low, tainted: true, agent: [.run, .run, .run, .run]),
        Row(shape: .files, risk: .medium, tainted: false, agent: [.ask, .ask, .auto, .full]),
        Row(shape: .files, risk: .medium, tainted: true, agent: [.ask, .ask, .ask, .ask]),
        Row(shape: .files, risk: .high, tainted: false, agent: [.ask, .ask, .ask, .full]),
        Row(shape: .files, risk: .high, tainted: true, agent: [.ask, .ask, .ask, .ask]),

        Row(shape: .memory, risk: .low, tainted: false, agent: [.run, .run, .run, .run]),
        Row(shape: .memory, risk: .low, tainted: true, agent: [.ask, .ask, .ask, .ask]),
        Row(shape: .memory, risk: .medium, tainted: false, agent: [.ask, .ask, .auto, .full]),
        Row(shape: .memory, risk: .medium, tainted: true, agent: [.ask, .ask, .ask, .ask]),
        Row(shape: .memory, risk: .high, tainted: false, agent: [.ask, .ask, .ask, .full]),
        Row(shape: .memory, risk: .high, tainted: true, agent: [.ask, .ask, .ask, .ask]),

        Row(shape: .shell, risk: .low, tainted: false, agent: [.run, .run, .run, .run]),
        Row(shape: .shell, risk: .low, tainted: true, agent: [.run, .run, .run, .run]),
        Row(shape: .shell, risk: .medium, tainted: false, agent: [.ask, .ask, .auto, .full]),
        Row(shape: .shell, risk: .medium, tainted: true, agent: [.ask, .ask, .ask, .ask]),
        Row(shape: .shell, risk: .high, tainted: false, agent: [.ask, .ask, .ask, .full]),
        Row(shape: .shell, risk: .high, tainted: true, agent: [.ask, .ask, .ask, .ask]),

        Row(shape: .extensionTool, risk: .low, tainted: false, agent: [.run, .run, .run, .run]),
        Row(shape: .extensionTool, risk: .low, tainted: true, agent: [.run, .run, .run, .run]),
        Row(shape: .extensionTool, risk: .medium, tainted: false, agent: [.ask, .ask, .auto, .full]),
        Row(shape: .extensionTool, risk: .medium, tainted: true, agent: [.ask, .ask, .ask, .ask]),
        Row(shape: .extensionTool, risk: .high, tainted: false, agent: [.ask, .ask, .ask, .full]),
        Row(shape: .extensionTool, risk: .high, tainted: true, agent: [.ask, .ask, .ask, .ask]),

        Row(shape: .fullText, risk: .low, tainted: false, agent: [.run, .run, .run, .run]),
        Row(shape: .fullText, risk: .low, tainted: true, agent: [.run, .run, .run, .run]),
        Row(shape: .fullText, risk: .medium, tainted: false, agent: [.ask, .ask, .ask, .ask]),
        Row(shape: .fullText, risk: .medium, tainted: true, agent: [.ask, .ask, .ask, .ask]),
        Row(shape: .fullText, risk: .high, tainted: false, agent: [.ask, .ask, .ask, .ask]),
        Row(shape: .fullText, risk: .high, tainted: true, agent: [.ask, .ask, .ask, .ask]),
    ]

    static let modes: [GuardMode] = [.askEveryTime, .askOncePerKind, .auto, .fullAccess]
    static let callers: [Caller] = [.agent(runId: "r"), .routine(id: "daily"), .external(client: "codex"), .extension(id: "dev.x.y")]

    func decide(_ shape: Shape, _ risk: Risk, tainted: Bool, caller: Caller, mode: GuardMode,
                grants: [Grant] = [], disabled: Set<Capability> = []) -> GuardDecision {
        let spec = ToolSpec(name: "t.x", title: "X", description: "", inputSchema: .object([:]), risk: risk,
                            capabilities: shape.capabilities, category: .system, mutates: true)
        return PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: shape.scope, caller: caller,
                                           tainted: tainted, policy: GuardPolicy(mode: mode, disabled: disabled), grants: grants,
                                           folders: [], mentions: UserMentions(text: "open https://example.com/a please"))
    }

    static func outcome(_ d: GuardDecision) -> Outcome? {
        switch d {
        case .allow(.auto): .run
        case .allow(.autoMode): .auto
        case .allow(.fullAccess): .full
        case .ask: .ask
        default: nil
        }
    }

    @Test func everyModeRiskTaintAndCaller() {
        #expect(Self.rows.count == Shape.allCases.count * 3 * 2)
        var checked = 0
        for row in Self.rows {
            for (column, mode) in Self.modes.enumerated() {
                for caller in Self.callers {
                    let expected: Outcome = if case .agent = caller { row.agent[column] } else { row.agent[column == 0 ? 0 : 1] }
                    let got = Self.outcome(decide(row.shape, row.risk, tainted: row.tainted, caller: caller, mode: mode))
                    #expect(got == expected, "\(row.shape) \(row.risk) tainted=\(row.tainted) \(caller.kind) \(mode)")
                    checked += 1
                }
            }
        }
        #expect(checked == 48 * 4 * 4)
    }

    @Test func theUsersOwnClicksRunInEveryMode() {
        for mode in Self.modes {
            for row in Self.rows {
                #expect(decide(row.shape, row.risk, tainted: row.tainted, caller: .user, mode: mode) == .allow(.auto))
            }
        }
    }

    // MARK: Invariants that hold in every mode

    @Test func capabilitiesTurnedOffStayBlocked() {
        for mode in Self.modes {
            for caller in Self.callers + [.user] {
                for tainted in [false, true] {
                    guard case .deny = decide(.shell, .high, tainted: tainted, caller: caller, mode: mode, disabled: [.shell]) else {
                        Issue.record("\(mode) \(caller.kind): a disabled capability must stay blocked"); continue
                    }
                }
            }
        }
    }

    @Test func forbiddenPlacesStayBlocked() {
        let spec = ToolSpec(name: "files.move", title: "Move", description: "", inputSchema: .object([:]), risk: .medium,
                            capabilities: [.filesWrite], category: .files, mutates: true)
        for mode in Self.modes {
            for caller in Self.callers + [.user] {
                for path in [NSHomeDirectory() + "/.ssh/authorized_keys", NSHomeDirectory() + "/Library/LaunchAgents/x.plist", "/System/x"] {
                    let d = PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: ToolScope(writePaths: [path]),
                                                        caller: caller, tainted: false, policy: GuardPolicy(mode: mode), grants: [], folders: [])
                    guard case .deny = d else { Issue.record("\(mode) \(caller.kind) \(path) must be denied"); continue }
                }
            }
        }
    }

    @Test func foldersOutsideTheListAreAskedAboutInEveryMode() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("sf-mode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let spec = ToolSpec(name: "files.move", title: "Move", description: "", inputSchema: .object([:]), risk: .medium,
                            capabilities: [.filesWrite], category: .files, mutates: true)
        let scope = ToolScope(writePaths: [outside.appendingPathComponent("a.txt").path])
        for mode in Self.modes {
            let own = PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: scope, caller: .agent(runId: "r"),
                                                  tainted: false, policy: GuardPolicy(mode: mode), grants: [], folders: [])
            guard case .ask(let request) = own, case .folderAccess = request.details else {
                Issue.record("\(mode): a folder that isn't shared must be asked about"); continue
            }
            let other = PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: scope, caller: .external(client: "x"),
                                                    tainted: false, policy: GuardPolicy(mode: mode), grants: [], folders: [])
            guard case .deny = other else { Issue.record("\(mode): other agents never get folder prompts"); continue }
        }
    }

    @Test func aLinkTheModelBuiltIsOnlyAnsweredByAModeInACleanTurn() {
        let spec = ToolSpec(name: "web.fetch", title: "Fetch", description: "", inputSchema: .object([:]), risk: .low,
                            capabilities: [.network], category: .web, mutates: false)
        func fetch(_ mode: GuardMode, tainted: Bool) -> GuardDecision {
            PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: ToolScope(url: "https://evil.example/?q=notes"),
                                        caller: .agent(runId: "r"), tainted: tainted, policy: GuardPolicy(mode: mode), grants: [],
                                        folders: [], mentions: UserMentions(text: "what's new?"))
        }
        // A model-built address is at least medium (T1), so Auto answers it only in a clean turn.
        #expect(fetch(.auto, tainted: false) == .allow(.autoMode))
        #expect(fetch(.fullAccess, tainted: false) == .allow(.fullAccess))
        for mode in Self.modes {
            guard case .ask(let r) = fetch(mode, tainted: true) else { Issue.record("\(mode): steered fetch must ask"); continue }
            #expect(r.tainted && !r.canAlways)
        }
    }

    @Test func askEveryTimeIgnoresGrantsAndAutoHonoursThem() {
        let grant = Grant(tool: "t.x", callerKind: "agent")
        guard case .ask = decide(.plain, .medium, tainted: false, caller: .agent(runId: "r"), mode: .askEveryTime, grants: [grant]) else {
            Issue.record("Ask every time must ignore “Always allow”"); return
        }
        #expect(decide(.plain, .medium, tainted: false, caller: .agent(runId: "r"), mode: .askOncePerKind, grants: [grant]) == .allow(.always))
        #expect(decide(.plain, .medium, tainted: false, caller: .agent(runId: "r"), mode: .auto, grants: [grant]) == .allow(.always))
        // A grant never covers a tainted call, in any mode; Full access still runs the plain one, as the table says.
        #expect(decide(.plain, .medium, tainted: true, caller: .agent(runId: "r"), mode: .auto, grants: [grant]) != .allow(.always))
    }

    @Test func modeForEachCaller() {
        for mode in Self.modes {
            let policy = GuardPolicy(mode: mode)
            #expect(policy.mode(for: .agent(runId: "r")) == mode)
            for caller in [Caller.user, .routine(id: "x"), .external(client: "x"), .extension(id: "x")] {
                #expect(policy.mode(for: caller) == (mode == .askEveryTime ? .askEveryTime : .askOncePerKind))
            }
        }
    }
}
