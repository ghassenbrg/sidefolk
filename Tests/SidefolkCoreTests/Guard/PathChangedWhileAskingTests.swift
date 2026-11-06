import Foundation
import Synchronization
@testable import SidefolkCore
import Testing

/// A card can be up for minutes. The tool resolves its path again when it runs, so a link swapped meanwhile must not send it somewhere Guard never checked (T10).
@Suite struct PathChangedWhileAskingTests {
    final class Flag: Sendable {
        private let state = Mutex(false)
        var isSet: Bool { state.withLock { $0 } }
        func set() { state.withLock { $0 = true } }
    }

    /// A folder shared for reading, with `shared/dir/file` and `other/file` inside the temp home.
    final class Place: @unchecked Sendable {
        let env: TestEnv
        let shared: String
        let other: String
        let ran = Flag()

        init() async throws {
            env = try TestEnv()
            let fm = FileManager.default
            let root = try #require(FolderAccess.canonical(env.home.path))
            shared = root + "/shared"
            other = root + "/other"
            try fm.createDirectory(atPath: shared + "/dir", withIntermediateDirectories: true)
            try fm.createDirectory(atPath: other, withIntermediateDirectories: true)
            try Data("a".utf8).write(to: URL(fileURLWithPath: shared + "/dir/file"))
            try Data("b".utf8).write(to: URL(fileURLWithPath: other + "/file"))
            try await env.permissions.grantFolder(shared, access: .read)
        }

        /// A high-risk tool reading `path`, so a card is always asked for it.
        func register(reading path: String) {
            let ran = self.ran
            env.registry.register(ProbeTool(name: "test.files", risk: .high, capabilities: [.filesRead], mutates: false,
                                            scope: { _ in ToolScope(readPaths: [FilePaths.scopePath(path)].compactMap { $0 }) },
                                            result: { _ in ran.set(); return ToolResult(text: "ok") }))
        }

        /// Answers the next card yes, after `before`.
        func answerYes(after before: @escaping @Sendable () -> Void = {}) -> Task<Void, Never> {
            let stream = env.events.stream(), broker = env.broker
            return Task {
                for await event in stream {
                    if case .approvalRequested(let request) = event {
                        before()
                        await broker.resolve(id: request.id, decision: .allowOnce)
                        return
                    }
                }
            }
        }

        func run() async -> ToolOutcome { await env.executor.execute(name: "test.files", input: [:], caller: .agent(runId: "r")) }
    }

    @Test func aLinkSwappedWhileTheCardWasUpDoesNotRun() async throws {
        let p = try await Place()
        p.register(reading: p.shared + "/dir/file")
        let (shared, other) = (p.shared, p.other)
        let answered = p.answerYes {
            // `shared/dir` becomes a link to `other`: the same name now leads outside the shared folder.
            try? FileManager.default.removeItem(atPath: shared + "/dir")
            try? FileManager.default.createSymbolicLink(atPath: shared + "/dir", withDestinationPath: other)
        }
        let out = await p.run()
        _ = await answered.value
        guard case .denied(let why) = out.status else { Issue.record("expected denied, got \(out.status)"); return }
        #expect(why.contains("changed while the question was waiting"), "\(why)")
        #expect(!p.ran.isSet, "the tool did not run")
        #expect(try await p.env.activity.recent()[0].decision == .blocked)
    }

    @Test func thePathResolvingTheSameRunsAsBefore() async throws {
        let p = try await Place()
        p.register(reading: p.shared + "/dir/file")
        let answered = p.answerYes()
        let out = await p.run()
        _ = await answered.value
        #expect(out.isOK && p.ran.isSet)
    }

    @Test func aTailMadeMeanwhileByAnEarlierStepIsTheSamePlace() async throws {
        let p = try await Place()
        let target = p.shared + "/dir/made-later"
        p.register(reading: target)
        let answered = p.answerYes { try? Data("c".utf8).write(to: URL(fileURLWithPath: target)) }
        let out = await p.run()
        _ = await answered.value
        #expect(out.isOK && p.ran.isSet, "a file that now exists where it was going to be is not a change")
    }

    @Test func aToolWithNoPathsIsNotAffected() async throws {
        let env = try TestEnv()
        env.registry.register(ProbeTool(risk: .medium))
        let answered = env.autoAnswer(.allowOnce)
        let out = await env.executor.execute(name: "test.probe", input: [:], caller: .agent(runId: "r"))
        _ = await answered.value
        #expect(out.isOK)
    }
}
