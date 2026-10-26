import Foundation
import Testing
@testable import SidefolkCore

/// The Codex brain end to end against the real `codex` on this Mac and the user's ChatGPT plan: a
/// whole Sidefolk runtime (temp home, in-memory database, real socket and `sidefolk mcp` helper),
/// two tiny requests. Off unless `SIDEFOLK_LIVE_CODEX=1`: each test spends a little of the plan.
@Suite(.serialized) struct LiveCodexTests {
    static let enabled = ProcessInfo.processInfo.environment["SIDEFOLK_LIVE_CODEX"] == "1"

    struct Stack {
        let dir: ShortTempDir
        let runtime: SidefolkRuntime
        let agent: AgentRuntime

        init() async throws {
            let helper = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/debug/sidefolk").path
            dir = try ShortTempDir()
            let paths = SidefolkPaths(home: URL(fileURLWithPath: dir.path))
            runtime = await SidefolkRuntime(paths: paths, db: try AppDatabase.inMemory(), platform: NullPlatform())
            try await runtime.start()
            await runtime.settings.update { $0.provider.kind = .codex }
            let tokens = runtime.tokens
            let factory = BrainFactory.standard(secrets: InMemorySecretStore(), codexBackend: { provider in
                CodexBackend.make(provider: provider, paths: paths, helperPath: helper, registry: tokens)
            })
            let settings = runtime.settings
            agent = AgentRuntime(executor: runtime.executor, db: runtime.db, events: runtime.events,
                                 context: ContextBuilder(notebook: runtime.notebook, exchanges: runtime.exchanges), factory: factory,
                                 settings: { settings.current })
        }

        func stop() async {
            _ = await runtime.stop()
            dir.remove()
        }
    }

    /// At low effort, so the run also proves Codex takes `-c model_reasoning_effort` (D36).
    @Test(.enabled(if: enabled)) func answersOneWord() async throws {
        let stack = try await Stack()
        await stack.runtime.settings.update { $0.provider.effort = ReasoningEffort.low.rawValue }
        let result = await stack.agent.testProvider()
        await stack.stop()
        let text = try result.get()
        print("live codex: \(text)")
        #expect(text.lowercased().contains("ok"))
    }

    @Test(.enabled(if: enabled)) func savesANoteThroughSidefolksTools() async throws {
        let stack = try await Stack()
        let events = await collect(stack.agent.handle(AgentRequest(text: "Save a note titled “Codex live check” that says: hello from Codex.")))
        let items = try await stack.runtime.notebook.items()
        let runs = try await stack.runtime.runs.recent()
        let activity = try await stack.runtime.activity.recent()
        await stack.stop()
        if let failure = events.compactMap(\.failure).first { Issue.record("run failed: \(failure) \(failure.detail ?? "")") }
        print("live codex reply: \(events.compactMap(\.reply).first?.text ?? "-")")
        print("live codex run: \(runs.first.map { "\($0.provider) \($0.model) steps \($0.steps) in \($0.inputTokens) out \($0.outputTokens)" } ?? "-")")
        print("live codex activity: \(activity.map { "\($0.tool) \($0.decision)" })")
        #expect(items.contains { $0.title.localizedCaseInsensitiveContains("Codex live check") || $0.body.contains("hello from Codex") })
        #expect(activity.contains { $0.tool == "notes.save" && $0.runId == runs.first?.id })
    }
}
