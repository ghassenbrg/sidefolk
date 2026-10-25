import Darwin
import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

struct TrackerEnv {
    let env: TestEnv
    let attention: AttentionCenter
    let sessions: SessionTracker
    let jobs: JobTracker
    let opened = BridgeRecorder<[String]>([])

    init() async throws {
        env = try TestEnv()
        attention = AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock)
        sessions = SessionTracker(store: SessionStore(env.db), attention: attention, events: env.events, clock: env.clock)
        jobs = JobTracker(store: JobStore(env.db), attention: attention, events: env.events, clock: env.clock)
        let opened = self.opened
        await sessions.setOpenHandler { session in opened.value.withLock { $0.append(session.id) } }
        await sessions.start()
    }

    /// Attention items, oldest first.
    func items() async throws -> [AttentionItem] { try await AttentionStore(env.db).recent().reversed() }

    func event(_ name: String, _ build: (inout SessionEvent) -> Void = { _ in }) -> SessionEvent {
        var e = SessionEvent(event: name, sessionId: "s1", cwd: "/Users/me/git/sidefolk", hostBundleId: "com.apple.Terminal", hostPid: 4242)
        build(&e)
        return e
    }
}

@Suite struct SessionTrackerTests {
    @Test func aSessionNeedsYouThenFinishes() async throws {
        let t = try await TrackerEnv()
        var s = await t.sessions.apply(t.event("UserPromptSubmit") { $0.prompt = "Fix the flaky socket test" })
        #expect(s?.state == .working)
        #expect(s?.title == "Fix the flaky socket test")
        #expect(s?.hostApp == "com.apple.Terminal")
        #expect(try await t.items().isEmpty)

        t.env.clock.advance(30)
        s = await t.sessions.apply(t.event("Notification") {
            $0.message = "Claude needs your permission to use Bash"
            $0.notificationType = "permission_prompt"
        })
        #expect(s?.state == .needsYou)
        var items = try await t.items()
        #expect(items.count == 1)
        #expect(items[0].title == "Claude needs you in sidefolk")
        #expect(items[0].body == "Claude needs your permission to use Bash")
        #expect(items[0].actions.map(\.id) == ["open", "dismiss"])
        #expect(items[0].actions.first?.isPrimary == true)

        // The same notification again doesn't tap again.
        await t.sessions.apply(t.event("Notification") { $0.notificationType = "permission_prompt" })
        #expect(try await t.items().count == 1)

        // Answered in the terminal: the bubble goes away.
        await t.sessions.apply(t.event("PreToolUse") { $0.toolName = "Bash" })
        items = try await t.items()
        #expect(items[0].state == .acknowledged)

        t.env.clock.advance(180)
        s = await t.sessions.apply(t.event("Stop"))
        #expect(s?.state == .idle)
        items = try await t.items()
        #expect(items.count == 2)
        #expect(items[1].title == "Claude finished in sidefolk")
        #expect(items[1].level == .attention)

        // A repeated Stop and the later "waiting for your input" don't tap again.
        await t.sessions.apply(t.event("Stop"))
        await t.sessions.apply(t.event("Notification") { $0.notificationType = "idle_prompt" })
        #expect(try await t.items().count == 2)

        s = await t.sessions.apply(t.event("SessionEnd"))
        #expect(s?.state == .finished)
        #expect(s?.endedAt != nil)
        #expect(try await SessionStore(t.env.db).live().isEmpty)
    }

    @Test func shortWorkEndsGently() async throws {
        let t = try await TrackerEnv()
        await t.sessions.apply(t.event("UserPromptSubmit") { $0.prompt = "hi" })
        t.env.clock.advance(20)
        await t.sessions.apply(t.event("Stop"))
        let items = try await t.items()
        #expect(items.count == 1)
        #expect(items[0].level == .gentle)
    }

    @Test func openRoutesToTheHostApp() async throws {
        let t = try await TrackerEnv()
        await t.sessions.apply(t.event("Notification") { $0.message = "Waiting" })
        let item = try #require(try await t.items().first)
        await t.attention.respond(id: item.id, actionId: "open")
        #expect(t.opened.value.withLock { $0 } == ["s1"])
    }

    @Test func eventsAreValidatedAndCapped() {
        let long = String(repeating: "word ", count: 100) + "\nsecond line"
        let e = SessionEvent(json: ["agent": "claude-code", "event": "UserPromptSubmit", "session_id": "abc-123",
                                    "prompt": .string(long), "cwd": "relative/path", "tty": "/etc/passwd", "host_pid": 1])
        #expect(e != nil)
        #expect(e?.prompt?.count ?? 0 <= 120)
        #expect(e?.prompt?.contains("second") == false)
        #expect(e?.cwd == nil)
        #expect(e?.tty == nil)
        #expect(e?.hostPid == nil)
        #expect(SessionEvent(json: ["agent": "claude-code", "event": "Stop"]) == nil)
        #expect(SessionEvent(json: ["agent": "claude code; rm", "event": "Stop", "session_id": "x"]) == nil)
    }
}

@Suite struct JobTrackerTests {
    @Test func finishedJobTapsWithItsDuration() async throws {
        let t = try await TrackerEnv()
        let job = await t.jobs.start(JobReport(title: "npm test", command: "npm test", cwd: "/tmp/app", pid: 123), client: "sidefolk-cli")
        #expect(job.state == .running)
        #expect(job.source == "external:sidefolk-cli")
        t.env.clock.advance(252)
        let done = await t.jobs.finish(JobReport(id: job.id, title: "npm test", exitCode: 0), client: "sidefolk-cli")
        #expect(done.state == .succeeded)
        let item = try #require(try await t.items().last)
        #expect(item.title == "npm test finished in 4m 12s")
        #expect(item.level == .attention)
        #expect(item.actions.map(\.title) == ["Dismiss"])
    }

    @Test func failedJobSaysTheExitCode() async throws {
        let t = try await TrackerEnv()
        let job = await t.jobs.start(JobReport(title: "make", pid: 1234), client: "cli")
        let done = await t.jobs.finish(JobReport(id: job.id, title: "make", exitCode: 2, durationSeconds: 95), client: "cli")
        #expect(done.state == .failed)
        #expect(done.exitCode == 2)
        #expect(try await t.items().last?.title == "make failed (exit 2)")
    }

    @Test func shortJobsAreGentle() async throws {
        let t = try await TrackerEnv()
        let job = await t.jobs.start(JobReport(title: "ls"), client: "cli")
        await t.jobs.finish(JobReport(id: job.id, title: "ls", exitCode: 0, durationSeconds: 2), client: "cli")
        let item = try #require(try await t.items().last)
        #expect(item.level == .gentle)
        #expect(item.title == "ls finished in 2s")
    }

    @Test func finishWithoutStartIsRecorded() async throws {
        let t = try await TrackerEnv()
        let job = await t.jobs.finish(JobReport(title: "cargo build", exitCode: 0, durationSeconds: 600), client: "cli")
        #expect(job.state == .succeeded)
        #expect(try await JobStore(t.env.db).job(id: job.id)?.endedAt != nil)
        // Finishing twice changes nothing.
        await t.jobs.finish(JobReport(id: job.id, title: "cargo build", exitCode: 1), client: "cli")
        #expect(try await JobStore(t.env.db).job(id: job.id)?.state == .succeeded)
    }

    @Test func reconcileCancelsJobsWhoseProcessIsGone() async throws {
        let t = try await TrackerEnv()
        let pid = try PosixSpawn.run("/usr/bin/true", arguments: [], environment: [:], searchPath: false, options: .init())
        _ = PosixSpawn.wait(pid)
        let gone = await t.jobs.start(JobReport(title: "gone", pid: Int(pid)), client: "cli")
        let alive = await t.jobs.start(JobReport(title: "alive", pid: Int(getpid())), client: "cli")
        #expect(await t.jobs.reconcile() == 1)
        #expect(try await JobStore(t.env.db).job(id: gone.id)?.state == .cancelled)
        #expect(try await JobStore(t.env.db).job(id: alive.id)?.state == .running)
    }

    @Test func durations() {
        #expect(JobTracker.formatDuration(4) == "4s")
        #expect(JobTracker.formatDuration(252) == "4m 12s")
        #expect(JobTracker.formatDuration(3780) == "1h 3m")
    }
}

@Suite struct AgentFacingToolsTests {
    @Test func notifyPostsWithTheCallersSource() async throws {
        let t = try await TrackerEnv()
        let tools = AgentFacingTools.make(attention: t.attention)
        t.env.registry.register(tools)
        let out = await t.env.executor.execute(name: "notify.user", input: ["title": "Tests passed", "level": "attention"],
                                               caller: .external(client: "codex"))
        #expect(out.isOK)
        let item = try #require(try await t.items().last)
        #expect(item.source == "external:codex")
        #expect(item.level == .attention)
    }

    @Test func askReturnsTheChosenOption() async throws {
        let t = try await TrackerEnv()
        t.env.registry.register(AgentFacingTools.make(attention: t.attention))
        let stream = t.env.events.stream()
        let attention = t.attention
        let answerer = Task {
            for await e in stream {
                if case .attention(.present(let item, _)) = e, item.refKind == "ask" {
                    await attention.respond(id: item.id, actionId: item.actions[1].id)
                    return
                }
            }
        }
        let out = await t.env.executor.execute(name: "ask.user", input: ["question": "Deploy now?", "options": ["Yes", "Later"]],
                                               caller: .external(client: "claude-code"))
        await answerer.value
        guard case .ok(let result) = out.status else { Issue.record("expected ok"); return }
        #expect(result.text == "Later")
    }

    @Test func askNeedsTwoToFourOptions() async throws {
        let t = try await TrackerEnv()
        t.env.registry.register(AgentFacingTools.make(attention: t.attention))
        let out = await t.env.executor.execute(name: "ask.user", input: ["question": "?", "options": ["Only one"]], caller: .user)
        #expect(!out.isOK)
    }

    @Test func statusCountsOnly() async throws {
        let t = try await TrackerEnv()
        t.env.registry.register(AgentFacingTools.status(StatusReader(db: t.env.db)))
        _ = await t.jobs.start(JobReport(title: "secret project build"), client: "cli")
        let out = await t.env.executor.execute(name: "status", input: [:], caller: .external(client: "x"))
        guard case .ok(let result) = out.status else { Issue.record("expected ok"); return }
        #expect(result.text.contains("1 job running"))
        #expect(!result.text.contains("secret"))
    }
}
