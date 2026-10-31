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

    public init(extensionId: String, extensionName: String, game: String, title: String, symbol: String? = nil, levels: [String] = [],
                ai: Bool = true, say: [String] = [], iconPath: String? = nil) {
        self.extensionId = extensionId
        self.extensionName = extensionName
        self.game = game
        self.title = title
        self.symbol = symbol
        self.levels = levels
        self.ai = ai
        self.say = say
        self.iconPath = iconPath
    }

    public var id: String { "\(extensionId)/\(game)" }
    public var isSidefolk: Bool { extensionId == Self.sidefolk }

    public static let sidefolk = "sidefolk"
    /// The best of three, Sidefolk's own (D44): its hand is drawn in core.
    public static let handsMatch = GameInfo(extensionId: sidefolk, extensionName: "Sidefolk", game: "rock_paper_scissors",
                                            title: String(localized: "Rock, Paper, Scissors", comment: "A game: the best of three against the companion"),
                                            symbol: "hand.raised.fill", say: [])
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
        if let s = board?.score {
            summary += " · " + String(localized: "You \(s.you) · \(companionName) \(s.companion)",
                                      comment: "A game's score: the person's, then the companion's (named)")
        }
        return ActivityEntry(at: at, caller: "user", tool: "games.play", risk: Risk.low.rawValue, decision: .auto, summary: summary,
                             args: ["extension": .string(info.extensionId), "game": .string(info.game)])
    }
}
