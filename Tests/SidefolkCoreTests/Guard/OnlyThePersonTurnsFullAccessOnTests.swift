import Foundation
import Testing
@testable import SidefolkCore

/// Full access is the person's own click on the sheet's button (D185). No tool, for Sidefolk's agent, other agents,
/// extensions, routines or a plan, can change Guard's policy; the app code that can is the Settings sheet and the menu bar,
/// and the menu bar can't choose Full access.
@Suite struct OnlyThePersonTurnsFullAccessOnTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private func swiftFiles(_ folder: String) throws -> [URL] {
        let files = try #require(FileManager.default.enumerator(at: Self.root.appendingPathComponent(folder), includingPropertiesForKeys: nil))
        return files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test func noCoreCodeWritesThePolicyExceptItsStore() throws {
        var writers: [String] = []
        let files = try swiftFiles("Sources/SidefolkCore")
        for file in files where file.lastPathComponent != "PermissionStore.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("updatePolicy(") || text.contains("setPolicy(") || text.contains("guard.policy") { writers.append(file.lastPathComponent) }
        }
        #expect(files.count > 100)
        #expect(writers.isEmpty, "Core code that can change Guard's policy: \(writers)")
    }

    @Test func noToolOfferedToAnotherCallerIsAboutGuardSettings() {
        let aboutGuard = ["policy", "guard", "permission", "approval", "mode", "fullaccess", "full_access", "trust"]
        let offered = ExternalToolPolicy.all.union(ExtensionActionPolicy.builtIn)
        let bad = offered.filter { name in aboutGuard.contains { name.lowercased().contains($0) } }
        #expect(!offered.isEmpty)
        #expect(bad.isEmpty, "\(bad)")
    }

    @Test func onlySidefolkOwnAgentAndItsTypedCommandsGetTheMode() {
        let policy = GuardPolicy(mode: .fullAccess)
        for caller in [Caller.external(client: "claude-code"), .extension(id: "dev.x.y"), .routine(id: "r")] {
            #expect(policy.mode(for: caller) == .askOncePerKind, "\(caller)")
        }
        #expect(policy.mode(for: .agent(runId: "r")) == .fullAccess)
        #expect(policy.mode(for: .command(extensionId: "dev.x.y")) == .fullAccess)
    }

    /// A plan (D110) is a card the person read; it runs under Guard as the extension, whose mode is never Full access.
    @Test func aPlanOrAnExtensionCallIsNotFullAccess() {
        let spec = ToolSpec(name: "t.x", title: "X", description: "", inputSchema: .object([:]), risk: .medium, capabilities: [.extensions],
                            category: .extensions, mutates: true)
        let decision = PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: .none, caller: .extension(id: "dev.x.y"),
                                                   tainted: true, policy: GuardPolicy(mode: .fullAccess), grants: [], folders: [])
        guard case .ask = decision else { Issue.record("an extension's call under Full access must still ask: \(decision)"); return }
    }

    @Test func fullAccessOnlyTurnsOnThroughChoose() throws {
        // The app's one way in: `GuardPolicy.choose`, called with Full access only from the sheet's button and the debug snapshots.
        var callers: [String] = []
        for file in try swiftFiles("Sources/SidefolkApp") where !file.path.contains("/Dev/") {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains(".choose(.fullAccess") || text.contains("mode = .fullAccess") { callers.append(file.lastPathComponent) }
        }
        #expect(callers.isEmpty, "Full access is chosen through SettingsModel.setMode(_:fullAccessEnds:) only: \(callers)")
    }
}
