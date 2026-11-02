import Foundation
import Testing
@testable import SidefolkCore

struct ExtensionKitProtocolTests {
    @Test func noticesAreDeliveredWhileARequestIsAwaiting() throws {
        let dir = try ExtFixtures.tempDir("kit-notices")
        defer { try? FileManager.default.removeItem(at: dir) }
        let main = dir.appendingPathComponent("main.swift")
        let binary = dir.appendingPathComponent("probe")
        let source = #"""
        import Foundation
        let ext = Extension(name: "probe")
        var sawNotice = false
        ext.on("probe/notice") { _ in sawNotice = true }
        ext.tool("wait", "Wait", "Waits briefly.") { _ in
            ext.send("probe/started")
            try await Task.sleep(for: .milliseconds(300))
            return sawNotice ? "notice arrived" : "notice was late"
        }
        await ext.serve()
        """#
        try Data(source.utf8).write(to: main)
        let kit = ExtFixtures.repoRoot.appendingPathComponent("extensions/Kit")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        // The whole Kit, as an extension's package builds it: its files depend on each other.
        let kitFiles = try FileManager.default.contentsOfDirectory(at: kit, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }.map(\.path).sorted()
        compiler.arguments = kitFiles + [main.path, "-o", binary.path]
        compiler.standardOutput = FileHandle.nullDevice
        compiler.standardError = FileHandle.nullDevice
        try compiler.run(); compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)
        guard compiler.terminationStatus == 0 else { return }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = binary
        process.standardInput = input; process.standardOutput = output
        try process.run()
        let call = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"wait","arguments":{}}}"# + "\n"
        try input.fileHandleForWriting.write(contentsOf: Data(call.utf8))
        let started = output.fileHandleForReading.availableData
        #expect(String(decoding: started, as: UTF8.self).contains("probe/started"))
        let notice = #"{"jsonrpc":"2.0","method":"probe/notice","params":{}}"# + "\n"
        try input.fileHandleForWriting.write(contentsOf: Data(notice.utf8))
        try input.fileHandleForWriting.close()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: result, as: UTF8.self).contains("notice arrived"))
    }

    /// The Kit's side of D100, end to end in the sandbox: a program built on it declares settings, draws every richer part, asks the AI,
    /// adds a History row and receives what it used to have.
    @Test func theKitSpeaksEveryAbility() async throws {
        let source = #"""
        import Foundation
        let ext = Extension(name: "kit-abilities")
        ext.carry { section, values in ["tone": values.string("mood") ?? ""] }
        ext.tool("says", "Says", "Says the settings.") { _ in "\(ExtensionSettings.string("tone") ?? "?")/\(ExtensionSettings.bool("loud") ?? false)" }
        ext.tool("quiet", "Quiet", "Turns loud off.") { _ in
            ExtensionSettings.set("loud", false)
            return "ok"
        }
        ext.tool("note", "Note", "A row.") { _ in
            Activity.add("Did a thing", key: "thing", result: "done")
            return "ok"
        }
        ext.tool("ask", "Ask", "Asks the AI.") { _ in
            guard let name = AI.available else { return "no AI" }
            switch await AI.ask("Write a word.", label: "A word", seconds: 5) {
            case .answer(let text, let madeBy): return "\(text) by \(madeBy), offered by \(name)"
            case .refused(let why): return "refused: \(why)"
            }
        }
        ext.page("all") { _ in
            Page(summary: Summary("All"), sections: [
                Section(nil, [.hero(Hero("All", scene: .pack("a.png", dark: "b.png"), figure: .companion(.full), says: "Hi"))]),
                Section(nil, [.stats([StatItem("Wins", "3", symbol: "star")])]),
                Section("Grid", [.cards(size: .small, [Card("One", detail: "d", at: Date(timeIntervalSince1970: 0), picture: .person, badge: Badge("New"), done: true,
                                                            actions: [Action("Go", tool: "says", style: .primary)], menu: (label: "More", items: [Action("Also", tool: "says")]))])],
                        picture: .companion(.face)),
                Section(nil, [.tabs(selected: "b", [PageTab("a", "A", sections: [Section(nil, [.note("n")])]), PageTab("b", "B", badge: "2", sections: [Section(nil, [.note("m")])])])]),
                Section(nil, [.badges("Won", [Achievement("Ten", value: 3, goal: 10)])]),
                Section(nil, [.recent("Last", [RecentItem("Did", at: Date(timeIntervalSince1970: 0), tone: .good)])]),
                Section(nil, [.settings("Settings", keys: ["tone"], ai: true)]),
            ])
        }
        await ext.serve()
        """#
        let w = try await ExtensionAbilitiesTests.World { $0.carriedSettings = { _ in ["mood": "calm"] } }
        let folder = w.h.root.appendingPathComponent("src/kit", isDirectory: true)
        let manifest: JSONValue = ["id": "dev.sidefolk.kit-abilities", "name": "Kit Abilities", "version": "1.0.0", "run": ["command": "bin/server"], "settings_from": "old",
                                   "permissions": ["ai": ["purpose": "to write a word", "daily_cap": 2]],
                                   "settings": [["key": "tone", "type": "text", "title": "Tone", "default": "warm"], ["key": "loud", "type": "switch", "title": "Loud", "default": true]],
                                   "tools": ["says": ["risk": "low"], "quiet": ["risk": "low"], "note": ["risk": "low"], "ask": ["risk": "low"]],
                                   "pages": ["all": ["title": "All"]]]
        try ExtFixtures.makeExtension(at: folder, manifest: manifest)
        let dir = try ExtFixtures.tempDir("kit-abilities")
        defer { try? FileManager.default.removeItem(at: dir) }
        let main = dir.appendingPathComponent("main.swift")
        try Data(source.utf8).write(to: main)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let kit = ExtFixtures.repoRoot.appendingPathComponent("extensions/Kit")
        let kitFiles = try FileManager.default.contentsOfDirectory(at: kit, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }.map(\.path).sorted()
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        compiler.arguments = kitFiles + [main.path, "-o", folder.appendingPathComponent("bin/server").path]
        compiler.standardOutput = FileHandle.nullDevice
        compiler.standardError = FileHandle.nullDevice
        try compiler.run(); compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)
        guard compiler.terminationStatus == 0 else { return }

        try await w.h.host.install(from: folder, origin: .official)
        let id = "dev.sidefolk.kit-abilities"
        for _ in 0..<50 where await w.h.host.settings(extensionId: id).first?.value != "calm" { try await Task.sleep(for: .milliseconds(100)) }
        #expect(w.text(await w.h.call("ext.kit-abilities.says")) == "calm/true", "what it used to have, and its settings with each request")
        #expect(w.text(await w.h.call("ext.kit-abilities.quiet")) == "ok")
        for _ in 0..<50 where await w.h.host.settings(extensionId: id).last?.value != false { try await Task.sleep(for: .milliseconds(100)) }
        #expect(w.text(await w.h.call("ext.kit-abilities.says")) == "calm/false")
        #expect(w.text(await w.h.call("ext.kit-abilities.ask")) == "A line. by Scripted, offered by Scripted")
        #expect(w.text(await w.h.call("ext.kit-abilities.note")) == "ok")
        for _ in 0..<50 where await w.rows(ExtensionActivityTool.name).isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        #expect(await w.rows(ExtensionActivityTool.name).first?.summary == "Kit Abilities: Did a thing")

        let page = try await w.h.host.renderPage(extensionId: id, page: "all")
        #expect(page.sections.flatMap(\.blocks).map(\.kind) == ["hero", "stats", "grid", "tabs", "badges", "recent", "settings"])
        #expect(page.hero?.scene == .pack(path: "a.png", dark: "b.png"))
        #expect(page.sections[2].picture == .companion(.face))
        guard case .cards(let grid) = page.sections[2].blocks[0], case .tabs(let tabs) = page.sections[3].blocks[0] else { Issue.record("parts"); return }
        #expect(grid.size == .small && grid.items[0].picture == .person && grid.items[0].done && grid.items[0].menu?.items.count == 1 && grid.items[0].at != nil)
        #expect(tabs.selected == "b" && tabs.tabs[1].badge == "2")
    }
}
