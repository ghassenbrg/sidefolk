import Foundation
import Testing
@testable import SidefolkCore

/// System Vitals rests while Your Mac (system-vitals-plus) is on (D67): its tools and new heads-ups step aside, Settings
/// says why, and it comes back by itself when Your Mac is off or gone. Only between Sidefolk's own.
struct ExtensionOverlapTests {
    @Test(.enabled(if: ExtFixtures.addonFolders.contains("system-vitals-plus"), ExtFixtures.noAddons))
    func systemVitalsRestsWhileYourMacIsOn() async throws {
        let h = try HostEnv()
        let small = try await h.host.install(from: ExtFixtures.builtIn("system-vitals"), origin: .bundled)
        #expect(h.env.registry.tool(named: "ext.system-vitals.battery") != nil)

        // Someone's own copy under the same id can't quiet a built-in.
        let byHand = try await h.host.install(from: ExtFixtures.builtIn("system-vitals-plus"))
        #expect(await h.host.info(id: small.id)?.restingFor == nil)
        #expect(h.env.registry.tool(named: "ext.system-vitals.battery") != nil)
        try await h.host.uninstall(id: byHand.id)

        let big = try await h.host.install(from: ExtFixtures.builtIn("system-vitals-plus"), origin: .official)
        #expect(await h.host.info(id: small.id)?.restingFor == "Your Mac")
        #expect(await h.host.info(id: small.id)?.enabled == true, "resting isn't switched off")
        #expect(h.env.registry.tool(named: "ext.system-vitals.battery") == nil)
        #expect(h.env.registry.tool(named: "ext.system-vitals-plus.battery") != nil)
        #expect(!(await h.host.watcherKinds()).contains { $0.extensionId == small.id })

        try await h.host.setEnabled(false, id: big.id)
        #expect(await h.host.info(id: small.id)?.restingFor == nil)
        #expect(h.env.registry.tool(named: "ext.system-vitals.battery") != nil)
        try await h.host.setEnabled(true, id: big.id)
        #expect(h.env.registry.tool(named: "ext.system-vitals.battery") == nil)
        try await h.host.uninstall(id: big.id)
        #expect(h.env.registry.tool(named: "ext.system-vitals.battery") != nil)
        await h.host.shutdown()
    }
}
