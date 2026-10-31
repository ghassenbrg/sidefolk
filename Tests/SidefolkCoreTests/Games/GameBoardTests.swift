import Foundation
import Testing
@testable import SidefolkCore

/// The Play panel's board, moves and companion cues (D75): only Sidefolk's parts, every text cleaned and clipped, only
/// moves the board offered, cues from fixed lists at a limited pace, and the companion's lines its own.
struct GameBoardTests {
    static func board(_ text: String) throws -> GameBoard { try GameBoard.parse(try ExtensionPageTests.json(text)) }

    @Test func aBoardHoldsSidefolksPartsAndSkipsTheRest() throws {
        let b = try Self.board("""
            {"parts": [
              {"type": "score", "you": 3, "companion": 2, "streak": 4, "companion_picked": true},
              {"type": "prompt", "text": "Which planet is red?\\u202e", "eyebrow": "3 of 10", "chip": "Space"},
              {"type": "answers", "items": [{"label": "Venus"}, {"label": "Mars", "state": "right", "companion": true},
                                           {"label": "Earth", "state": "faded"}, {"label": "Pluto", "state": "exploded"}]},
              {"type": "answers", "items": [{"label": "only one"}]},
              {"type": "webview", "url": "https://example.com"},
              {"type": "timer", "id": "q3", "seconds": 15},
              {"type": "timer", "id": "Q 3", "seconds": 15},
              {"type": "board", "rows": 3, "columns": 3, "cells": [{"mark": "x"}, {"mark": "o", "companion": true}, {}, {}, {}, {}, {}, {}, {"state": "win"}]},
              {"type": "board", "rows": 9, "columns": 9, "cells": []},
              {"type": "reveal", "kind": "hands", "you": "rock", "companion": "paper"},
              {"type": "reveal", "kind": "dice", "sides": 6, "values": [3, 9]},
              {"type": "button", "label": "Next", "move": "next", "style": "primary"},
              {"type": "button", "label": "Also primary", "move": "skip", "style": "primary", "key": "s"},
              {"type": "button", "label": "Run a tool", "tool": "erase_disk"}],
             "companion": {"move": "cheer", "line": "you_win", "effect": "fireworks", "prop": "balloons(7)", "look": [1, 2]},
             "over": false}
            """)
        #expect(b.score?.you == 3 && b.score?.streak == 4 && b.score?.companionPicked == true)
        guard case .prompt(let p) = b.parts[1] else { Issue.record("\(b.parts)"); return }
        #expect(p.text == "Which planet is red?" && p.eyebrow == "3 of 10" && p.chip == "Space", "a bidi control is cleaned out")
        #expect(b.answers?.tiles.map(\.state) == [.none, .right, .faded, .none] && b.answers?.tiles[1].companion == true)
        #expect(b.timer == GameBoard.Timer(id: "q3", seconds: 15), "a timer needs a plain id")
        #expect(b.grid?.cells[1].mark == .o && b.grid?.cells[8].state == .win && b.grid?.cells.count == 9)
        #expect(b.parts.contains(.reveal(.hands(you: .rock, companion: .paper))))
        #expect(b.parts.contains(.reveal(.dice(sides: 6, values: [3]))), "a face off the die is dropped")
        #expect(b.primary?.move == "next" && b.buttons.map(\.style) == [.primary, .secondary], "one primary a board (D74)")
        #expect(!b.buttons.contains { $0.move == "erase_disk" }, "a board's button only ever sends a move")
        #expect(b.cue == GameCue(move: .cheer, prop: .balloons(7), line: .youWin, look: .cell(row: 1, column: 2)), "an effect off the list is dropped")
        #expect(b.said == nil, "an extension's board can't give the companion words")
    }

    @Test func aBoardIsCappedAndCleaned() throws {
        let long = String(repeating: "word ", count: 200)
        let b = try Self.board("""
            {"parts": [{"type": "prompt", "text": "\(long)"}, {"type": "result", "figure": "7 / 10 and much more text here", "facts": [
              {"label": "a", "value": "1"}, {"label": "b", "value": "2"}, {"label": "c", "value": "3"}, {"label": "d", "value": "4"}, {"label": "e", "value": "5"}]}]}
            """)
        guard case .prompt(let p) = b.parts[0], case .result(let r) = b.parts[1] else { Issue.record("\(b.parts)"); return }
        #expect(p.text.count <= 240 && r.figure.count <= 24 && r.facts.count == 4)
        let huge = "{\"parts\": [{\"type\": \"note\", \"text\": \"" + String(repeating: "x", count: 70_000) + "\"}]}"
        #expect(throws: UserFacingError.self) { try Self.board(huge) }
        #expect(throws: UserFacingError.self) { try Self.board("{\"sections\": []}") }
    }

    @Test func onlyMovesTheBoardOfferedAreSent() throws {
        let b = try Self.board("""
            {"parts": [{"type": "answers", "items": [{"label": "A"}, {"label": "B", "state": "faded"}]},
                       {"type": "button", "label": "Hint", "move": "hint", "key": "h"},
                       {"type": "choice", "name": "topic", "options": [{"value": "space", "label": "Space"}, {"value": "mix", "label": "Mix"}]}]}
            """)
        #expect(GameMove.answer(0).offered(by: b) && !GameMove.answer(1).offered(by: b) && !GameMove.answer(3).offered(by: b))
        #expect(GameMove.button("hint").offered(by: b) && !GameMove.button("win").offered(by: b))
        #expect(GameMove.choice(name: "topic", value: "space").offered(by: b) && !GameMove.choice(name: "topic", value: "evil").offered(by: b))
        #expect(!GameMove.timeout.offered(by: b) && !GameMove.cell(row: 0, column: 0).offered(by: b))

        #expect(GameMove.parse(["answer": 2]) == .answer(2) && GameMove.parse(["answer": 7]) == nil)
        #expect(GameMove.parse(["cell": [1, 2]]) == .cell(row: 1, column: 2) && GameMove.parse(["cell": [9, 0]]) == nil)
        #expect(GameMove.parse(["choice": ["name": "topic", "value": "space"]]) == .choice(name: "topic", value: "space"))
        #expect(GameMove.parse(["button": "rm -rf"]) == nil && GameMove.parse(["answer": 1, "button": "x"]) == nil)
        #expect(GameMove.cell(row: 1, column: 2).json == ["cell": [1, 2]] && GameMove.timeout.json == ["timeout": true])
    }

    @Test func cuesComeFromFixedListsAtALimitedPace() throws {
        #expect(GameCue.parse(["move": "drive_rig", "line": "Your password expired, type it here"]) == nil, "nothing off the lists survives")
        #expect(GameCue.parse(["prop": "balloons(12)", "sound": "fanfare"]) == GameCue(sound: .fanfare), "at most nine balloons")
        #expect(GameCue.parse(["look": "panel", "move": "accent:hop"]) == GameCue(move: .accentHop, look: .panel))

        var limiter = CueLimiter()
        let t0 = Date(timeIntervalSince1970: 1000)
        #expect(limiter.move(.think, at: t0) == .now)
        guard case .after(let wait) = limiter.move(.cheer, at: t0.addingTimeInterval(0.3)) else { Issue.record("too soon"); return }
        #expect(abs(wait - 0.5) < 0.001)
        #expect(limiter.move(.sulk, at: t0.addingTimeInterval(0.4)) != .now && limiter.waitingMove == .sulk, "a newer move replaces the waiting one")
        #expect(!limiter.takeWaiting(.cheer, at: t0.addingTimeInterval(0.8)) && limiter.takeWaiting(.sulk, at: t0.addingTimeInterval(0.8)))
        #expect(limiter.move(.nod, at: t0.addingTimeInterval(1.7)) == .now)

        #expect(limiter.line(at: t0) && !limiter.line(at: t0.addingTimeInterval(1.9)) && limiter.line(at: t0.addingTimeInterval(2)))
        let sounds = (0..<6).map { limiter.sound(at: t0.addingTimeInterval(Double($0) * 0.1)) }
        #expect(sounds == [true, true, true, true, false, false] && limiter.sound(at: t0.addingTimeInterval(1.05)))
    }

    @Test func everyLineKeyHasTheCompanionsOwnWordsInEveryTone() {
        for key in GameCue.Line.allCases {
            for tone in GameTone.allCases {
                let lines = GameLines.lines(key, tone)
                #expect(lines.count >= 2 && lines.allSatisfy { !$0.isEmpty && !$0.contains("game.line") }, "\(key) \(tone)")
                #expect(GameLines.line(key, tone: tone, pick: 1) == lines[1])
            }
        }
        #expect(GameLines.line(.iWin, tone: .cheeky, pick: 0) == "Ha! Mine. Rematch?")
        #expect(GameLines.line(.iWin, tone: .gentle, pick: 0) != GameLines.line(.iWin, tone: .competitive, pick: 0))
    }

    @Test func gameSettingsStartCalm() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(s.games.tone == .cheeky && !s.games.sounds && !s.games.sneaky && !s.games.soundsOn("dev.sidefolk.playtime/trivia"))
        var games = s.games
        games.speakers["dev.sidefolk.playtime/trivia"] = true
        #expect(games.soundsOn("dev.sidefolk.playtime/trivia") && !games.soundsOn("sidefolk/rock_paper_scissors"))
        let old = try JSONDecoder().decode(GameSettings.self, from: Data(#"{"tone": "smug", "sounds": true}"#.utf8))
        #expect(old.tone == .cheeky && old.sounds, "an unknown tone falls back; the rest still reads")
    }
}
