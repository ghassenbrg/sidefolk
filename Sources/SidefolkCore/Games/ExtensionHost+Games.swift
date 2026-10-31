import Foundation
import Synchronization

/// The game channel (D75): `sidefolk/game.start`, `game.move` and `game.end`, not tool calls. A move a second would
/// put a row in Activity and the Guard in front of every click; a move can only change the game's own state in its own
/// folder, and its answer is data Sidefolk draws. Anything that acts on the world stays a tool, behind Guard.
extension ExtensionHost {
    /// How long a game may take to answer a move, how large an answer may be, and how fast Sidefolk sends moves.
    public static let gameReplySeconds: TimeInterval = 2
    public static let gameMovesPerSecond = 20

    /// Opens a game, ending whatever game was open: one Play panel, one game.
    public func startGame(extensionId id: String, game: String, setup: GameSetup) async throws -> (session: String, board: GameBoard) {
        if let open = openGame { await endGame(extensionId: open.extensionId, game: open.game, session: open.session, reason: .closed) }
        let (client, name) = try await gameClient(id, game)
        begin(id)
        defer { end(id) }
        var params: [String: JSONValue] = ["game": .string(game), "language": .string(setup.language), "options": .object(setup.options)]
        if let level = setup.level { params["level"] = .string(level) }
        let reply = try await ask(client, "sidefolk/game.start", params, name: name)
        guard let session = reply["session"]?.stringValue.flatMap(Self.sessionId) else {
            throw UserFacingError(verbatim: Self.noAnswer(name))
        }
        let board = try Self.board(reply, name: name)
        openGame = OpenGame(extensionId: id, game: game, session: session)
        return (session, board)
    }

    /// The person's move, sent only while the panel shows that game, at most 20 a second.
    public func moveGame(extensionId id: String, game: String, session: String, move: GameMove, now: Date = Date()) async throws -> GameBoard {
        guard var open = openGame, open.extensionId == id, open.game == game, open.session == session else {
            throw UserFacingError("That game has ended.")
        }
        guard open.allow(at: now) else { throw UserFacingError("That's faster than a game takes moves.") }
        openGame = open
        let (client, name) = try await gameClient(id, game)
        begin(id)
        defer { end(id) }
        let reply = try await ask(client, "sidefolk/game.move", ["game": .string(game), "session": .string(session), "move": move.json], name: name)
        return try Self.board(reply, name: name)
    }

    /// The panel closed, the game was left too long, or it finished. The game hears it once; nothing comes back.
    public func endGame(extensionId id: String, game: String, session: String, reason: GameEndReason) async {
        guard let open = openGame, open.extensionId == id, open.game == game, open.session == session else { return }
        openGame = nil
        guard let (client, name) = try? await gameClient(id, game) else { return }
        begin(id)
        defer { end(id) }
        _ = try? await ask(client, "sidefolk/game.end", ["game": .string(game), "session": .string(session), "reason": .string(reason.rawValue)],
                           name: name)
    }

    private func ask(_ client: MCPClient, _ method: String, _ params: [String: JSONValue], name: String) async throws -> JSONValue {
        do {
            return try await client.request(method, params: .object(params), timeout: Self.gameReplySeconds)
        } catch is MCPError {
            throw UserFacingError(verbatim: Self.noAnswer(name))
        }
    }

    static func board(_ reply: JSONValue, name: String) throws -> GameBoard {
        guard reply.jsonString.utf8.count <= GameBoard.maxBytes, let board = reply["board"] else { throw UserFacingError(verbatim: noAnswer(name)) }
        return try GameBoard.parse(board)
    }

    public static func noAnswer(_ name: String) -> String {
        String(localized: "\(name) didn't answer, so the game ended.", comment: "An extension's game stopped answering; the name is the extension's")
    }

    /// A session id a game chose: up to 64 letters, digits, `_` and `-`.
    static func sessionId(_ s: String) -> String? {
        s.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil ? s : nil
    }
}

/// The game open in the Play panel, and when its last moves came.
struct OpenGame: Sendable {
    let extensionId: String
    let game: String
    let session: String
    private var moves: [Date] = []

    init(extensionId: String, game: String, session: String) {
        self.extensionId = extensionId
        self.game = game
        self.session = session
    }

    /// Whether one more move fits in the last second.
    mutating func allow(at now: Date) -> Bool {
        moves = moves.filter { now.timeIntervalSince($0) < 1 }
        guard moves.count < ExtensionHost.gameMovesPerSecond else { return false }
        moves.append(now)
        return true
    }
}

/// The games of enabled extensions, kept where the sentence matcher can read them at once.
public final class GameShelf: Sendable {
    private let games = Mutex<[GameInfo]>([])
    public init() {}
    public var all: [GameInfo] { games.withLock { $0 } }
    func set(_ list: [GameInfo]) { games.withLock { $0 = list } }
}
