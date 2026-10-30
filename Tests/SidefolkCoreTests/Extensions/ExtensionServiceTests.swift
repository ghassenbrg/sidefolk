import Foundation
import Testing
@testable import SidefolkCore

/// Extensions that keep running and act (D63): the clipboard and power permissions, background extensions, palettes,
/// switches and buttons on pages, and the nudge. A fixture stands in for Clipboard, so the person's own clipboard is
/// never read or changed; Keep Awake runs for real.
struct ExtensionServiceTests {
    static let fixture = #"""
    import json, sys
    def send(o):
        sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
    items = [{"id": "a", "title": "first copy", "kind": "text", "actions": ["pin", "delete"]},
             {"id": "b", "title": "https://example.com", "kind": "link", "pinned": True, "actions": ["plain", "evil"]}]
    for line in sys.stdin:
        m = json.loads(line)
        if "id" not in m: continue
        meth, p = m["method"], m.get("params") or {}
        if meth == "initialize": r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "f", "version": "1"}}
        elif meth == "tools/list": r = {"tools": [{"name": "nudge_me", "description": "Sends a nudge.", "inputSchema": {"type": "object"}}]}
        elif meth == "tools/call":
            send({"jsonrpc": "2.0", "method": "sidefolk/nudge", "params": {}})
            r = {"content": [{"type": "text", "text": "nudged"}]}
        elif meth == "sidefolk/palette.query":
            q = p.get("query", "")
            r = {"items": [i for i in items if q in i["title"]], "note": "2 kept"}
        elif meth == "sidefolk/palette.choose":
            r = {"close": p["action"] == "choose", "paste": p["action"] == "choose", "message": "chose " + p["item"] + " " + p["action"]}
        else:
            send({"jsonrpc": "2.0", "id": m["id"], "error": {"code": -32601, "message": "nope"}}); continue
        send({"jsonrpc": "2.0", "id": m["id"], "result": r})
    """#

    static func makeFixture(power: Bool, background: Bool = true) throws -> URL {
        let folder = try ExtFixtures.tempDir("service").appendingPathComponent("fixture")
        return try ExtFixtures.makeExtension(at: folder, manifest: ExtFixtures.manifest(
            id: "dev.test.service", tools: ["nudge_me": ["risk": "low"]], permissions: ["power": .bool(power)],
            extra: ["background": .bool(background), "sidefolk": ">=0.2",
                    "palettes": ["history": ["title": "History", "hotkey": "shift+cmd+c", "placeholder": "Search"]]]),
            files: ["server.py": fixture])
    }

    @Test func theManifestSaysWhatItMayDo() throws {
        let m = try ExtensionManifest.decode(Data("""
            {"id": "dev.example.c", "name": "C", "version": "1.0", "run": {"command": "bin/x"}, "background": true,
             "permissions": {"clipboard": true, "power": true},
             "palettes": {"history": {"title": "Clipboard", "hotkey": "shift+cmd+c"}, "bad": {"title": "B", "hotkey": "shift+v"}}}
            """.utf8))
        #expect(m.background && m.permissions.clipboard && m.permissions.power)
        var issues: [ValidationIssue] = []
        ManifestValidator(paths: SidefolkPaths(home: try ExtFixtures.tempDir("svc-home"))).checkPalettes(m, issues: &issues)
        #expect(issues.map(\.field) == ["palettes.bad.hotkey"], "a shortcut needs cmd, ctrl or option")

        let summary = PermissionSummary.forExtension(ExtensionPermissions(network: true, clipboard: true, power: true))
        #expect(summary.lines.map(\.kind).contains(.clipboard) && summary.lines.map(\.kind).contains(.power))
        #expect(summary.warnings.contains { $0.contains("what you copy") }, "the clipboard and the internet together")
        #expect(ExtensionPermissions(clipboard: true).raisesRiskFloor && !ExtensionPermissions(power: true).raisesRiskFloor)
    }

    @Test func theSandboxOpensOnlyWhatWasGranted() throws {
        let dir = try ExtFixtures.tempDir("svc-sb")
        func profile(_ p: ExtensionPermissions) throws -> String {
            try SandboxProfile.make(.init(extensionDir: dir.path, dataDir: dir.path, executable: "/usr/bin/true", permissions: p)).text
        }
        let none = try profile(ExtensionPermissions())
        #expect(!none.contains("com.apple.pasteboard.1") && !none.contains("PowerManagement"))
        #expect(none.contains("com.apple.cache_delete.public"), "free space as System Settings counts it, for everyone")
        #expect(try profile(ExtensionPermissions(clipboard: true)).contains("com.apple.pasteboard.1"))
        #expect(try profile(ExtensionPermissions(power: true)).contains("com.apple.PowerManagement.control"))
        #expect(!(try profile(ExtensionPermissions(clipboard: true)).contains("launchservicesd")), "never Launch Services: it opens apps and links")
    }

    @Test func listsAndControlsAreReadStrictly() throws {
        let list = ExtensionPaletteList.parse(try ExtensionPageTests.json("""
            {"items": [{"id": "a", "title": "one\\u202e two", "kind": "link", "actions": ["pin", "rm -rf", "plain"]},
                       {"id": "", "title": "no id"}, {"id": "c", "title": "   "}], "note": "3 kept"}
            """))
        #expect(list.items.map(\.id) == ["a"] && list.items[0].kind == .link && list.items[0].actions == ["pin", "plain"])
        #expect(!list.items[0].title.contains("\u{202E}") && list.note == "3 kept")

        let page = try ExtensionPage.parse(try ExtensionPageTests.json("""
            {"sections": [{"blocks": [
              {"type": "switch", "label": "Keep the screen on", "on": true, "tool": "set_option", "input": {"option": "screen"}},
              {"type": "button", "label": "Stop", "tool": "stop_keeping_awake", "style": "destructive"},
              {"type": "button", "label": "Other's", "tool": "ext.other.tool"}]}]}
            """))
        let blocks = page.sections[0].blocks
        #expect(blocks.count == 2, "a tool name is the extension's own, never a registry name")
        guard case .control(let toggle) = blocks[0], case .control(let stop) = blocks[1] else { Issue.record("\(blocks)"); return }
        #expect(toggle.kind == .toggle(on: true) && stop.kind == .button(.destructive))
        #expect(toggle.input(switchedTo: false) == ["option": "screen", "on": false])
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aBackgroundExtensionKeepsRunningAndItsPaletteWorks() async throws {
        let h = try HostEnv { $0.idleTimeout = 1 }
        let info = try await h.host.install(from: try Self.makeFixture(power: true))
        try await Task.sleep(for: .seconds(2.5))
        #expect(await h.host.isRunning(info.id), "a background extension doesn't stop for being idle")

        let palettes = await h.host.palettes()
        #expect(palettes.map(\.id) == ["dev.test.service/history"] && palettes.first?.hotkey == "shift+cmd+c")
        let all = try await h.host.queryPalette(extensionId: info.id, palette: "history", query: "")
        #expect(all.items.map(\.id) == ["a", "b"] && all.items[1].pinned && all.items[1].actions == ["plain"] && all.note == "2 kept")
        #expect(try await h.host.queryPalette(extensionId: info.id, palette: "history", query: "example").items.map(\.id) == ["b"])
        let chosen = try await h.host.choosePalette(extensionId: info.id, palette: "history", item: "a", action: "choose")
        #expect(chosen == ExtensionPaletteChoice(close: true, paste: true, message: "chose a choose"))
        await #expect(throws: UserFacingError.self) { try await h.host.choosePalette(extensionId: info.id, palette: "history", item: "a", action: "Run Me") }

        // Off, it stops, and its palette and shortcut go with it.
        try await h.host.setEnabled(false, id: info.id)
        let stopped = await h.host.isRunning(info.id)
        let left = await h.host.palettes()
        #expect(!stopped && left.isEmpty)
        try await h.host.setEnabled(true, id: info.id)
        try await Task.sleep(for: .seconds(1))
        #expect(await h.host.isRunning(info.id), "on again, it starts by itself")
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func onlyThePowerPermissionNudgesAndAtMostEveryTwentySeconds() async throws {
        for power in [true, false] {
            let h = try HostEnv()
            let stream = h.env.events.stream()
            let info = try await h.host.install(from: try Self.makeFixture(power: power, background: false))
            let counter = Task {
                var n = 0
                for await event in stream { if case .nudge = event { n += 1 } }
                return n
            }
            for _ in 0..<3 { _ = await h.call("ext.service.nudge_me") }
            try await Task.sleep(for: .milliseconds(500))
            counter.cancel()
            let nudges = await counter.value
            #expect(nudges == (power ? 1 : 0), "power \(power): \(nudges) nudges")
            _ = info
            await h.host.shutdown()
        }
    }

    @Test(.enabled(if: ExtFixtures.addonFolders.contains("keep-awake"), ExtFixtures.noAddons))
    func keepAwakeHoldsAndLetsGo() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: ExtFixtures.builtIn("keep-awake"))
        #expect(info.tools.allSatisfy { $0.risk == .low })
        // The Mac (not the screen) for a minute: the gentlest hold there is, released below.
        let held = try #require(await h.call("ext.keep-awake.keep_awake", ["minutes": 1, "screen": false]).okText)
        #expect(held.hasPrefix("Awake until") && held.contains("Screen may sleep"), "\(held)")
        let page = try await h.host.renderPage(extensionId: info.id, page: "awake")
        #expect(page.summary?.title.hasPrefix("Awake until") == true)
        #expect(page.sections.flatMap(\.blocks).contains { if case .control(let c) = $0 { c.tool == "stop_keeping_awake" } else { false } })
        let nowhere = await h.call("ext.keep-awake.keep_awake", ["while_app": "No Such App Anywhere"])
        #expect(nowhere.okText == nil || nowhere.okText?.contains("isn't open") == true)
        let stopped = try #require(await h.call("ext.keep-awake.stop_keeping_awake").okText)
        #expect(stopped.contains("sleeps as usual"), "\(stopped)")
        await h.host.shutdown()
    }
}
