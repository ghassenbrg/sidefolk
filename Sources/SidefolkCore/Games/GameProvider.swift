import Foundation
import Synchronization

/// A game the Play panel can open (D75): an extension's (`games` in its manifest) or Sidefolk's own.
public struct GameInfo: Sendable, Hashable, Identifiable {
    /// The extension's id, or `sidefolk` for the companion's own games.
    public var extensionId: String
    public var extensionName: String
    public var game: String
    public var title: String
    public var symbol: String?
    public var levels: [String]
    /// Offered to Sidefolk's AI in `games.open`.
    public var ai: Bool
    /// The sentences that open it at once (`say`).
    public var say: [String]
    /// The extension's icon, for the badge that says whose game it is; nil for Sidefolk's own.
    public var iconPath: String?
    /// One line under its title on the panel's menu card, in the person's language.
    public var tagline: String?
    /// The look Sidefolk dresses it in (its colour, scene and icon); nil is the plain one.
    public var look: GameLook?

    public init(extensionId: String, extensionName: String, game: String, title: String, symbol: String? = nil, levels: [String] = [],
                ai: Bool = true, say: [String] = [], iconPath: String? = nil, tagline: String? = nil, look: GameLook? = nil) {
        self.extensionId = extensionId
        self.extensionName = extensionName
        self.game = game
        self.title = title
        self.symbol = symbol
        self.levels = levels
        self.ai = ai
        self.say = say
        self.iconPath = iconPath
        self.tagline = tagline
        self.look = look
    }

    public var id: String { "\(extensionId)/\(game)" }
    public var isSidefolk: Bool { extensionId == Self.sidefolk }

    public static let sidefolk = "sidefolk"
    /// The best of three, Sidefolk's own (D44): its hand is drawn in core.
    public static let handsMatch = GameInfo(extensionId: sidefolk, extensionName: "Sidefolk", game: "rock_paper_scissors",
                                            title: String(localized: "Rock, Paper, Scissors", comment: "A game: the best of three against the companion"),
                                            symbol: "hand.raised.fill", say: [],
                                            tagline: String(localized: "Best of three, no peeking", comment: "Rock, Paper, Scissors on the Play panel's menu"),
                                            look: .hands)
}

/// How a game starts: the level, the person's language (`en`, `de`, `ar`) and Sidefolk's options for every game
/// (`tone`, `sneaky`).
public struct GameSetup: Sendable, Hashable {
    public var level: String?
    public var language: String
    public var options: [String: JSONValue]

    public init(level: String? = nil, language: String = "en", options: [String: JSONValue] = [:]) {
        self.level = level
        self.language = language
        self.options = options
    }
}

/// Where a game's boards come from: an extension through the game channel (`ExtensionGame`) or Sidefolk itself
/// (`HandsMatch`). The Play panel has one path for both, so Sidefolk's own game proves the platform.
public protocol GameProvider: AnyObject, Sendable {
    var info: GameInfo { get }
    func start(_ setup: GameSetup) async throws -> GameBoard
    func move(_ move: GameMove) async throws -> GameBoard
    func end(_ reason: GameEndReason) async
}

/// An extension's game, played over `sidefolk/game.*` (ExtensionHost+Games).
public final class ExtensionGame: GameProvider {
    public let info: GameInfo
    private let host: ExtensionHost
    private let session = Mutex<String?>(nil)

    public init(info: GameInfo, host: ExtensionHost) {
        self.info = info
        self.host = host
    }

    public func start(_ setup: GameSetup) async throws -> GameBoard {
        let (id, board) = try await host.startGame(extensionId: info.extensionId, game: info.game, setup: setup)
        session.withLock { $0 = id }
        return board
    }

    public func move(_ move: GameMove) async throws -> GameBoard {
        guard let id = session.withLock({ $0 }) else { throw UserFacingError("That game has ended.") }
        return try await host.moveGame(extensionId: info.extensionId, game: info.game, session: id, move: move)
    }

    public func end(_ reason: GameEndReason) async {
        guard let id = session.withLock({ s -> String? in defer { s = nil }; return s }) else { return }
        await host.endGame(extensionId: info.extensionId, game: info.game, session: id, reason: reason)
    }
}

/// The one Activity row a game leaves (D75), written when it ends rather than a row a move: "Played Trivia with
/// Playtime · You 7 · Mochi 6".
public enum GameRecord {
    public static func entry(_ info: GameInfo, last board: GameBoard?, companionName: String, at: Date) -> ActivityEntry {
        let with = info.isSidefolk ? companionName : info.extensionName
        var summary = String(localized: "Played \(info.title) with \(with)", comment: "Activity: a game played in the Play panel, then who with")
        // Two people played each other (D96): their names and points, and no result, so the person's record against
        // the companion (`GameStats`) stays theirs alone.
        if let s = board?.score, let players = s.players {
            summary = String(localized: "Played \(info.title): \(players[0]) \(s.you) · \(players[1]) \(s.companion)",
                             comment: "Activity: two people played a game against each other on this Mac, each name then its points")
            return ActivityEntry(at: at, caller: "user", tool: "games.play", risk: Risk.low.rawValue, decision: .auto, summary: summary,
                                 args: ["extension": .string(info.extensionId), "game": .string(info.game), "players": 2])
        }
        if let s = board?.score {
            summary += " · " + String(localized: "You \(s.you) · \(companionName) \(s.companion)",
                                      comment: "A game's score: the person's, then the companion's (named)")
        }
        var args: [String: JSONValue] = ["extension": .string(info.extensionId), "game": .string(info.game)]
        // How it ended for the person, when it did: the menu's stats are counted from these rows (`GameStats`).
        if let board, board.over, let result = board.result { args["result"] = .string(GameVerdict(tone: result.tone).rawValue) }
        return ActivityEntry(at: at, caller: "user", tool: "games.play", risk: Risk.low.rawValue, decision: .auto, summary: summary,
                             args: .object(args))
    }
}

/// The person's games at a glance, for the Play panel's menu: counted from Sidefolk's own Activity rows (`games.play`),
/// so they cover every game, Sidefolk's and the extensions', and nothing is read from a game's own records.
public struct GameStats: Sendable, Hashable {
    /// Games played to the end.
    public var played = 0
    public var wins = 0
    /// Wins in a row up to the latest game.
    public var streak = 0
    /// The longest run of wins.
    public var bestStreak = 0

    public init() {}

    /// From Activity rows, newest first as `ActivityStore.recent` gives them.
    public init(_ rows: [ActivityEntry]) {
        var run = 0, counting = true
        for row in rows where row.tool == "games.play" {
            guard let result = row.args?["result"]?.stringValue.flatMap(GameVerdict.init(rawValue:)) else { continue }
            played += 1
            if result == .win {
                wins += 1
                run += 1
                if counting { streak += 1 }
            } else {
                counting = false
                run = 0
            }
            bestStreak = max(bestStreak, run)
        }
    }
}
