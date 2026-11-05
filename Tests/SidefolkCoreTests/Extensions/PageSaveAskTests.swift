import Foundation
import Testing
@testable import SidefolkCore

/// A page's `save`: what it asks for can name a file, never a place.
@Suite struct PageSaveAskTests {
    private func ask(_ name: String, type: String = "sideflow", tool: String = "export_flows") -> PageSaveAsk? {
        guard case .save(let ask)? = PageAct.parse(["save": ["name": .string(name), "type": .string(type), "tool": .string(tool), "input": [:]]]) else { return nil }
        return ask
    }

    @Test func aNoteIsPlainAndShort() {
        guard case .save(let ask)? = PageAct.parse(["save": ["name": "a", "type": "txt", "tool": "t", "input": [:], "note": .string(String(repeating: "x", count: 300))]]) else { Issue.record("no ask"); return }
        #expect(ask.note?.count == 200)
    }

    @Test func aNameIsOnlyAName() {
        #expect(ask("Morning")?.name == "Morning.sideflow", "its ending goes on")
        #expect(ask("Morning.sideflow")?.name == "Morning.sideflow")
        #expect(ask("Morning.SIDEFLOW")?.name == "Morning.SIDEFLOW")
        #expect(ask("../../etc/passwd")?.name.contains("/") == false)
        #expect(ask("~/Library/LaunchAgents/x")?.name.contains("/") == false)
        #expect(ask("a:b")?.name == "a-b.sideflow")
        #expect(ask(".hidden")?.name == "hidden.sideflow", "not a hidden file")
        #expect(ask("re\u{202E}port")?.name == "report.sideflow", "nothing hidden in it")
        #expect(ask(String(repeating: "x", count: 500))?.name.count == 120)
        #expect(ask(String(repeating: "x", count: 500))?.name.hasSuffix(".sideflow") == true, "the ending survives")
    }

    @Test func whatIsntPlainlyASaveIsntOne() {
        #expect(ask("") == nil)
        #expect(ask("...") == nil)
        #expect(ask("   ") == nil)
        #expect(ask("x", type: "SIDEFLOW") == nil)
        #expect(ask("x", type: "a/b") == nil)
        #expect(ask("x", type: "") == nil)
        #expect(ask("x", tool: "../nope") == nil)
    }

    @Test func whatItHandsOverIsAPlainFileInItsOwnFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("exports"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("words".utf8).write(to: folder.appendingPathComponent("exports/a.sideflow"))
        #expect(ExtensionDataFile.readSaved("exports/a.sideflow", type: "sideflow", in: folder, limit: 100) == Data("words".utf8))
        #expect(ExtensionDataFile.readSaved("exports/a.sideflow", type: "sideflow", in: folder, limit: 2) == nil, "over the limit")
        #expect(ExtensionDataFile.readSaved("exports/a.sideflow", type: "txt", in: folder, limit: 100) == nil, "not what it said it would be")
        for name in ["../a.sideflow", "/etc/a.sideflow", "exports/../a.sideflow", ".a.sideflow", "exports/nope.sideflow", ""] {
            #expect(ExtensionDataFile.readSaved(name, type: "sideflow", in: folder, limit: 100) == nil, "\(name)")
        }
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.sideflow"), withDestinationURL: folder.appendingPathComponent("exports/a.sideflow"))
        #expect(ExtensionDataFile.readSaved("link.sideflow", type: "sideflow", in: folder, limit: 100) == nil, "a link isn't followed")
        try Data("x".utf8).write(to: folder.appendingPathComponent("b.sideflow"))
        try FileManager.default.linkItem(at: folder.appendingPathComponent("b.sideflow"), to: folder.appendingPathComponent("c.sideflow"))
        #expect(ExtensionDataFile.readSaved("b.sideflow", type: "sideflow", in: folder, limit: 100) == nil, "nor one with two names")
    }
}
