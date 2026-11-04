import Foundation
import Testing
@testable import SidefolkCore

/// What the person said yes to is listed where they can take it back (Trust › Allowed for now, Always allowed), and
/// "Forget everything I allowed" takes back all of it and nothing else.
@Suite struct RememberedAnswersTests {
    /// A tainted run whose cards are answered with `decision`; counts the cards.
    private func answering(_ env: TestEnv, _ decision: ApprovalDecision, cards: CallCounter) -> Task<Void, Never> {
        let stream = env.events.stream()
        let broker = env.broker
        return Task {
            for await e in stream {
                guard case .approvalRequested(let r) = e else { continue }
                cards.bump()
                await broker.resolve(id: r.id, decision: decision)
            }
        }
    }

    @Test func allowedForNowIsListedAndStopsAsked() async throws {
        let env = try TestEnv()
        env.registry.register(ProbeTool(name: "applenotes.copy", risk: .medium, capabilities: [.macApps, .notebook],
                                        result: { _ in ToolResult(text: "Copied.", untrusted: true) }))
        let cards = CallCounter()
        let answer = answering(env, .allowForRequest, cards: cards)
        defer { answer.cancel() }
        #expect(await env.executor.allowedForNow().isEmpty)

        let box = BrainToolbox(runId: "run-1", specs: env.registry.specs, executor: env.executor, startTainted: true, emit: { _ in })
        _ = await box.call("applenotes.copy", input: ["x": "1"])
        _ = await box.call("applenotes.copy", input: ["x": "2"])
        #expect(cards.value == 1)
        #expect(await env.executor.allowedForNow() == [.tool("applenotes.copy")])

        // Stopped: the same run is asked again.
        await env.executor.stopAllowing(.tool("applenotes.copy"))
        #expect(await env.executor.allowedForNow().isEmpty)
        _ = await box.call("applenotes.copy", input: ["x": "3"])
        #expect(cards.value == 2)

        // It ends with the run, and is gone from the list.
        await box.close()
        #expect(await env.executor.allowedForNow().isEmpty)
    }

    @Test func forgetTakesBackEveryYesAndLeavesFolders() async throws {
        let env = try TestEnv()
        env.registry.register(ProbeTool(name: "applenotes.copy", risk: .medium, capabilities: [.macApps, .notebook],
                                        result: { _ in ToolResult(text: "Copied.", untrusted: true) }))
        let cards = CallCounter()
        let answer = answering(env, .allowForRequest, cards: cards)
        defer { answer.cancel() }
        let box = BrainToolbox(runId: "run-1", specs: env.registry.specs, executor: env.executor, startTainted: true, emit: { _ in })
        _ = await box.call("applenotes.copy", input: ["x": "1"])
        try await env.permissions.addGrant(Grant(tool: "applenotes.list", scope: .object([:]), callerKind: "agent"))
        let site = Grant(tool: "web.fetch", scope: ["host": "docs.example.com"], callerKind: "agent")
        try await env.permissions.addGrant(site)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("remembered-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try await env.permissions.grantFolder(folder, access: .readwrite)
        try await env.permissions.updatePolicy { $0.disabled.insert(.network) }
        #expect(try await env.permissions.grants().count == 2)

        // What Trust forgets: everything but the sites and services it lists under "Using the internet" (the caller says which).
        try await env.permissions.revokeGrants { $0.scope.string("host") == nil }
        await env.executor.stopAllowingAnything()

        #expect(try await env.permissions.grants().map(\.id) == [site.id], "the site stays, as the dialog says")
        #expect(await env.executor.allowedForNow().isEmpty)
        // Folders are their own list and the policy is not a yes.
        #expect(try await env.permissions.folders().count == 1)
        #expect(try await env.permissions.policy().disabled == [.network])
        // The same tool asks again.
        _ = await box.call("applenotes.copy", input: ["x": "2"])
        #expect(cards.value == 2)
    }

    @Test func aGrantCanBeRevokedAndTheNextCallAsksAgain() async throws {
        let env = try TestEnv()
        env.registry.register(ProbeTool(name: "clipboard.read", risk: .medium, capabilities: [.clipboard],
                                        result: { _ in ToolResult(text: "x") }))
        let cards = CallCounter()
        let answer = answering(env, .allowAlways, cards: cards)
        defer { answer.cancel() }
        let box = BrainToolbox(runId: "run-1", specs: env.registry.specs, executor: env.executor, startTainted: false, emit: { _ in })
        _ = await box.call("clipboard.read", input: [:])
        _ = await box.call("clipboard.read", input: [:])
        #expect(cards.value == 1)
        let grant = try #require(try await env.permissions.grants().first)
        try await env.permissions.revokeGrant(id: grant.id)
        _ = await box.call("clipboard.read", input: [:])
        #expect(cards.value == 2)
    }

    /// The folder card's main button is "Share folder" (it answers Always): the next call in that folder doesn't ask. "Just this time" doesn't remember.
    @Test func aSharedFolderIsNotAskedAboutAgainAndOnceIsNot() async throws {
        for (decision, remembered) in [(ApprovalDecision.allowAlways, true), (.allowOnce, false)] {
            let env = try TestEnv()
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sf-share-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            env.registry.register(ProbeTool(name: "files.move", risk: .medium, capabilities: [.filesWrite],
                                            scope: { _ in ToolScope(writePaths: [folder.path + "/a.txt"]) }))
            try await env.permissions.setPolicy(GuardPolicy(mode: .auto))
            let cards = CallCounter()
            let stream = env.events.stream()
            let broker = env.broker
            let answering = Task {
                for await e in stream {
                    guard case .approvalRequested(let r) = e else { continue }
                    cards.bump()
                    if case .folderAccess = r.details { await broker.resolve(id: r.id, decision: decision) } else { await broker.resolve(id: r.id, decision: .deny) }
                }
            }
            defer { answering.cancel() }
            for _ in 1...2 { #expect(await env.executor.execute(name: "files.move", input: ["x": "1"], caller: .agent(runId: "r")).isOK) }
            #expect(cards.value == (remembered ? 1 : 2), "\(decision)")
            #expect(try await env.permissions.folders().count == (remembered ? 1 : 0))
            // Taking it back from Trust (Remove) asks again.
            if remembered {
                try await env.permissions.revokeFolder(try #require(try await env.permissions.folders().first).path)
                _ = await env.executor.execute(name: "files.move", input: ["x": "1"], caller: .agent(runId: "r"))
                #expect(cards.value == 2)
            }
        }
    }

    /// "Share folder" shares the folder the card named: a link put there between the question and the yes shares nothing.
    @Test func aFolderSwappedForALinkAfterTheQuestionIsNotShared() async throws {
        let env = try TestEnv()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("sf-swap-\(UUID().uuidString)")
        let folder = base.appendingPathComponent("work"), elsewhere = base.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let target = folder.path
        env.registry.register(ProbeTool(name: "files.move", risk: .medium, capabilities: [.filesWrite],
                                        scope: { _ in ToolScope(writePaths: [target + "/a.txt"]) }))
        try await env.permissions.setPolicy(GuardPolicy(mode: .auto))
        let stream = env.events.stream()
        let broker = env.broker
        let cards = CallCounter()
        let swapping = Task {
            for await e in stream {
                guard case .approvalRequested(let r) = e else { continue }
                cards.bump()
                // Only the first question is answered yes, after the folder it named became a link; the call then asks again, now naming
                // where the link leads, and that card is answered no.
                if cards.value == 1 {
                    try? FileManager.default.removeItem(at: folder)
                    try? FileManager.default.createSymbolicLink(at: folder, withDestinationURL: elsewhere)
                    await broker.resolve(id: r.id, decision: .allowAlways)
                } else {
                    await broker.resolve(id: r.id, decision: .deny)
                }
            }
        }
        defer { swapping.cancel() }
        let out = await env.executor.execute(name: "files.move", input: ["x": "1"], caller: .agent(runId: "r"))
        #expect(!out.isOK)
        #expect(cards.value == 2, "the yes shared nothing, so it asked again, about the real folder")
        #expect(try await env.permissions.folders().isEmpty, "nothing was shared")
    }
}
