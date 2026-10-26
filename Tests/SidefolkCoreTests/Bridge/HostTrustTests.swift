import Darwin
import Foundation
import Testing
@testable import SidefolkCore

/// SECURITY T4: a session event's host app is self-reported, so "Open" only ever raises an app that is
/// really above the sender, or a well-known terminal or editor.
@Suite struct HostTrustTests {
    /// sender 500 → claude 400 → shell 300 → editor 200 (an app) → launchd.
    let tree = HostTrust.Processes(
        parent: { [500: 400, 400: 300, 300: 200, 200: 1, 777: 1][$0] },
        bundleId: { [200: "com.example.Editor", 777: "com.evil.Phish"][$0] })

    func event(pid: Int?, bundle: String?) -> SessionEvent {
        SessionEvent(event: "Notification", sessionId: "s1", hostBundleId: bundle, hostPid: pid)
    }

    @Test func anAncestorIsTrustedAndNamedByItsOwnBundle() {
        let e = HostTrust.verified(event(pid: 200, bundle: "com.apple.Terminal"), peer: 500, processes: tree)
        #expect(e.hostPid == 200)
        #expect(e.hostBundleId == "com.example.Editor", "read from the process, not the payload")
    }

    @Test func aPidOutsideTheSendersTreeIsDropped() {
        let forged = HostTrust.verified(event(pid: 777, bundle: "com.evil.Phish"), peer: 500, processes: tree)
        #expect(forged.hostPid == nil)
        #expect(forged.hostBundleId == nil)

        // A well-known terminal is still fine to raise by bundle id: it's the user's own.
        let terminal = HostTrust.verified(event(pid: 777, bundle: "com.apple.Terminal"), peer: 500, processes: tree)
        #expect(terminal.hostPid == nil)
        #expect(terminal.hostBundleId == "com.apple.Terminal")
        // As is the helper's no-pid fallback (tmux, iTerm2's server process).
        #expect(HostTrust.verified(event(pid: nil, bundle: "com.googlecode.iterm2"), peer: 500, processes: tree).hostBundleId
            == "com.googlecode.iterm2")
        #expect(HostTrust.verified(event(pid: nil, bundle: "com.evil.Phish"), peer: 500, processes: tree).hostBundleId == nil)
    }

    @Test func edgesOfTheWalk() {
        // Without the sender's pid nothing can be checked; launchd, the sender itself and processes
        // that aren't apps never count.
        #expect(HostTrust.verified(event(pid: 200, bundle: nil), peer: nil, processes: tree).hostPid == nil)
        #expect(HostTrust.verified(event(pid: 1, bundle: nil), peer: 500, processes: tree).hostPid == nil)
        #expect(HostTrust.verified(event(pid: 500, bundle: nil), peer: 500, processes: tree).hostPid == nil)
        #expect(HostTrust.verified(event(pid: 300, bundle: nil), peer: 500, processes: tree).hostPid == nil)
        // A loop in a (racing) process table ends.
        let loop = HostTrust.Processes(parent: { [10: 11, 11: 10][$0] }, bundleId: { _ in "x" })
        #expect(!HostTrust.isAncestor(99, of: 10, loop))
    }

    @Test func aStoredPidIsUsedOnlyWhileItStillRunsThatApp() {
        var s = AgentSession(id: "s1", agent: "claude-code", cwd: nil, state: .needsYou)
        s.hostPid = 200
        s.hostApp = "com.example.Editor"
        #expect(HostTrust.target(for: s, processes: tree) == (200, "com.example.Editor"))
        // The editor quit and its pid now belongs to something else.
        let reused = HostTrust.Processes(parent: tree.parent, bundleId: { $0 == 200 ? "com.evil.Phish" : nil })
        #expect(HostTrust.target(for: s, processes: reused) == (nil, "com.example.Editor"))
    }

    @Test func theRealProcessTreeIsWalked() throws {
        #expect(HostTrust.isAncestor(getppid(), of: getpid(), .live))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["5"]
        try child.run()
        defer { child.terminate() }
        #expect(!HostTrust.isAncestor(child.processIdentifier, of: getpid(), .live))
    }

    /// End to end: a forged host pid sent over the socket never reaches the stored session.
    @Test func aForgedHostNeverReachesTheSession() async throws {
        let h = try BridgeHarness().start()
        defer { h.stop() }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["5"]
        try child.run()
        defer { child.terminate() }

        let client = try await h.connect(client: "sidefolk-hook")
        defer { client.close() }
        _ = try await client.call("session/event", event(pid: Int(child.processIdentifier), bundle: "com.evil.Phish").json)
        var stored = try #require(try await SessionStore(h.env.db).session(id: "s1"))
        #expect(stored.hostPid == nil)
        #expect(stored.hostApp == nil)

        _ = try await client.call("session/event", event(pid: nil, bundle: "com.apple.Terminal").json)
        stored = try #require(try await SessionStore(h.env.db).session(id: "s1"))
        #expect(stored.hostApp == "com.apple.Terminal")
    }
}
