import Foundation

/// What a game extension's page says about its games for the Game Center (D93), under `games` beside its summary:
/// each game's tallies and best in its own words, its board or word of the day, and its last games. Numbers and short
/// text only: Sidefolk lays the center out, draws every picture from its own art by the game's look, and words the
/// rest. Read leniently and capped like the rest of a page: a bad record is left out, never the page.
///
///     "games": {
///       "records": {"trivia": {"played": 12, "won": 7, "lost": 4, "drawn": 1, "streak": 2, "best_streak": 4,
///                              "best": "Best of 10: 8", "today": {"text": "Solved in 4", "done": true, "streak": 3}}},
///       "recent": [{"game": "trivia", "at": "2026-11-01T09:30:00Z", "outcome": "won", "text": "You 7 · Mochi 6"}]
///     }
public struct GameCenterRecords: Sendable, Hashable {
    public struct Record: Sendable, Hashable {
        public var played = 0
        public var won = 0
        public var lost = 0
        public var drawn = 0
        /// Wins in a row now, and the most ever.
        public var streak = 0
        public var bestStreak = 0
        /// Its best in its own terms ("Best: 9 moves", "Fair 3:12").
        public var best: String?
        /// Its board or word of the day, for a game that has one.
        public var today: Today?

        public init(played: Int = 0, won: Int = 0, lost: Int = 0, drawn: Int = 0, streak: Int = 0, bestStreak: Int = 0, best: String? = nil,
                    today: Today? = nil) {
            (self.played, self.won, self.lost, self.drawn, self.streak, self.bestStreak) = (played, won, lost, drawn, streak, bestStreak)
            self.best = best
            self.today = today
        }
    }

    /// A game's daily: "Not played yet", "Solved in 4", "2 of 3 boards", whether today's is done, and the days in a row.
    public struct Today: Sendable, Hashable {
        public var text: String
        public var done: Bool
        public var streak: Int

        public init(text: String, done: Bool = false, streak: Int = 0) {
            self.text = text
            self.done = done
            self.streak = streak
        }
    }

    public enum Outcome: String, Sendable, Hashable {
        case won, lost, draw, solved

        /// What it means for the person, in GameVerdict's colours (D78): a solve is a good outcome like a win.
        public var verdict: GameVerdict { switch self { case .won, .solved: .win; case .lost: .loss; case .draw: .draw } }
    }

    /// One game played to the end.
    public struct Recent: Sendable, Hashable {
        public var game: String
        public var at: Date
        public var outcome: Outcome
        /// The score or time in the game's words ("You 7 · Mochi 6", "Solved in 3:12").
        public var text: String?

        public init(game: String, at: Date, outcome: Outcome, text: String? = nil) {
            self.game = game
            self.at = at
            self.outcome = outcome
            self.text = text
        }
    }

    /// Two people's head-to-head in a game (D96): two names, each one's wins, the draws.
    public struct Duel: Sendable, Hashable {
        public var game: String
        public var names: [String]
        public var wins: [Int]
        public var draws: Int

        public init(game: String, names: [String], wins: [Int], draws: Int = 0) {
            self.game = game
            self.names = names
            self.wins = wins
            self.draws = draws
        }
    }

    public var records: [String: Record]
    public var recent: [Recent]
    /// The games two people can play each other on this Mac (D96), by name.
    public var twoPlayers: Set<String>
    public var duels: [Duel]

    public init(records: [String: Record] = [:], recent: [Recent] = [], twoPlayers: Set<String> = [], duels: [Duel] = []) {
        self.records = records
        self.recent = recent
        self.twoPlayers = twoPlayers
        self.duels = duels
    }

    static let maxGames = 64
    static let maxRecent = 20
    static let maxCount = 1_000_000

    /// Reads `{records, recent}`; nil when it isn't that at all.
    public static func parse(_ json: JSONValue?) -> GameCenterRecords? {
        guard let object = json?.objectValue else { return nil }
        var records: [String: Record] = [:]
        for (game, value) in (object["records"]?.objectValue ?? [:]).sorted(by: { $0.key < $1.key }).prefix(maxGames) {
            guard isName(game), let r = record(value) else { continue }
            records[game] = r
        }
        let recent = (object["recent"]?.arrayValue ?? []).prefix(maxRecent).compactMap { j -> Recent? in
            guard let game = j["game"]?.stringValue, isName(game),
                  let at = j["at"]?.stringValue.flatMap(ISO8601DateFormatter().date(from:)),
                  let outcome = j["outcome"]?.stringValue.flatMap(Outcome.init(rawValue:)) else { return nil }
            return Recent(game: game, at: at, outcome: outcome, text: ExtensionPage.text(j["text"], 60))
        }
        let two = Set((object["two_players"]?.arrayValue ?? []).prefix(maxGames).compactMap(\.stringValue).filter(isName))
        let duels = (object["duels"]?.arrayValue ?? []).prefix(maxRecent).compactMap { j -> Duel? in
            guard let game = j["game"]?.stringValue, isName(game) else { return nil }
            let names = (j["names"]?.arrayValue ?? []).compactMap { ExtensionPage.text($0, 24) }
            let wins = (j["wins"]?.arrayValue ?? []).compactMap(\.intValue).map { Swift.min(maxCount, Swift.max(0, $0)) }
            guard names.count == 2, wins.count == 2 else { return nil }
            return Duel(game: game, names: names, wins: wins, draws: Swift.min(maxCount, Swift.max(0, j["draws"]?.intValue ?? 0)))
        }
        return GameCenterRecords(records: records, recent: recent, twoPlayers: two, duels: Array(duels))
    }

    /// A game's name as the manifest has it, or a tally of its own under it (`higher_lower_yours`).
    static func isName(_ s: String) -> Bool { s.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil }

    static func record(_ j: JSONValue) -> Record? {
        guard j.objectValue != nil else { return nil }
        func count(_ key: String) -> Int { Swift.min(maxCount, Swift.max(0, j[key]?.intValue ?? 0)) }
        var r = Record(played: count("played"), won: count("won"), lost: count("lost"), drawn: count("drawn"), streak: count("streak"),
                       bestStreak: count("best_streak"), best: ExtensionPage.text(j["best"], 80))
        if let t = j["today"], let text = ExtensionPage.text(t["text"], 60) {
            r.today = Today(text: text, done: t["done"]?.boolValue ?? false, streak: Swift.min(maxCount, Swift.max(0, t["streak"]?.intValue ?? 0)))
        }
        return r
    }
}
