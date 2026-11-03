import Foundation
import Testing
@testable import SidefolkCore

/// "Is anything waiting for me?": what the companion may know of other agents' sessions, and what it may not.
@Suite struct AgentSessionsToolTests {
    let runtime: SidefolkRuntime

    init() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-sessions-\(UUID().uuidString)", isDirectory: true)
        runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform())
    }

    func read() async -> (outcome: ToolOutcome, card: ApprovalRequest?) {
        let stream = runtime.events.stream()
        let broker = runtime.broker
        let asked = Task { () -> ApprovalRequest? in
            for await event in stream {
                if case .approvalRequested(let r) = event {
                    await broker.resolve(id: r.id, decision: .allowOnce)
                    return r
                }
            }
            return nil
        }
        let outcome = await runtime.executor.execute(name: "agents.sessions", input: [:], caller: .agent(runId: "r"))
        asked.cancel()
        return (outcome, await asked.value)
    }

    @Test func itSaysWhosWaitingFirstAndNoTitles() async throws {
        var working = AgentSession(id: "a", agent: "codex", cwd: "/Users/me/git/pockito", state: .working)
        working.title = "the first prompt words"
        working.conversationTitle = "the conversation title"
        working.detail = "what it last said"
        try await runtime.sessions.save(working)
        try await runtime.sessions.save(AgentSession(id: "b", agent: "claude-code", cwd: "/Users/me/git/sidefolk", state: .needsYou))

        let read = await read()
        #expect(read.card?.effect == .readsPrivateData)
        guard case .ok(let result) = read.outcome.status else {
            Issue.record("\(read.outcome.status)")
            return
        }
        #expect(result.untrusted)
        #expect(result.text.hasPrefix("- Claude Code in sidefolk: waiting for the user"), "\(result.text)")
        #expect(result.text.contains("Codex in pockito: working"))
        for private_ in ["first prompt", "conversation title", "last said", "/Users/me"] { #expect(!result.text.contains(private_), "\(private_)") }
    }

    @Test func aSelfChosenNameReadsAsThat() async throws {
        try await runtime.sessions.save(AgentSession(id: "c", agent: "The.user", cwd: nil, state: .working))
        #expect(await read().outcome.promptText.contains("An agent calling itself “The.user”"))
    }

    @Test func nothingRunningSaysSo() async {
        #expect(await read().outcome.promptText.contains("No agent sessions"))
    }

    @Test func otherAgentsNeverGetIt() async {
        #expect(!ExternalToolPolicy.isExposed("agents.sessions"))
        #expect(await runtime.gateway.call("agents.sessions", input: [:], client: "codex").promptText.contains("doesn't offer"))
    }
}
