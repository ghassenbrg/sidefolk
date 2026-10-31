import Foundation
import Testing
@testable import SidefolkCore

/// The logic puzzles' grid (D79, the puzzles): read, checked and capped; its moves (a tap, a dragged rectangle, a number
/// in a cell) only where the board offers them; and the solved card only after the last mark has settled.
struct GamePuzzleTests {
    static func board(_ text: String) throws -> GameBoard { try GameBoardTests.board(text) }

    static func cells(_ n: Int, _ extra: String = "{}") -> String {
        ([extra] + Array(repeating: "{}", count: n - 1)).joined(separator: ",")
    }

    @Test func aPuzzleIsReadCheckedAndCapped() throws {
        let edges = (0..<300).map { _ in #"{"cell": 0, "clue": "same"}"# }.joined(separator: ",")
        let b = try Self.board("""
            {"parts": [{"type": "puzzle", "rows": 3, "columns": 4, "input": "drag", "box": [2, 3],
              "cells": [{"symbol": "heart", "text": "123", "notes": [1, 1, 12, 3], "region": 40, "state": "conflict", "given": true, "fresh": true},
                        {"symbol": "crown", "text": "7"}, \(Self.cells(10))],
              "edges": [\(edges), {"cell": 3, "clue": "same"}, {"cell": 8, "down": true, "clue": "same"}, {"cell": 1, "clue": "maybe"}],
              "plots": [{"row": 0, "column": 0, "height": 2, "width": 2, "state": "hint", "tint": 3}, {"row": 2, "column": 3, "height": 2, "width": 1}],
              "clock": {"seconds": 75.5, "running": true}}]}
            """)
        let p = try #require(b.puzzle)
        #expect(p.rows == 3 && p.columns == 4 && p.input == .drag)
        let first = p.cells[0]
        #expect(first.symbol == .heart && first.text == nil && first.notes == [1, 3] && first.region == nil && first.state == .conflict
                && first.given && first.fresh, "two characters a number, notes 1–9 once each, twelve regions")
        #expect(p.cells[1].symbol == nil && p.cells[1].text == "7", "only Sidefolk's own pieces")
        #expect(p.box == nil, "boxes must divide the grid")
        #expect(p.edges.count == GameBoard.Puzzle.maxEdges, "edges capped; one off the grid's side or with no clue dropped")
        #expect(p.plots.count == 1 && p.plots[0].state == .hint && p.plots[0].tint == 3, "a plot past the edge is dropped")
        #expect(p.seconds == 75.5 && p.running)

        // Too big, cells that don't fill it, or digits with no pad: not a puzzle.
        for bad in [#""rows": 11, "columns": 4, "cells": []"#, #""rows": 2, "columns": 2, "cells": [{}]"#,
                    #""rows": 2, "columns": 2, "input": "digits", "cells": [{}, {}, {}, {}]"#] {
            #expect(try Self.board(#"{"parts": [{"type": "puzzle", \#(bad)}]}"#).puzzle == nil, "\(bad)")
        }
        let sudoku = try Self.board(#"{"parts": [{"type": "puzzle", "rows": 6, "columns": 6, "input": "digits", "digits": 6, "box": [2, 3], "cells": [\#(Self.cells(36))]}]}"#)
        #expect(sudoku.puzzle?.box?.rows == 2 && sudoku.puzzle?.box?.columns == 3 && sudoku.puzzle?.digits == 6)
    }

    @Test func movesGoOnlyWhereThePuzzleTakesThem() throws {
        func puzzle(_ input: String, digits: String = "", locked: Bool = false) throws -> GameBoard {
            try Self.board(#"{"parts": [{"type": "puzzle", "rows": 9, "columns": 9, "input": "\#(input)" \#(digits), "locked": \#(locked),"#
                           + #""cells": [\#(Self.cells(81, #"{"text": "5", "given": true}"#))]}]}"#)
        }
        let tap = try puzzle("tap"), drag = try puzzle("drag"), digits = try puzzle("digits", digits: #", "digits": 9"#)
        #expect(GameMove.cell(row: 8, column: 8).offered(by: tap) && !GameMove.cell(row: 0, column: 0).offered(by: tap), "a given never changes")
        #expect(GameMove.cell(row: 0, column: 0).offered(by: drag), "a click on a drag board takes a plot away")
        #expect(GameMove.area(row: 0, column: 0, toRow: 8, toColumn: 3).offered(by: drag) && !GameMove.area(row: 0, column: 0, toRow: 1, toColumn: 1).offered(by: tap))
        #expect(GameMove.place(row: 1, column: 1, value: 9, note: false).offered(by: digits) && GameMove.place(row: 1, column: 1, value: 0, note: false).offered(by: digits))
        #expect(!GameMove.place(row: 0, column: 0, value: 3, note: true).offered(by: digits) && !GameMove.cell(row: 1, column: 1).offered(by: digits))
        #expect(!GameMove.cell(row: 2, column: 2).offered(by: try puzzle("tap", locked: true)))
        // The moves read and write as the channel carries them, up to a 10 × 10 grid.
        for move: GameMove in [.area(row: 0, column: 9, toRow: 3, toColumn: 2), .place(row: 4, column: 4, value: 0, note: true), .cell(row: 9, column: 9)] {
            #expect(GameMove.parse(move.json) == move)
        }
        #expect(GameMove.parse(["place": ["cell": [1, 1], "value": 12]]) == nil && GameMove.parse(["area": [0, 0, 10, 1]]) == nil)
    }

    @Test func theSolvedCardWaitsForTheLastMark() throws {
        let before = try Self.board(#"{"parts": [{"type": "puzzle", "rows": 2, "columns": 2, "cells": [{}, {}, {}, {}], "clock": {"seconds": 9, "running": true}}]}"#)
        let after = try Self.board("""
            {"parts": [{"type": "prompt", "text": "Solved!"}, {"type": "puzzle", "rows": 2, "columns": 2, "cells": [{"symbol": "star", "fresh": true}, {}, {}, {}],
              "clock": {"seconds": 12, "running": false}},
             {"type": "result", "figure": "0:12", "tone": "good"}], "over": true, "companion": {"move": "celebrate"}}
            """)
        let (build, wait) = try #require(GameSuspense.buildUp(from: before, to: after, picked: nil))
        #expect(wait == GameSuspense.beatSeconds && !GameSuspense.showsVerdict(build))
        #expect(build.puzzle?.locked == true && build.puzzle?.cells[0].symbol == .star && build.puzzle?.running == false,
                "the last mark shows and settles, the clock stopped")
        // An ordinary move gives nothing away: no build-up.
        let move = try Self.board(#"{"parts": [{"type": "puzzle", "rows": 2, "columns": 2, "cells": [{"symbol": "heart"}, {}, {}, {}]}]}"#)
        #expect(GameSuspense.buildUp(from: before, to: move, picked: nil) == nil)
    }

    @Test func puzzlesAreLooksOfTheirOwn() {
        for look in [GameLook.plots, .seesaw, .sudoku, .blossoms, .words] { #expect(look.solo) }
        #expect(!GameLook.cups.solo)
    }
}
