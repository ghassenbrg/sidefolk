import Foundation
import GRDB
import Testing
@testable import SidefolkCore

/// Running apart from shown, order, and what stands around a value (D116).
@Suite struct WatchManagementTests {
    let env: WatchEnv
    let sampler = FakeSampler()
    let engine: WatcherEngine

    init() throws {
        env = try WatchEnv()
        engine = env.reportEngine(sampler)
    }

    func run(_ tool: String, _ input: JSONValue, as caller: Caller = .user) async -> ToolOutcome {
        await env.base.executor.execute(name: tool, input: input, caller: caller)
    }

    func report(_ metric: String, as caller: Caller = .user) async throws -> Watcher {
        let outcome = await run("watch.report", ["source": "metric", "metric": .string(metric), "every_seconds": 60], as: caller)
        #expect(outcome.isOK, "\(outcome.status)")
        guard case .ok(let r) = outcome.status, let id = r.card?.refId, let w = await engine.watcher(id: id) else { throw CancellationError() }
        return w
    }

    // MARK: Order

    @Test func theOrderIsTheOrderMadeUntilArranged() async throws {
        let a = try await report("cpu"), b = try await report("memory"), c = try await report("disk")
        #expect(await engine.arranged().map(\.id) == [a.id, b.id, c.id])
        await engine.reorder([c.id, a.id, b.id])
        #expect(await engine.arranged().map(\.id) == [c.id, a.id, b.id])
        let d = try await report("battery")
        #expect(await engine.arranged().last?.id == d.id, "a new one comes last")
    }

    @Test func aPlaceHoldsAcrossALaunch() async throws {
        let a = try await report("cpu"), b = try await report("memory")
        await engine.reorder([b.id, a.id])
        let saved = try await env.store.all(limit: 10).sorted { $0.sortOrder < $1.sortOrder }.map(\.id)
        #expect(saved == [b.id, a.id])
    }

    @Test func arrangingSomeLeavesTheOthersInTheirPlaces() async throws {
        let a = try await report("cpu"), b = try await report("memory"), c = try await report("disk")
        await engine.reorder([c.id, a.id])
        #expect(await engine.arranged().map(\.id) == [c.id, b.id, a.id])
    }

    @Test func anAgentArrangesOnlyItsOwn() async throws {
        let codex = Caller.external(client: "codex")
        let mine = try await report("cpu")
        let theirs = try await report("memory", as: codex)
        let refused = await run("watch.reorder", ["ids": [.string(theirs.id), .string(mine.id)]], as: codex)
        #expect(!refused.isOK)
        #expect(await run("watch.reorder", ["ids": [.string(theirs.id)]], as: codex).isOK)
        #expect(await engine.arranged().map(\.id) == [mine.id, theirs.id])
    }

    @Test func undoPutsThemBack() async throws {
        let a = try await report("cpu"), b = try await report("memory")
        let outcome = await run("watch.reorder", ["ids": [.string(b.id), .string(a.id)]])
        _ = try await env.base.executor.undo.undo(outcome.activity.id)
        #expect(await engine.arranged().map(\.id) == [a.id, b.id])
    }

    // MARK: Where it shows

    @Test func aHiddenValueRunsOnAndFreesItsPlace() async throws {
        let a = try await report("cpu"), _ = try await report("memory"), _ = try await report("disk")
        let quiet = try await report("battery")
        #expect(quiet.display == .quiet)
        await #expect(throws: WatchError.self) { try await engine.setDisplay(quiet.id, .beside) }
        try await engine.setDisplay(a.id, .quiet)
        try await engine.setDisplay(quiet.id, .beside)
        #expect(await engine.watcher(id: a.id)?.state == .active)
    }

    @Test func aWatchForChangesHasNoPlaceToShow() async throws {
        let made = await run("watch.create", ["kind": "url_change", "target": "example.com/a"])
        guard case .ok(let r) = made.status, let id = r.card?.refId else { Issue.record("not made"); return }
        #expect(!(await run("watch.update", ["id": .string(id), "display": "quiet"])).isOK)
    }

    /// T29: other agents never take the last places beside the companion.
    @Test func otherAgentsTakeOnlySomeOfThePlaces() async throws {
        let codex = Caller.external(client: "codex")
        #expect(try await report("cpu", as: codex).display == .beside)
        #expect(try await report("memory", as: codex).display == .beside)
        #expect(try await report("disk", as: codex).display == .quiet)
        #expect(try await report("battery").display == .beside, "the person still has a place")
    }

    @Test func aValueSetToComeAndGoHasAMomentAtMostOnceAMinute() {
        var w = Watcher.make("fake", interval: 10, now: Date())
        w.mode = .report
        let at = Date()
        #expect(!WatchReading(w, value: "23%", at: at).dueItsMoment(last: nil), "beside the companion it has no moments")
        w.display = .notify
        let reading = WatchReading(w, value: "23%", at: at)
        #expect(reading.dueItsMoment(last: nil))
        #expect(!reading.dueItsMoment(last: at.addingTimeInterval(-30)))
        #expect(reading.dueItsMoment(last: at.addingTimeInterval(-60)))
        w.intervalS = 300
        #expect(!WatchReading(w, value: "23%", at: at).dueItsMoment(last: at.addingTimeInterval(-120)), "and at its own interval when that's longer")
    }

    /// What is set around a value is no part of the number read from it.
    @Test func aNumberIsReadFromTheValueAlone() {
        var w = Watcher.make("fake", interval: 60, now: Date())
        w.valuePrefix = "Q3"
        let r = WatchReading(w, value: "45%", at: Date())
        #expect(r.plain == "45%")
        #expect(WatchReading.number(in: r.plain) == 45)
    }

    @Test func aRepeatedIdInAnArrangementChangesNothingElse() async throws {
        let a = try await report("cpu"), b = try await report("memory"), c = try await report("disk")
        await engine.reorder([b.id, b.id, a.id, "nonsense"])
        #expect(await engine.arranged().map(\.id) == [b.id, a.id, c.id])
        #expect(Set(await engine.arranged().map(\.sortOrder)).count == 3)
    }

    /// Sidefolk's own agent runs under Auto and Full access without asking, so more room isn't for it to give.
    @Test func onlyAnotherAgentCanAskForMoreRoom() async throws {
        #expect(!(await run("watch.more_room", .object([:]), as: .agent(runId: "r"))).isOK)
        #expect(!(await run("watch.more_room", .object([:]))).isOK)
    }

    @Test func moreRoomHasACeiling() async throws {
        for _ in 0..<20 { _ = await engine.allowMoreExternalRoom() }
        #expect(await engine.allowMoreExternalRoom() == WatchLimits.externalRoomMost)
    }

    /// What runs without the person's words keeps a ceiling; theirs has none.
    @Test func whatNobodyAskedForDirectlyHasACeiling() async throws {
        let plain = env.engine(probes: [ScriptedProbe(minimumInterval: 1, script: { _, _ in ProbeResult(state: .object([:])) })])
        for _ in 0..<WatchLimits.maxUnattended { _ = try await plain.add(.make("fake", interval: 600, source: "routine:r1", now: env.clock.now)) }
        await #expect(throws: WatchError.self) { try await plain.add(.make("fake", interval: 600, source: "extension:x", now: env.clock.now)) }
        _ = try await plain.add(.make("fake", interval: 600, source: "user", now: env.clock.now))
    }

    @Test func anUnseenValueSendsNoNotificationOfItsOwnAccord() throws {
        var w = Watcher.make("fake", interval: 120, now: Date())
        w.mode = .report
        w.display = .quiet
        let reading = WatchReading(w, value: "23%", at: Date())
        #expect(!reading.notifies(companionVisible: false, quiet: false))
        w.display = .beside
        #expect(WatchReading(w, value: "23%", at: Date()).notifies(companionVisible: false, quiet: false))
    }

    // MARK: What stands around a value

    @Test func aValueWithNothingSetStaysExactlyAsItWas() {
        let w = Watcher.make("fake", interval: 60, now: Date())
        let r = WatchReading(w, value: "17.2 GB of 24 GB", at: Date())
        #expect(r.value == "17.2 GB of 24 GB")
        #expect(r.atRest == "17.2 GB")
    }

    @Test func aSignTakesNoSpaceAWordDoesAndTheNumberIsIsolated() {
        var w = Watcher.make("fake", interval: 60, now: Date())
        w.valuePrefix = "$"
        #expect(WatchReading(w, value: "45", at: Date()).value == "$\u{2068}45\u{2069}")
        w.valuePrefix = nil
        w.valueSuffix = "GPU"
        #expect(WatchReading(w, value: "45%", at: Date()).value == "\u{2068}45%\u{2069} GPU")
        w.valueSuffix = nil
        w.valuePrefix = "GPU"
        let r = WatchReading(w, value: "17.2 GB of 24 GB", at: Date())
        #expect(r.atRest == "GPU \u{2068}17.2 GB\u{2069}")
    }

    @Test func whatIsSetIsShortAndPlain() async throws {
        let w = try await report("cpu")
        try await engine.setValueAffixes(w.id, prefix: "  a\u{202E}verylongprefix\n", suffix: "   ")
        let after = try #require(await engine.watcher(id: w.id))
        #expect(after.valuePrefix?.count ?? 0 <= WatchLimits.maxAffix)
        #expect(after.valuePrefix?.unicodeScalars.contains("\u{202E}") == false)
        #expect(after.valueSuffix == nil)
    }

    @Test func theToolSetsThemAndUndoTakesThemBack() async throws {
        let w = try await report("cpu")
        let outcome = await run("watch.update", ["id": .string(w.id), "suffix": "GPU", "display": "notify"])
        #expect(outcome.isOK)
        #expect(await engine.watcher(id: w.id)?.valueSuffix == "GPU")
        #expect(await engine.watcher(id: w.id)?.display == .notify)
        _ = try await env.base.executor.undo.undo(outcome.activity.id)
        #expect(await engine.watcher(id: w.id)?.valueSuffix == nil)
        #expect(await engine.watcher(id: w.id)?.display == .beside)
    }

    // MARK: Agents

    @Test func agentsGetTheManagingToolsForTheirOwn() async throws {
        let codex = Caller.external(client: "codex")
        let mine = try await report("cpu")
        let theirs = try await report("memory", as: codex)
        for tool in ["watch.pause", "watch.resume", "watch.update"] {
            #expect(ExternalToolPolicy.saving.contains(tool))
            #expect(!(await run(tool, ["id": .string(mine.id)], as: codex)).isOK, "\(tool) on the person's")
            #expect(await run(tool, ["id": .string(theirs.id)], as: codex).isOK, "\(tool) on its own")
        }
    }

    /// No setting makes asking for more room automatic.
    @Test func moreRoomIsAlwaysAsked() {
        var access = AgentAccess()
        access.save = .allow
        #expect(ExternalToolPolicy.permission("watch.more_room", access: access) == .ask)
        #expect(ExternalToolPolicy.all.contains("watch.more_room"))
    }

    // MARK: From before

    @Test func aFourthFromBeforeRunsQuietlyWhereItCanBeFound() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            for n in 0..<5 {
                try db.execute(sql: """
                    INSERT INTO watchers (id, kind, title, config, condition, interval_s, state, mode, level, error_count, fire_count, source, created_at, updated_at)
                    VALUES (?, 'metric', 't', '{}', '{}', 10, ?, 'report', 'attention', 0, 0, 'user', ?, 0)
                    """, arguments: ["w\(n)", n == 4 ? "expired" : "active", Double(n)])
            }
            try db.execute(sql: AppDatabase.fourthLiveValueRunsQuietly)
            let quiet = try String.fetchAll(db, sql: "SELECT id FROM watchers WHERE display = 'quiet'")
            #expect(quiet == ["w3"])
        }
    }

    @Test func watchersFromBeforeStayBesideInTheirOrder() async throws {
        try await env.base.db.writer.write { db in
            let row = try #require(try Row.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'watchers'"))
            let sql: String = row["sql"]
            #expect(sql.contains("\"display\" TEXT NOT NULL DEFAULT 'beside'"))
            #expect(sql.contains("\"sort_order\" INTEGER NOT NULL DEFAULT 0"))
        }
    }
}
