import Foundation
import Testing
@testable import SidefolkCore

/// A medium-risk card names what the call can do, from what Sidefolk lets it do: a weather forecast said
/// "Changes things" before the 0.1.0 review. The risk level stays as it was.
@Suite struct ApprovalEffectTests {
    static let cases: [(name: String, can: Set<Capability>, mutates: Bool, effect: ApprovalRequest.Effect)] = [
        // An extension: only its sandbox counts, never its own word.
        ("ext.weather.forecast", [.extensions, .network], false, .usesInternet),
        ("ext.weather.forecast", [.extensions, .network], true, .usesInternet),
        ("ext.git.clone", [.extensions, .network, .filesWrite], false, .changesFiles),
        ("ext.notes.search", [.extensions, .filesRead], false, .readsFiles),
        ("ext.tasks.add", [.extensions], true, .usesExtension),
        ("ext.tasks.list", [.extensions], false, .usesExtension),
        ("ext.tool.run", [.extensions, .shell], false, .runsPrograms),
        // Sidefolk's own tools: their `mutates` is Sidefolk's word.
        ("web.fetch", [.network], false, .usesInternet),
        ("open.email", [.apps], false, .opensApps),
        ("clipboard.read", [.clipboard], false, .readsPrivateData),
        ("files.move", [.filesWrite], true, .changesFiles),
        ("applenotes.copy", [.macApps, .notebook], true, .changesThings),
        ("watch.extension", [.watch, .extensions], true, .changesThings),
    ]

    @Test func theLabelSaysWhatTheCallCanDo() async throws {
        for c in Self.cases {
            let env = try TestEnv()
            env.registry.register(ProbeTool(name: c.name, risk: .medium, capabilities: c.can, mutates: c.mutates))
            let card = env.autoAnswer(.deny)
            _ = await env.executor.execute(name: c.name, input: ["x": "a"], caller: .agent(runId: "r"))
            let request = try #require(await card.value)
            #expect(request.effect == c.effect, "\(c.name) \(c.can) mutates: \(c.mutates)")
            #expect(request.risk == .medium)
        }
    }
}
