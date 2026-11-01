#if DEBUG
import AppKit
import SidefolkCore

/// The Game Center (D93) for the UI snapshots: Playtime's games as its manifest and `strings/` declare them (from the
/// add-ons beside this repository, or `SIDEFOLK_ADDONS_REPO`), in the snapshot's language, with records a person who
/// plays most days would have, Sidefolk's own match from Activity, and a game put away. `many` adds games a future
/// Playtime might bring, to see the center scale.
@MainActor
enum SampleGameCenter {
    static let id = "dev.sidefolk.playtime"

    static var info: ExtensionPageInfo {
        ExtensionPageInfo(extensionId: id, extensionName: "Playtime", page: "playtime", title: "Playtime", symbol: "gamecontroller.fill", refresh: 30,
                          widget: true, iconPath: FixtureServices.addonIcon("playtime"), gameCenter: true)
    }

    static func model(many: Bool = false, empty: Bool = false) -> GameCenterModel {
        var games = playtimeGames()
        if many {
            for (game, title, tagline, look) in [("connect_four", "Connect Four", "Four in a row, against gravity", GameLook.grid),
                                                 ("word_chain", "Word Chain", "Each word starts where the last one ended", .balloons),
                                                 ("snap", "Snap", "Spot the pair before your companion", .cards),
                                                 ("dots", "Dots and Boxes", "Close a box, take another turn", nil),
                                                 ("crossword", "Mini Crossword", "Five clues, one small grid", .words),
                                                 ("nonogram", "Nonogram", "Paint the picture the numbers hide", .sudoku)] {
                games.append(GameInfo(extensionId: id, extensionName: "Playtime", game: game, title: title, levels: ["easy", "fair", "hard"],
                                      tagline: tagline, look: look))
            }
        }
        let now = Date()
        let page = ExtensionPage(summary: .init(title: "Daily Word: Not played yet", detail: "Streak 4", symbol: "textformat.abc"),
                                 games: empty ? nil : records(now: now, games: games))
        let pageModel = ExtensionPageModel(info: info, page: page, history: [:], alerts: [], updated: now)
        var settings = GameSettings()
        settings.levels["\(id)/tictactoe"] = "hard"
        settings.sneaky = true
        let shelf = GameCenterModel.games(for: id, shelf: games)
        return GameCenterModel(page: pageModel, games: shelf, rows: empty ? [] : rows(now: now), kept: empty ? nil : shelf.first { $0.game == "which_cup" },
                               settings: settings, companionName: "Mochi",
                               figure: SamplePlayBoards.figure ?? CompanionArt.portrait(for: AppSettings(), state: .listening, side: 220),
                               avatar: CompanionArt.avatar(for: AppSettings(), side: 40))
    }

    /// Playtime's games from its manifest, titles and taglines in the snapshot's language.
    static func playtimeGames() -> [GameInfo] {
        let folder = URL(fileURLWithPath: FixtureServices.addonIcon("playtime")).deletingLastPathComponent()
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("sidefolk-extension.json")),
              let manifest = try? JSONValue.parse(String(decoding: data, as: UTF8.self)), let games = manifest["games"]?.objectValue else { return [] }
        let language = ExtensionStrings.current
        let words = ["\(language).json", "\(language.prefix(2)).json"].lazy
            .compactMap { try? Data(contentsOf: folder.appendingPathComponent("strings/\($0)")) }
            .compactMap { try? JSONValue.parse(String(decoding: $0, as: UTF8.self)) }.first
        return games.keys.sorted().compactMap { key in
            guard let g = games[key] else { return nil }
            let shown = words?["games"]?[key]
            return GameInfo(extensionId: id, extensionName: "Playtime", game: key, title: shown?["title"]?.stringValue ?? g["title"]?.stringValue ?? key,
                            symbol: g["symbol"]?.stringValue, levels: g["levels"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                            say: g["say"]?.arrayValue?.compactMap(\.stringValue) ?? [], iconPath: FixtureServices.addonIcon("playtime"),
                            tagline: shown?["tagline"]?.stringValue ?? g["tagline"]?.stringValue, look: g["look"]?.stringValue.flatMap(GameLook.init(rawValue:)))
        }
    }

    /// What Playtime would say of a person who plays most days (its own words are English here: they come from the
    /// extension in the person's language in the app).
    private static func records(now: Date, games: [GameInfo]) -> GameCenterRecords {
        typealias R = GameCenterRecords.Record
        var r: [String: R] = [
            "trivia": R(played: 14, won: 9, lost: 4, drawn: 1, streak: 3, bestStreak: 4, best: "Best of 10: 9"),
            "tictactoe": R(played: 21, won: 8, lost: 6, drawn: 7, streak: 0, bestStreak: 3),
            "copy_me": R(played: 6, won: 0, lost: 6, best: "Best: 11 moves"),
            "quick_paws": R(played: 9, won: 5, lost: 4, streak: 1, bestStreak: 2, best: "Best: 212 ms"),
            "which_cup": R(played: 12, won: 7, lost: 5, streak: 2, bestStreak: 5),
            "higher_lower": R(played: 8, won: 6, lost: 2, best: "Best: 5 guesses"),
            "balloon_words": R(played: 5, won: 3, lost: 2),
            "last_stick": R(played: 4, won: 1, lost: 3),
            "daily_word": R(played: 26, won: 24, lost: 2, streak: 4, bestStreak: 11, best: "Best: 3 guesses",
                            today: .init(text: "Not played yet", done: false, streak: 4)),
            "plots": R(played: 11, won: 11, best: "Fair 2:41", today: .init(text: "Today: Easy 1:12 · 2 more to play", done: true, streak: 6)),
            "seesaw": R(played: 7, won: 7, best: "Easy 1:55", today: .init(text: "Today: 3 boards to play", streak: 0)),
            "sudoku": R(played: 19, won: 19, best: "Fair 6:02, Hard 14:31", today: .init(text: "Today: Fair 5:48", done: true, streak: 9)),
            "blossoms": R(played: 3, won: 3, best: "Fair 4:10", today: .init(text: "Today: 3 boards to play", streak: 0)),
        ]
        if games.contains(where: { $0.game == "connect_four" }) { r["connect_four"] = R(played: 3, won: 2, lost: 1) }
        let minute: TimeInterval = 60
        let recent: [GameCenterRecords.Recent] = [
            .init(game: "sudoku", at: now - 25 * minute, outcome: .solved, text: "Solved in 5:48"),
            .init(game: "which_cup", at: now - 50 * minute, outcome: .won, text: "You 3 · Mochi 2"),
            .init(game: "trivia", at: now - 3 * 60 * minute, outcome: .won, text: "You 8 · Mochi 6"),
            .init(game: "tictactoe", at: now - 26 * 60 * minute, outcome: .draw),
            .init(game: "copy_me", at: now - 27 * 60 * minute, outcome: .lost, text: "11 moves"),
            .init(game: "plots", at: now - 28 * 60 * minute, outcome: .solved, text: "Solved in 1:12"),
        ]
        return GameCenterRecords(records: r, recent: recent)
    }

    /// Sidefolk's own best of three, and the last time each game was played.
    private static func rows(now: Date) -> [ActivityEntry] {
        func row(_ game: String, _ result: GameVerdict?, hoursAgo: Double) -> ActivityEntry {
            var args: [String: JSONValue] = ["extension": .string(game == "rock_paper_scissors" ? GameInfo.sidefolk : id), "game": .string(game)]
            if let result { args["result"] = .string(result.rawValue) }
            return ActivityEntry(at: now - hoursAgo * 3600, caller: "user", tool: "games.play", risk: "low", decision: .auto, summary: "Played",
                                 args: .object(args))
        }
        return [row("sudoku", .win, hoursAgo: 0.4), row("which_cup", .win, hoursAgo: 0.8), row("rock_paper_scissors", .win, hoursAgo: 2),
                row("trivia", .win, hoursAgo: 3), row("rock_paper_scissors", .loss, hoursAgo: 5), row("tictactoe", .draw, hoursAgo: 26),
                row("copy_me", .loss, hoursAgo: 27), row("plots", .win, hoursAgo: 28), row("quick_paws", .win, hoursAgo: 50),
                row("higher_lower", .win, hoursAgo: 75), row("daily_word", .win, hoursAgo: 24), row("seesaw", .win, hoursAgo: 120),
                row("balloon_words", .loss, hoursAgo: 140), row("blossoms", .win, hoursAgo: 170), row("last_stick", .loss, hoursAgo: 200)]
    }
}
#endif
