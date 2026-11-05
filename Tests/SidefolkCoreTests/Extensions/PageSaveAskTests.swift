import Foundation
import Testing
@testable import SidefolkCore

/// A page's `save`: what it asks for can name a file, never a place.
@Suite struct PageSaveAskTests {
    private func ask(_ name: String, type: String = "sideflow", tool: String = "export_flows") -> PageSaveAsk? {
        guard case .save(let ask)? = PageAct.parse(["save": ["name": .string(name), "type": .string(type), "tool": .string(tool), "input": [:]]]) else { return nil }
        return ask
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
}
