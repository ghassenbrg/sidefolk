import Foundation

/// What the Game Center shows (D93), put together from three true sources: the games themselves (their manifests,
/// `GameInfo`), what their extension's page says of them (`GameCenterRecords`: tallies, bests, the day's boards), and
/// Sidefolk's own Activity rows (`games.play`), which cover every game, Sidefolk's own too, and say when each was last
/// played. A game its extension says nothing about is counted from Activity alone. Nothing here is made up: a badge is
/// earned from these numbers or shown with how far there is to go.
public struct GameCenter: Sendable {
    /// A game with what is known of it.
    public struct Entry: Sendable, Hashable, Identifiable {
        public var info: GameInfo
        public var record: GameCenterRecords.Record
        /// The last time it was played to the end, from Activity.
        public var last: Date?

        public var id: String { info.id }
        /// Played alone, a puzzle: its wins are solves, not wins against the companion.
        public var solo: Bool { info.look?.solo ?? false }
    }

    /// Where a game sits: the menu's two groups, the same rule as the Play panel's menu (`GameLook.solo`); a game with
    /// no look plays against the companion.
    public enum Group: String, Sendable, CaseIterable {
        case versus, puzzles
    }

    public struct Totals: Sendable, Hashable {
        /// Games won against the companion.
        public var wins = 0
        /// Puzzles solved (their wins).
        public var solved = 0
        public var played = 0
        /// The longest run of wins in any game.
        public var bestStreak = 0
        /// The longest run of days of any game's daily, going now.
        public var dailyStreak = 0
    }

    public var entries: [Entry]
    public var recent: [GameCenterRecords.Recent]
    public var totals: Totals

    /// - Parameters:
    ///   - games: every game shown, in the menu's order.
    ///   - extensionId: the extension whose page this is: its records count for its games.
    ///   - rows: `games.play` Activity rows, newest first.
    public init(games: [GameInfo], extensionId: String, records: GameCenterRecords?, rows: [ActivityEntry]) {
        let plays = rows.filter { $0.tool == "games.play" }
        func key(_ row: ActivityEntry) -> String? {
            guard let ext = row.args?["extension"]?.stringValue, let game = row.args?["game"]?.stringValue else { return nil }
            return "\(ext)/\(game)"
        }
        var byGame: [String: [ActivityEntry]] = [:]
        for row in plays { if let k = key(row) { byGame[k, default: []].append(row) } }

        entries = games.map { info in
            let own = info.extensionId == extensionId ? records?.records[info.game] : nil
            let mine = byGame[info.id] ?? []
            return Entry(info: info, record: own ?? Self.counted(mine), last: mine.first?.at)
        }
        // The extension's own last games, with Sidefolk's games and other extensions' from Activity, newest first.
        let titled = Set(games.filter { $0.extensionId == extensionId }.map(\.game))
        var recent = (records?.recent ?? []).filter { r in titled.contains(r.game) || titled.contains(where: { r.game.hasPrefix($0 + "_") }) }
        let covered = records == nil ? Set<String>() : Set(games.filter { $0.extensionId == extensionId }.map(\.id))
        for row in plays {
            guard let k = key(row), !covered.contains(k), let info = games.first(where: { $0.id == k }),
                  let result = row.args?["result"]?.stringValue.flatMap(GameVerdict.init(rawValue:)) else { continue }
            let outcome: GameCenterRecords.Outcome = switch result {
            case .win: (info.look?.solo ?? false) ? .solved : .won
            case .loss: .lost
            case .draw: .draw
            }
            recent.append(GameCenterRecords.Recent(game: info.extensionId == extensionId ? info.game : info.id, at: row.at, outcome: outcome))
        }
        self.recent = Array(recent.sorted { $0.at > $1.at }.prefix(10))

        var t = Totals()
        for e in entries {
            if e.solo { t.solved += e.record.won } else { t.wins += e.record.won }
            t.played += e.record.played
            t.bestStreak = max(t.bestStreak, e.record.bestStreak)
            t.dailyStreak = max(t.dailyStreak, e.record.today?.streak ?? 0)
        }
        totals = t
    }

    /// A game's tallies from its Activity rows (newest first), for a game its extension says nothing about.
    static func counted(_ rows: [ActivityEntry]) -> GameCenterRecords.Record {
        var r = GameCenterRecords.Record()
        var run = 0, counting = true
        for row in rows {
            guard let result = row.args?["result"]?.stringValue.flatMap(GameVerdict.init(rawValue:)) else { continue }
            r.played += 1
            switch result {
            case .win:
                r.won += 1
                run += 1
                if counting { r.streak += 1 }
            case .loss:
                r.lost += 1
                counting = false
                run = 0
            case .draw:
                r.drawn += 1
                counting = false
                run = 0
            }
            r.bestStreak = max(r.bestStreak, run)
        }
        return r
    }

    /// The entries of a group, in order; empty groups are left out by the caller.
    public func group(_ group: Group) -> [Entry] { entries.filter { ($0.solo ? Group.puzzles : .versus) == group } }

    /// The games with a board or word of the day: today's highlights.
    public var dailies: [Entry] { entries.filter { $0.record.today != nil } }

    /// The entry a recent game belongs to (`higher_lower_yours` is Higher or Lower's).
    public func entry(for recent: GameCenterRecords.Recent) -> Entry? {
        entries.first { $0.info.game == recent.game || $0.info.id == recent.game } ?? entries.first { recent.game.hasPrefix($0.info.game + "_") }
    }

    /// The badges, earned or on their way, from these numbers only.
    public var badges: [GameBadge] {
        let tried = entries.filter { $0.record.played > 0 }.count
        let dailies = self.dailies
        let doneToday = dailies.filter { $0.record.today?.done == true }.count
        var out: [GameBadge] = [
            GameBadge(.firstWin, value: totals.wins, goal: 1),
            GameBadge(.tenWins, value: totals.wins, goal: 10),
            GameBadge(.fiftyWins, value: totals.wins, goal: 50),
            GameBadge(.hatTrick, value: totals.bestStreak, goal: 3),
            GameBadge(.fiveInARow, value: totals.bestStreak, goal: 5),
            GameBadge(.explorer, value: tried, goal: entries.count),
        ]
        if entries.contains(where: \.solo) { out.append(GameBadge(.puzzler, value: totals.solved, goal: 10)) }
        if !dailies.isEmpty {
            out.append(GameBadge(.dailyWeek, value: totals.dailyStreak, goal: 7))
            if dailies.count > 1 { out.append(GameBadge(.fullDay, value: doneToday, goal: dailies.count)) }
        }
        return out.filter { $0.goal > 0 }
    }
}

/// A badge in the Game Center: earned from the person's records (D93), or shown with how far there is to go.
public struct GameBadge: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case firstWin, tenWins, fiftyWins, hatTrick, fiveInARow, explorer, puzzler, dailyWeek, fullDay
    }

    public var kind: Kind
    public var value: Int
    public var goal: Int

    public init(_ kind: Kind, value: Int, goal: Int) {
        self.kind = kind
        self.value = min(value, goal)
        self.goal = goal
    }

    public var id: String { kind.rawValue }
    public var earned: Bool { value >= goal }
}
