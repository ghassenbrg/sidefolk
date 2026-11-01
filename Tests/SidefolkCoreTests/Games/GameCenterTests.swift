import Foundation
@testable import SidefolkCore
import Testing

/// The Game Center's data (D93): a game extension's records read leniently from its page, put together with the
/// games and Sidefolk's Activity rows, and badges earned only from those numbers.
struct GameCenterTests {
    static let trivia = GameInfo(extensionId: "dev.sidefolk.playtime", extensionName: "Playtime", game: "trivia", title: "Trivia", look: .quiz)
    static let numbers = GameInfo(extensionId: "dev.sidefolk.playtime", extensionName: "Playtime", game: "higher_lower", title: "Higher or Lower",
                                  look: .numbers)
    static let sudoku = GameInfo(extensionId: "dev.sidefolk.playtime", extensionName: "Playtime", game: "sudoku", title: "Sudoku", look: .sudoku)
    static let words = GameInfo(extensionId: "dev.sidefolk.playtime", extensionName: "Playtime", game: "daily_word", title: "Daily Word", look: .words)

    @Test func recordsAreReadLenientlyAndCapped() throws {
        let page = try ExtensionPage.parse(try JSONValue.parse("""
            {"summary": {"title": "Daily Word: Not played yet"},
             "games": {"records": {"trivia": {"played": 12, "won": 7, "lost": 4, "drawn": 1, "streak": 2, "best_streak": 4, "best": "Best of 10: 8"},
                                   "sudoku": {"played": 3, "won": 3, "today": {"text": "Today: Fair 3:12", "done": true, "streak": 5}},
                                   "Bad Name": {"played": 1}, "copy_me": "nope", "daily_word": {"played": -4, "won": 2000000000}},
                       "recent": [{"game": "trivia", "at": "2026-11-01T09:30:00Z", "outcome": "won", "text": "You 7 · Mochi 6"},
                                  {"game": "trivia", "at": "yesterday", "outcome": "won"},
                                  {"game": "sudoku", "at": "2026-10-31T09:30:00Z", "outcome": "solved"}]}}
            """))
        let games = try #require(page.games)
        #expect(games.records.keys.sorted() == ["daily_word", "sudoku", "trivia"])
        #expect(games.records["trivia"] == GameCenterRecords.Record(played: 12, won: 7, lost: 4, drawn: 1, streak: 2, bestStreak: 4, best: "Best of 10: 8"))
        #expect(games.records["sudoku"]?.today == GameCenterRecords.Today(text: "Today: Fair 3:12", done: true, streak: 5))
        #expect(games.records["daily_word"]?.played == 0 && games.records["daily_word"]?.won == 1_000_000)
        #expect(games.recent.map(\.outcome) == [.won, .solved], "a row without a readable date is left out")
        #expect(try ExtensionPage.parse(try JSONValue.parse(#"{"summary": {"title": "Hi"}}"#)).games == nil)
    }

    @Test func theCenterPutsRecordsActivityAndGamesTogether() {
        func row(_ game: GameInfo, _ result: GameVerdict, _ minutesAgo: Double) -> ActivityEntry {
            ActivityEntry(at: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60), caller: "user", tool: "games.play", risk: "low", decision: .auto,
                          summary: "Played", args: ["extension": .string(game.extensionId), "game": .string(game.game), "result": .string(result.rawValue)])
        }
        // Newest first, as Activity gives them.
        let rows = [row(.handsMatch, .win, 1), row(.handsMatch, .win, 2), row(Self.trivia, .loss, 3), row(.handsMatch, .loss, 4), row(.handsMatch, .win, 5)]
        let records = GameCenterRecords(records: ["trivia": .init(played: 12, won: 7, bestStreak: 4),
                                                  "sudoku": .init(played: 10, won: 10, today: .init(text: "Solved", done: true, streak: 7)),
                                                  "daily_word": .init(played: 2, won: 1, today: .init(text: "Not played yet", streak: 3))],
                                        recent: [.init(game: "trivia", at: Date(timeIntervalSince1970: 1_000_000 - 150), outcome: .lost, text: "You 3 · Mochi 5"),
                                                 .init(game: "higher_lower_yours", at: Date(timeIntervalSince1970: 500), outcome: .lost)])
        let games = [GameInfo.handsMatch, Self.trivia, Self.numbers, Self.sudoku, Self.words]
        let center = GameCenter(games: games, extensionId: "dev.sidefolk.playtime", records: records, rows: rows)

        let rps = center.entries[0]
        #expect(rps.record.played == 4 && rps.record.won == 3 && rps.record.streak == 2 && rps.record.bestStreak == 2 && rps.record.lost == 1,
                "Sidefolk's own game is counted from Activity")
        #expect(rps.last == Date(timeIntervalSince1970: 1_000_000 - 60))
        #expect(center.entries[1].record.played == 12 && center.entries[1].last != nil, "the extension's tally, Activity's last time")
        #expect(center.entries[2].record.played == 0 && center.entries[2].last == nil)
        #expect(center.group(.versus).map(\.info.game) == ["rock_paper_scissors", "trivia", "higher_lower"])
        #expect(center.group(.puzzles).map(\.info.game) == ["sudoku", "daily_word"])
        #expect(center.dailies.map(\.info.game) == ["sudoku", "daily_word"])
        #expect(center.totals.wins == 10 && center.totals.solved == 11 && center.totals.played == 28 && center.totals.bestStreak == 4
                && center.totals.dailyStreak == 7)
        // Recent: the extension's own rows (a tally under a game's prefix included) with Sidefolk's game from Activity; the
        // extension's games aren't counted twice from Activity.
        #expect(center.recent.map(\.game) == ["sidefolk/rock_paper_scissors", "sidefolk/rock_paper_scissors", "trivia",
                                              "sidefolk/rock_paper_scissors", "sidefolk/rock_paper_scissors", "higher_lower_yours"])
        #expect(center.entry(for: center.recent.last!)?.info.game == "higher_lower")

        let badges = Dictionary(uniqueKeysWithValues: center.badges.map { ($0.kind, $0) })
        #expect(badges[.firstWin]?.earned == true && badges[.tenWins]?.earned == true && badges[.fiftyWins]?.value == 10)
        #expect(badges[.hatTrick]?.earned == true && badges[.fiveInARow]?.value == 4)
        #expect(badges[.explorer]?.value == 4 && badges[.explorer]?.goal == 5 && badges[.explorer]?.earned == false)
        #expect(badges[.puzzler]?.earned == true && badges[.dailyWeek]?.earned == true)
        #expect(badges[.fullDay]?.value == 1 && badges[.fullDay]?.goal == 2)

        // Without records, every game is counted from Activity, and nothing is invented.
        let bare = GameCenter(games: games, extensionId: "dev.sidefolk.playtime", records: nil, rows: [])
        #expect(bare.totals.played == 0 && bare.dailies.isEmpty && bare.badges.allSatisfy { !$0.earned })
        #expect(!bare.badges.contains { $0.kind == .dailyWeek })
    }
}
