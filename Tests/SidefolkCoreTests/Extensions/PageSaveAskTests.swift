import Foundation
import Testing
@testable import SidefolkCore

/// A page's `save`: what it asks for can name a file, never a place.
@Suite struct PageSaveAskTests {
    private func ask(_ name: String, type: String = "data", tool: String = "export_report") -> PageSaveAsk? {
        guard case .save(let ask)? = PageAct.parse(["save": ["name": .string(name), "type": .string(type), "tool": .string(tool), "input": [:]]]) else { return nil }
        return ask
    }

    @Test func aNoteIsPlainAndShort() {
        guard case .save(let ask)? = PageAct.parse(["save": ["name": "a", "type": "txt", "tool": "t", "input": [:], "note": .string(String(repeating: "x", count: 300))]]) else { Issue.record("no ask"); return }
        #expect(ask.note?.count == 140)
        guard case .save(let lines)? = PageAct.parse(["save": ["name": "a", "type": "txt", "tool": "t", "input": [:], "note": "Save it\nin ~/Library"]]) else { Issue.record("no ask"); return }
        #expect(lines.note == "Save it in ~/Library", "one line")
        #expect(PageSaveAsk.panelMessage("Save it here", from: "Reports").hasPrefix("Reports says: "), "whose words they are comes first")
    }

    @Test func thePlacesSidefolkNeverTouchesAreRefusedWhateverWasPicked() throws {
        let home = NSHomeDirectory()
        for path in [home + "/Library/LaunchAgents/com.helper.agent.json", home + "/.claude/settings.json", home + "/.ssh/config.txt",
                     SidefolkPaths.standard().home.appendingPathComponent("notes.json").path, "/Library/LaunchDaemons/x.json"] {
            #expect(PageSaveAsk.refusal(at: URL(fileURLWithPath: path)) != nil, "\(path)")
        }
        // A link on the way is followed to where it leads.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("in"), withDestinationURL: URL(fileURLWithPath: home + "/Library"))
        #expect(PageSaveAsk.refusal(at: folder.appendingPathComponent("in/LaunchAgents/x.json")) != nil, "a link into ~/Library")
        #expect(PageSaveAsk.refusal(at: folder.appendingPathComponent("report.json")) == nil, "an ordinary place")
        #expect(PageSaveAsk.refusal(at: folder.appendingPathComponent("agent.plist")) != nil, "a kind that acts where it lands, renamed in the panel")
    }

    @Test func aNameIsOnlyAName() {
        #expect(ask("Morning")?.name == "Morning.data", "its ending goes on")
        #expect(ask("Morning.data")?.name == "Morning.data")
        #expect(ask("Morning.DATA")?.name == "Morning.data")
        #expect(ask("../../etc/passwd")?.name.contains("/") == false)
        #expect(ask("~/Library/LaunchAgents/x")?.name.contains("/") == false)
        #expect(ask("a:b")?.name == "a-b.data")
        #expect(ask(".hidden")?.name == "hidden.data", "not a hidden file")
        #expect(ask("re\u{202E}port")?.name == "report.data", "nothing hidden in it")
        #expect(ask(String(repeating: "x", count: 500))?.name.count == 120)
        #expect(ask(String(repeating: "x", count: 500))?.name.hasSuffix(".data") == true, "the ending survives")
    }

    @Test func whatIsntPlainlyASaveIsntOne() {
        #expect(ask("") == nil)
        #expect(ask("...") == nil)
        #expect(ask("   ") == nil)
        #expect(ask("x", type: "DATA") == nil)
        #expect(ask("x", type: "a/b") == nil)
        #expect(ask("x", type: "") == nil)
        #expect(ask("x", tool: "../nope") == nil)
    }

    @Test func whatItHandsOverIsAPlainFileInItsOwnFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("exports"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("words".utf8).write(to: folder.appendingPathComponent("exports/a.data"))
        #expect(ExtensionDataFile.readSaved("exports/a.data", type: "data", in: folder, limit: 100) == Data("words".utf8))
        #expect(ExtensionDataFile.readSaved("exports/a.data", type: "data", in: folder, limit: 2) == nil, "over the limit")
        #expect(ExtensionDataFile.readSaved("exports/a.data", type: "txt", in: folder, limit: 100) == nil, "not what it said it would be")
        for name in ["../a.data", "/etc/a.data", "exports/../a.data", ".a.data", "exports/nope.data", ""] {
            #expect(ExtensionDataFile.readSaved(name, type: "data", in: folder, limit: 100) == nil, "\(name)")
        }
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.data"), withDestinationURL: folder.appendingPathComponent("exports/a.data"))
        #expect(ExtensionDataFile.readSaved("link.data", type: "data", in: folder, limit: 100) == nil, "a link isn't followed")
        try Data("x".utf8).write(to: folder.appendingPathComponent("b.data"))
        try FileManager.default.linkItem(at: folder.appendingPathComponent("b.data"), to: folder.appendingPathComponent("c.data"))
        #expect(ExtensionDataFile.readSaved("b.data", type: "data", in: folder, limit: 100) == nil, "nor one with two names")
    }

    @Test func itCantBeAKindOfFileThatRuns() {
        for type in ["app", "command", "terminal", "pkg", "scpt", "sh", "py", "dmg", "webloc", "plist", "mobileconfig", "workflow", "rb", "pl"] { #expect(ask("Report", type: type) == nil, "\(type)") }
        for type in ["csv", "json", "txt", "data"] { #expect(ask("Report", type: type)?.name == "Report.\(type)", "\(type)") }
    }

    @Test func aNameCantHideWhatItIs() {
        #expect(ask("Invoice.pdf" + String(repeating: " ", count: 100) + "x")?.name == "Invoice.pdf x.data")
        #expect(ask("a\nb\u{202E}c\u{00AD}d\u{2028}e")?.name == "abcde.data" || ask("a\nb\u{202E}c\u{00AD}d\u{2028}e")?.name == "a bcde.data")
        #expect(ask(String(repeating: "x", count: 300) + ".y")?.name.hasSuffix("xxx.data") == true)
        #expect(ask("...")?.name == nil)
        #expect(ask(String(repeating: ".", count: 200) + "z")?.name == "z.data")
    }

    @Test func aPipeDoesntHoldItUp() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(mkfifo(folder.appendingPathComponent("p.data").path, 0o600) == 0)
        #expect(ExtensionDataFile.readSaved("p.data", type: "data", in: folder, limit: 100) == nil)
    }

    @Test func aSavedFileIsMarkedAsDownloaded() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        PageSaveAsk.markAsDownloaded(file)
        #expect(getxattr(file.path, "com.apple.quarantine", nil, 0, 0, 0) > 0)
    }

    @Test func aFieldHearsWhenWhatsSavedChangesUnlessItFollowsTheTyping() throws {
        func field(_ value: String, live: Bool) throws -> ExtensionPage.Field {
            ExtensionPage.Field(label: "A", detail: nil, placeholder: nil, button: "", tool: "t", input: .object([:]), key: "text", go: nil, live: live, value: value)
        }
        #expect(try field("a", live: false) != field("b", live: false))
        #expect(try field("a", live: true) == field("b", live: true))
    }
}
