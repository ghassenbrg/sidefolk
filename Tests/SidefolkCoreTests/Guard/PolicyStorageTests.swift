import Foundation
import Testing
@testable import SidefolkCore

/// The Guard policy as stored (SQLite, never UserDefaults: SECURITY T8), and what older ones become (D37).
@Suite struct PolicyStorageTests {
    func stored(_ json: JSONValue) async throws -> GuardPolicy {
        let env = try TestEnv()
        try await KVStore(env.db).set("guard.policy", json)
        return try await env.permissions.policy()
    }

    @Test func aFreshInstallAsksOncePerKindAndSkipsAfterTenMinutes() async throws {
        let policy = try await TestEnv().permissions.policy()
        #expect(policy.mode == .askOncePerKind)
        #expect(policy.disabled.isEmpty)
        #expect(policy.unanswered == UnansweredRule(action: .skip, minutes: 10))
    }

    @Test func everythingSurvivesASaveAndLoad() async throws {
        let env = try TestEnv()
        let policy = GuardPolicy(mode: .fullAccess, disabled: [.shell, .clipboard], unanswered: UnansweredRule(action: .stop, minutes: 30))
        try await env.permissions.setPolicy(policy)
        #expect(try await env.permissions.policy() == policy)
        // Stored under readable names, so the file says what it means.
        let raw = try #require(try await KVStore(env.db).get("guard.policy", as: JSONValue.self))
        #expect(raw["mode"] == "fullAccess")
        #expect(raw["unanswered"]?["action"] == "stop")
    }

    @Test func theTwoOldModesBecomeTheirNewNames() async throws {
        let cautious = try await stored(["mode": "cautious", "disabled": ["shell", "network"]])
        #expect(cautious.mode == .askEveryTime)
        #expect(cautious.disabled == [.shell, .network])
        #expect(cautious.unanswered == UnansweredRule())

        let standard = try await stored(["mode": "standard", "disabled": []])
        #expect(standard.mode == .askOncePerKind)
    }

    @Test func nothingUnknownLoosensGuard() async throws {
        // A mode this version doesn't know reads as the default, never as more access.
        #expect(try await stored(["mode": "turbo"]).mode == .askOncePerKind)
        #expect(try await stored(["mode": 3]).mode == .askOncePerKind)
        // One capability it doesn't know doesn't turn the others back on.
        let partly = try await stored(["mode": "auto", "disabled": ["teleport", "shell"]])
        #expect(partly.mode == .auto)
        #expect(partly.disabled == [.shell])
        // A broken "If I don't answer" setting falls back to its default and keeps the rest.
        let broken = try await stored(["mode": "askEveryTime", "disabled": ["clipboard"], "unanswered": "soon"])
        #expect(broken.mode == .askEveryTime && broken.disabled == [.clipboard] && broken.unanswered == UnansweredRule())
        let odd = try await stored(["unanswered": ["action": "explode", "minutes": 5]])
        #expect(odd.unanswered == UnansweredRule(action: .skip, minutes: 5))
    }

    @Test func everyWaitEnds() {
        #expect(UnansweredRule(action: .skip, minutes: 10).waitMinutes == 10)
        #expect(UnansweredRule(action: .stop, minutes: 0).waitMinutes == 1)
        #expect(UnansweredRule(action: .skip, minutes: 100_000).waitMinutes == UnansweredRule.longestMinutes)
        let waiting = UnansweredRule(action: .keepWaiting, minutes: 10)
        #expect(waiting.waitMinutes == 24 * 60)
        #expect(waiting.whenTimeIsUp == .stop)
        #expect(UnansweredRule(action: .skip).whenTimeIsUp == .skip)
    }
}
