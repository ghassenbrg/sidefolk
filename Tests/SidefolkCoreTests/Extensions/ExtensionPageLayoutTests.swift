import Foundation
import Testing
@testable import SidefolkCore

/// What pages can say since D73 (a hero, a transport, choices as cards, pictures or rows, a side column, folding
/// sections, quiet and dimmed buttons), how Sidefolk checks it, and where each part goes on the page.
struct ExtensionPageLayoutTests {
    static func page(_ text: String) throws -> ExtensionPage {
        try ExtensionPage.parse(JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)))
    }

    @Test func aHeroIsCheckedAndLeadsThePage() throws {
        let page = try Self.page("""
            {"summary": {"title": "Ready", "control": {"type": "button", "label": "Start", "tool": "share", "style": "primary"}},
             "sections": [{"blocks": [{"type": "hero", "title": "Share your screen", "eyebrow": "Ready", "tone": "good", "code": "481 729",
                "image": "shots/1/a.jpg", "busy": true,
                "facts": [{"label": "fps", "value": "29"}, {"label": "a", "value": "1"}, {"label": "b", "value": "2"}, {"label": "c", "value": "3"},
                          {"label": "d", "value": "4"}],
                "actions": [{"type": "button", "label": "Start sharing", "tool": "share_screen", "style": "primary", "symbol": "play.fill"},
                            {"type": "button", "label": "Cancel", "tool": "stop"}, {"label": "Other's", "tool": "ext.x.y"},
                            {"label": "4", "tool": "a"}, {"label": "5", "tool": "b"}]}]}]}
            """)
        let hero = try #require(page.hero)
        #expect(hero.title == "Share your screen" && hero.eyebrow == "Ready" && hero.tone == .good && hero.busy)
        #expect(hero.code == "481 729" && hero.image == "shots/1/a.jpg")
        #expect(hero.facts.count == 4, "four numbers at most")
        #expect(hero.actions.map(\.tool) == ["share_screen", "stop"], "three at most, and another extension's tool is left out")
        // The hero says what the summary would: the summary's button isn't drawn, so it doesn't count against the hero's.
        #expect(hero.actions[0].style == .primary && page.summary?.control?.style == .primary)
        #expect(page.regions.map(\.region) == [.top])

        for bad in [#"{"type": "hero"}"#, #"{"type": "hero", "title": "x", "code": "<script>"}"#, #"{"type": "hero", "title": "x", "image": "../../etc/passwd"}"#] {
            let parsed = try Self.page(#"{"sections": [{"blocks": ["# + bad + "]}]}")
            if case .hero(let h)? = parsed.sections.first?.blocks.first { #expect(h.code == nil && h.image == nil, "\(bad)") }
        }
    }

    @Test func aPageHasOnePrimaryAction() throws {
        let page = try Self.page("""
            {"summary": {"title": "x", "control": {"type": "button", "label": "Go", "tool": "go", "style": "primary"}},
             "sections": [{"blocks": [{"type": "button", "label": "Also", "tool": "also", "style": "primary"},
                                      {"type": "button", "label": "Quiet", "tool": "q", "style": "plain", "disabled": true, "detail": "Not yet"},
                                      {"type": "button", "label": "Odd", "tool": "o", "style": "shiny"}]}]}
            """)
        #expect(page.summary?.control?.style == .primary, "the banner's button comes first")
        let controls = page.sections[0].blocks.compactMap { if case .control(let c) = $0 { c } else { nil } }
        #expect(controls.map(\.style) == [.secondary, .plain, .secondary], "a second primary is drawn secondary; an unknown style is secondary")
        #expect(controls[1].disabled && controls[1].detail == "Not yet")
    }

    @Test func choicesAreDrawnAsWhatTheyChooseBetween() throws {
        let rows = (0..<30).map { #"{"value": "tv\#($0)", "label": "TV \#($0)", "detail": "Paired", "symbol": "tv", "badge": {"text": "Paired", "tone": "good"}, "action": {"label": "Forget", "tool": "forget_tv", "input": {"tv": "\#($0)"}, "style": "plain"}}"# }
        let page = try Self.page("""
            {"sections": [{"place": "side", "title": "TVs", "blocks": [
                {"type": "choice", "style": "rows", "label": "Share to", "key": "tv", "tool": "choose_tv", "selected": "tv1", "disabled": true,
                 "options": [\(rows.joined(separator: ","))]}]},
              {"title": "What", "blocks": [
                {"type": "choice", "style": "tiles", "label": "Screen", "tool": "set_option", "selected": "1",
                 "options": [{"value": "1", "label": "Built-in", "image": "shots/1.jpg"}]},
                {"type": "choice", "style": "cards", "label": "Quality", "tool": "set_option", "selected": "z",
                 "options": [{"value": "a", "label": "A", "detail": "720p", "image": "shots/no.jpg"}, {"value": "b", "label": "B"}]},
                {"type": "choice", "label": "One option", "tool": "x", "options": [{"value": "a", "label": "A"}]},
                {"type": "choice", "style": "rows", "label": "Bad key", "key": "on", "tool": "x", "options": [{"value": "a", "label": "A"}]}]}]}
            """)
        let choices = page.sections.flatMap(\.blocks).compactMap { if case .choice(let c) = $0 { c } else { nil } }
        #expect(choices.map(\.label) == ["Share to", "Screen", "Quality"], "a plain choice needs two options; `on` can't be the key")
        let tvs = choices[0]
        #expect(tvs.style == .rows && tvs.options.count == 24 && tvs.disabled && tvs.selected == "tv1")
        #expect(tvs.options[0].badge == ExtensionPage.Badge(text: "Paired", tone: .good) && tvs.options[0].action?.tool == "forget_tv")
        #expect(tvs.input(picking: "tv3") == ["tv": "tv3"], "the picked value goes under the choice's key")
        #expect(choices[1].style == .tiles && choices[1].options.count == 1 && choices[1].options[0].image == "shots/1.jpg")
        #expect(choices[2].style == .cards && choices[2].options[0].image == nil && choices[2].options[0].detail == "720p", "cards have no pictures")
        #expect(choices[2].selected == "", "a selection that isn't an option picks nothing")
    }

    @Test func aTransportNeedsButtonsWithSymbols() throws {
        let page = try Self.page("""
            {"sections": [{"blocks": [
                {"type": "transport", "title": "Film.mp4", "position": 754, "duration": 6310, "state": "playing", "buttons": [
                    {"label": "Back", "tool": "seek", "input": {"seconds": -30}, "symbol": "gobackward.30"},
                    {"label": "Pause", "tool": "pause", "style": "primary", "symbol": "pause.fill"},
                    {"label": "No symbol", "tool": "x"}]},
                {"type": "transport", "position": -4, "duration": 0, "buttons": [{"label": "Words only", "tool": "x"}]},
                {"type": "transport", "position": -4, "duration": 0, "state": "flying", "buttons": [{"label": "Play", "tool": "play", "symbol": "play.fill"}]}]}]}
            """)
        let transports = page.sections.flatMap(\.blocks).compactMap { if case .transport(let t) = $0 { t } else { nil } }
        #expect(transports.count == 2, "a transport without a symbol button is left out")
        #expect(transports[0].buttons.map(\.tool) == ["seek", "pause"] && transports[0].state == .playing && transports[0].duration == 6310)
        #expect(transports[1].position == nil && transports[1].duration == nil && transports[1].state == .stopped)
    }

    @Test func sectionsGoAcrossBesideOrFolded() throws {
        let page = try Self.page("""
            {"sections": [
              {"blocks": [{"type": "hero", "title": "Ready"}]},
              {"title": "TVs", "place": "side", "blocks": [{"type": "note", "text": "a"}]},
              {"title": "What", "blocks": [{"type": "choice", "style": "tiles", "label": "S", "tool": "t", "options": [{"value": "1", "label": "One"}]}]},
              {"title": "Quality", "blocks": [{"type": "switch", "label": "Sound", "tool": "t"}]},
              {"title": "More", "collapsed": true, "blocks": [{"type": "switch", "label": "Detail", "tool": "t"}]},
              {"collapsed": true, "place": "nowhere", "blocks": [{"type": "switch", "label": "Untitled", "tool": "t"}]}]}
            """)
        #expect(page.hasSide && page.isRich)
        #expect(page.sections[4].collapsed == true && page.sections[5].collapsed == nil, "only a titled section folds")
        #expect(page.sections[5].place == .main, "an unknown place is the main column")
        #expect(page.regions.map(\.region) == [.top, .side, .main, .main])
        #expect(page.regions[3].sections.map(\.title) == ["Quality", "More", nil], "small sections side by side")
        #expect(page.sections[2].isWide, "pictures run across")

        // Without a side column every section is in the main one, and a hero only leads from the first section.
        let plain = try Self.page(#"{"sections": [{"blocks": [{"type": "note", "text": "a"}]}, {"blocks": [{"type": "hero", "title": "Late"}]}]}"#)
        #expect(plain.hero == nil && plain.regions.map(\.region) == [.main, .main] && !plain.hasSide)
    }
}
