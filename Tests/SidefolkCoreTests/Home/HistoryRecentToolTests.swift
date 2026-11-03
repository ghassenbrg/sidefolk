import Foundation
import Testing
@testable import SidefolkCore

/// "What did Claude Code do today": Sidefolk's own agent reads short lines of History, on a card, and no one else can.
@Suite struct HistoryRecentToolTests {
    let runtime: SidefolkRuntime
    let clock = ManualClock(TestEnv.referenceDate)

    init() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-history-\(UUID().uuidString)", isDirectory: true)
        runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(), clock: clock)
    }

    func log(_ caller: String, _ summary: String, at: Date? = nil, args: JSONValue? = nil, outcome: String? = nil) async throws {
        _ = try await runtime.activity.log(ActivityEntry(at: at ?? clock.now, caller: caller, tool: "notes.save", risk: "low", decision: .auto, summary: summary,
                                                         args: args, outcome: outcome))
    }

    /// Runs it as the companion, answering its card.
    func read(_ input: JSONValue = [:]) async -> (outcome: ToolOutcome, card: ApprovalRequest?) {
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
        let outcome = await runtime.executor.execute(name: "history.recent", input: input, caller: .agent(runId: "r"))
        asked.cancel()
        return (outcome, await asked.value)
    }

    @Test func itAsksAndWhatItReadsIsOutsideContent() async throws {
        try await log("external:claude-code", "Save a note about the deploy")
        let read = await read()
        #expect(read.card?.effect == .readsPrivateData)
        guard case .ok(let result) = read.outcome.status else {
            Issue.record("\(read.outcome.status)")
            return
        }
        #expect(result.untrusted)
        #expect(result.text.contains("Claude Code: Save a note about the deploy"), "\(result.text)")
    }

    @Test func whoAndSinceKeepToWhatWasAsked() async throws {
        try await log("external:claude-code", "From Claude today")
        try await log("external:codex", "From Codex today")
        try await log("external:claude-code", "From Claude last week", at: clock.now.addingTimeInterval(-10 * 86400))
        let today = await read(["who": "claude code"]).outcome.promptText
        #expect(today.contains("From Claude today"))
        #expect(!today.contains("From Codex") && !today.contains("last week"))
        let week = await read(["since": "this week"]).outcome.promptText
        #expect(week.contains("From Codex today") && !week.contains("last week"))
        #expect(await !read(["since": "whenever"]).outcome.isOK)
    }

    /// Short lines: nothing a row only keeps for the person.
    @Test func argumentsAndOutcomesStayOut() async throws {
        try await log("external:codex", "Save a note", args: ["text": "the secret words"], outcome: "the outcome words")
        let text = await read().outcome.promptText
        #expect(text.contains("Save a note"))
        #expect(!text.contains("the secret words") && !text.contains("the outcome words"))
    }

    @Test func whatTheUserWasToldIsThereWithoutItsBody() async throws {
        await runtime.attention.post(AttentionRequest(level: .gentle, source: "watcher", title: "example.com changed", body: "The body words"))
        let text = await read().outcome.promptText
        #expect(text.contains("Told the user: example.com changed"), "\(text)")
        #expect(!text.contains("The body words"))
        #expect(await read(["who": "notices"]).outcome.promptText.contains("example.com changed"))
        #expect(await !read(["who": "codex"]).outcome.promptText.contains("example.com changed"))
    }

    @Test func aReadDoesntFillItself() async throws {
        _ = await read()
        #expect(await read().outcome.promptText.contains("Nothing in History"))
    }

    @Test func otherAgentsNeverGetIt() async throws {
        #expect(!ExternalToolPolicy.isExposed("history.recent"))
        let refused = await runtime.gateway.call("history.recent", input: [:], client: "codex")
        #expect(refused.promptText.contains("doesn't offer"))
        #expect(!runtime.gateway.specs().contains { $0.name == "history.recent" })
    }
}
