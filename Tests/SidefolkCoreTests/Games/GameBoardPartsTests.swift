import Foundation
import Testing
@testable import SidefolkCore

/// The later games' parts (D75 phases 2 and 3): each read, checked and capped; moves only for a part on the board; and
/// the founder's rule for every game's shape: nothing decided shows before its build-up ends.
struct GameBoardPartsTests {
    static func board(_ text: String) throws -> GameBoard { try GameBoardTests.board(text) }

    @Test func partsAreReadCheckedAndCapped() throws {
        let swaps = (0..<60).map { _ in "[0, 2]" }.joined(separator: ",")
        let b = try Self.board("""
            {"parts": [
              {"type": "pads", "items": [{"shape": "circle", "color": "blue", "label": "Wave", "move": "accent:wave"},
                                         {"shape": "star", "color": "yellow", "label": "Spin", "move": "fly"},
                                         {"shape": "hexagon", "color": "blue", "label": "Odd"}], "play": [0, 1, 0], "step_ms": 50},
              {"type": "cups", "count": 4, "hide": 1, "swaps": [\(swaps), [1, 1], [0, 9]], "swap_ms": 300},
              {"type": "reflex", "after_ms": 2500, "window_ms": 99999, "wait": "Steady…", "go": "Boop!", "early": "Too soon!"},
              {"type": "meter", "value": 3, "label": "Warm"},
              {"type": "number", "min": 1, "max": 100, "history": [{"value": 50, "mark": "lower"}, {"value": 20, "mark": "sideways"}]},
              {"type": "letters", "length": 5, "tries": 12, "rows": [[{"text": "c", "mark": "right"}, {"text": "rane!!", "mark": "elsewhere"}]], "flip": 0},
              {"type": "keys", "mode": "spell", "length": 5, "script": "hangul", "pages": [{"label": "", "rows": [[{"key": "ㅂ"}, {"key": "ab"}, {"key": "1"}]]}]},
              {"type": "entry", "name": "animal", "kind": "text", "max": 999},
              {"type": "sticks", "total": 21, "left": 9, "take": 3, "groups": [[1, 2, 3, 4], [99]], "taken": 50, "taken_by": "companion"},
              {"type": "lives", "total": 7, "left": 12, "symbol": "balloon"}],
             "after_ms": 900}
            """)
        let pads = try #require(b.pads)
        #expect(pads.pads.count == 2 && pads.pads[0].move == .accentWave && pads.pads[1].move == nil, "an unknown shape or move is dropped")
        #expect(pads.play == [0, 1, 0] && pads.stepSeconds == 0.25, "at least a quarter second a step")
        let cups = try #require(b.cups)
        #expect(cups.swaps.count == GameBoard.Cups.maxSwaps && cups.hide == 1 && !cups.revealed, "swaps capped, a bad swap dropped")
        #expect(b.reflex?.armed == true && b.reflex?.window == 5, "a window of at most five seconds")
        #expect(b.parts.contains { if case .meter(let m) = $0 { m.value == 1 } else { false } }, "a meter is 0–1")
        #expect(b.numberField?.history.map(\.value) == [50])
        #expect(b.letters?.tries == 8 && (b.letters?.rows[0][1].text.count ?? 9) <= 4 && b.letters?.flip == 0, "eight rows at most, four letters a tile")
        #expect(b.keys?.all.map(\.key) == ["ㅂ"] && b.keys?.script == .hangul, "a key is one letter")
        #expect(b.entry?.max == 120)
        #expect(b.sticks?.groups == [[1, 2, 3, 4], []] && b.sticks?.taken == 12 && b.sticks?.takenByCompanion == true)
        #expect(b.lives?.left == 7)
        #expect(b.after == 0.9)
        #expect(try Self.board(#"{"parts": [], "after_ms": 60000}"#).after == nil, "a wait longer than six seconds is no wait")
        // A tile's own key cap, for Y, N and ?.
        let yn = try Self.board(#"{"parts": [{"type": "answers", "items": [{"label": "Yes", "key": "y"}, {"label": "Not sure", "key": "?"}, {"label": "x", "key": "ab"}]}]}"#)
        #expect(yn.answers?.tiles.map(\.key) == ["Y", "?", nil])
    }

    @Test func movesGoOnlyToThePartsOnTheBoard() throws {
        let typing = try Self.board(#"{"parts": [{"type": "keys", "mode": "letter", "rows": [[{"key": "a"}]]}, {"type": "sticks", "total": 21, "left": 2}]}"#)
        #expect(GameMove.letter("e").offered(by: typing), "the game decides which letters are its own")
        #expect(!GameMove.word("crane").offered(by: typing) && GameMove.number(2).offered(by: typing) && !GameMove.number(3).offered(by: typing))
        let spell = try Self.board(#"{"parts": [{"type": "keys", "mode": "spell", "length": 5, "rows": [[{"key": "a"}]]}]}"#)
        #expect(GameMove.word("crane").offered(by: spell) && !GameMove.letter("a").offered(by: spell))
        let field = try Self.board(#"{"parts": [{"type": "number", "min": 1, "max": 100}]}"#)
        #expect(GameMove.number(42).offered(by: field) && !GameMove.number(0).offered(by: field) && !GameMove.number(101).offered(by: field))
        let cups = try Self.board(#"{"parts": [{"type": "cups", "count": 3, "swaps": [[0, 1]]}]}"#)
        #expect(GameMove.cell(row: 0, column: 2).offered(by: cups) && !GameMove.cell(row: 0, column: 3).offered(by: cups))
        let lifted = try Self.board(#"{"parts": [{"type": "cups", "count": 3, "picked": 1, "gem": null}]}"#)
        #expect(lifted.cups?.revealed == true && lifted.cups?.gem == nil && !GameMove.cell(row: 0, column: 0).offered(by: lifted), "lifted: no more picks")
        let reflex = try Self.board(#"{"parts": [{"type": "reflex", "after_ms": 2000, "wait": "w", "go": "g", "early": "e"}]}"#)
        #expect(GameMove.press(milliseconds: 240).offered(by: reflex) && GameMove.early.offered(by: reflex) && GameMove.timeout.offered(by: reflex))
        let played = try Self.board(#"{"parts": [{"type": "reflex", "wait": "w", "go": "g", "early": "e", "shows": "243 ms"}]}"#)
        #expect(!GameMove.press(milliseconds: 1).offered(by: played))
        let pads = try Self.board(#"{"parts": [{"type": "pads", "items": [{"shape": "circle", "color": "blue", "label": "a"}, {"shape": "star", "color": "red", "label": "b"}]}]}"#)
        #expect(GameMove.pad(1).offered(by: pads) && !GameMove.pad(2).offered(by: pads))
        let entry = try Self.board(#"{"parts": [{"type": "entry", "name": "animal", "kind": "text", "max": 10}]}"#)
        #expect(GameMove.text(name: "animal", value: "axolotl").offered(by: entry) && !GameMove.text(name: "question", value: "x").offered(by: entry))
        #expect(!GameMove.text(name: "animal", value: "a very long animal").offered(by: entry))
        let waiting = try Self.board(#"{"parts": [], "after_ms": 900}"#)
        #expect(GameMove.next.offered(by: waiting) && !GameMove.next.offered(by: entry))
        // Parsed as Sidefolk sends them: a text cleaned and on one line, a word of letters (kana, jamo, characters).
        #expect(GameMove.parse(try ExtensionPageTests.json(#"{"text": {"name": "question", "value": "Does it‮ swim?"}}"#)) == .text(name: "question", value: "Does it swim?"))
        #expect(GameMove.parse(try ExtensionPageTests.json(#"{"word": "一心一意"}"#)) == .word("一心一意"))
        #expect(GameMove.parse(try ExtensionPageTests.json(#"{"next": true}"#)) == .next && GameMove.next.json == ["next": true])
    }

    /// Every later game's moment of truth waits for its build-up: a stamped winning line, the cups lifted, a reflex timed,
    /// a guess judged, a point scored, a word's row flipping; the build-up shows none of it (`showsVerdict`).
    @Test func noGameShowsItsVerdictBeforeItsBuildUp() throws {
        func check(_ before: String, _ after: String, seconds: TimeInterval = GameSuspense.beatSeconds, _ comment: Comment) throws {
            let (a, b) = (try Self.board(before), try Self.board(after))
            let (build, wait) = try #require(GameSuspense.buildUp(from: a, to: b, picked: nil), comment)
            #expect(!GameSuspense.showsVerdict(build), comment)
            #expect(abs(wait - seconds) < 0.001, comment)
            #expect(build.buttons.isEmpty && build.cue == nil && !build.over, comment)
        }
        let cells = { (win: Bool) in (0..<9).map { $0 < 3 ? #"{"mark": "x"\#(win ? #", "state": "win""# : "")}"# : #"{"mark": "empty"}"# }.joined(separator: ",") }
        try check(#"{"parts": [{"type": "score", "you": 0, "companion": 0}, {"type": "board", "rows": 3, "columns": 3, "cells": [\#(cells(false))]}]}"#,
                  #"{"parts": [{"type": "score", "you": 1, "companion": 0}, {"type": "board", "rows": 3, "columns": 3, "cells": [\#(cells(true))], "locked": true}, {"type": "result", "figure": "1 – 0", "tone": "good"}], "companion": {"move": "sulk"}, "over": true}"#,
                  "tic-tac-toe: the line drawn after the X lands")
        try check(#"{"parts": [{"type": "score", "you": 1, "companion": 1}, {"type": "cups", "count": 3, "hide": 0, "swaps": [[0, 1]]}]}"#,
                  #"{"parts": [{"type": "score", "you": 2, "companion": 1}, {"type": "cups", "count": 3, "picked": 1, "gem": 1}, {"type": "button", "label": "Next", "move": "next", "style": "primary"}], "companion": {"move": "wince"}}"#,
                  "which cup: lifted after the pick wobbles")
        try check(#"{"parts": [{"type": "score", "you": 0, "companion": 0}, {"type": "reflex", "after_ms": 2000, "wait": "w", "go": "g", "early": "e"}]}"#,
                  #"{"parts": [{"type": "score", "you": 1, "companion": 0}, {"type": "reflex", "wait": "w", "go": "g", "early": "e", "shows": "180 ms"}], "after_ms": 1800, "companion": {"move": "wince"}}"#,
                  "quick paws: the times after a beat")
        try check(#"{"parts": [{"type": "number", "min": 1, "max": 100}]}"#,
                  #"{"parts": [{"type": "meter", "value": 0.7}, {"type": "number", "min": 1, "max": 100, "history": [{"value": 50, "mark": "lower"}]}], "companion": {"effect": "frost"}}"#,
                  "higher or lower: lower, after a beat")
        try check(#"{"parts": [{"type": "letters", "length": 5, "tries": 6, "rows": []}, {"type": "keys", "mode": "spell", "rows": [[{"key": "c"}]]}]}"#,
                  #"{"parts": [{"type": "letters", "length": 5, "tries": 6, "flip": 0, "rows": [[{"text": "c", "mark": "right"}, {"text": "r", "mark": "absent"}, {"text": "a", "mark": "elsewhere"}, {"text": "n", "mark": "absent"}, {"text": "e", "mark": "absent"}]]}, {"type": "keys", "mode": "spell", "rows": [[{"key": "c", "mark": "right"}]]}], "companion": {"move": "nod"}}"#,
                  seconds: 0.35 + 5 * 0.22, "daily word: the row flips, then the keys and the reaction")
        try check(#"{"parts": [{"type": "score", "you": 2, "companion": 3}, {"type": "board", "rows": 1, "columns": 2, "cells": [{"mark": "card_back"}, {"mark": "card_back"}]}]}"#,
                  #"{"parts": [{"type": "score", "you": 3, "companion": 3}, {"type": "board", "rows": 1, "columns": 2, "cells": [{"mark": "symbol", "value": "moon.fill", "animate": "flip"}, {"mark": "symbol", "value": "moon.fill"}]}], "companion": {"move": "wince"}}"#,
                  "memory pairs: the card turns, then the pair is counted")
        // The keyboard's marks would give a Daily Word row away: the build-up keeps the old ones.
        let before = try Self.board(#"{"parts": [{"type": "letters", "length": 1, "rows": []}, {"type": "keys", "mode": "spell", "rows": [[{"key": "c"}]]}]}"#)
        let after = try Self.board(#"{"parts": [{"type": "letters", "length": 1, "flip": 0, "rows": [[{"text": "c", "mark": "right"}]]}, {"type": "keys", "mode": "spell", "rows": [[{"key": "c", "mark": "right"}]]}]}"#)
        #expect(GameSuspense.buildUp(from: before, to: after, picked: nil)?.board.keys?.all.first?.mark == GameBoard.Keys.Mark.none)
        // A board that decides nothing (a turn, a letter typed) shows at once.
        #expect(GameSuspense.buildUp(from: before, to: before, picked: nil) == nil)
    }
}
