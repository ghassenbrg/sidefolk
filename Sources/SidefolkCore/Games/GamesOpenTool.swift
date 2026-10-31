import Foundation

/// A game to open in the Play panel, and whether the panel takes the keyboard: it does when the person asked
/// (their words, the Play menu, Home), and waits for a click when the AI opened it (D75).
public struct GameRequest: Sendable, Hashable {
    public var info: GameInfo
    public var level: String?
    public var focus: Bool

    public init(info: GameInfo, level: String? = nil, focus: Bool = true) {
        self.info = info
        self.level = level
        self.focus = focus
    }
}

/// `games.open`: opens a game in the Play panel beside the companion. Opening a game only shows a panel, so it needs no
/// approval; it is a tool so the person's words, the Play menu and the AI reach it the same way, audited.
struct GamesOpenTool: Tool {
    let events: EventBus
    let shelf: GameShelf

    var spec: ToolSpec {
        let games = ([GameInfo.handsMatch] + shelf.all.filter(\.ai)).map { g in
            "\(g.extensionId)/\(g.game) (\(g.title)\(g.levels.isEmpty ? "" : ", levels: " + g.levels.joined(separator: ", ")))"
        }
        return ToolSpec(
            name: "games.open", title: String(localized: "Open a game"),
            description: """
                Opens a game the user plays against you in the Play panel beside the companion, offline and without you: \
                the game runs itself once open. Use it when the user wants to play, or for a break ("want a round of \
                trivia?"). Games: \(games.joined(separator: "; ")).
                """,
            inputSchema: Schema.object([
                "extension": Schema.string("Who the game belongs to: the part before the slash above (sidefolk for the companion's own)."),
                "game": Schema.string("The game's name: the part after the slash."),
                "level": Schema.string("One of the game's levels, if it has them."),
            ], required: ["extension", "game"]),
            risk: .low, capabilities: [.system], category: .system, mutates: false)
    }

    func summary(for input: JSONValue) -> String {
        find(input).map { String(localized: "Play \($0.title)", comment: "Opening a game in the Play panel: “Play Trivia”") }
            ?? String(localized: "Open a game")
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope() }

    func find(_ input: JSONValue) -> GameInfo? {
        guard let id = input.string("extension"), let game = input.string("game") else { return nil }
        if id == GameInfo.sidefolk { return game == GameInfo.handsMatch.game ? .handsMatch : nil }
        return shelf.all.first { $0.extensionId == id && $0.game == game }
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let info = find(input) else {
            throw ToolError.invalidInput(String(localized: "There's no such game. Games are listed in this tool's description."))
        }
        let level = input.string("level").flatMap { info.levels.contains($0) ? $0 : nil }
        let focus = context.caller == .user
        events.publish(.game(GameRequest(info: info, level: level, focus: focus)))
        return ToolResult(text: "Opened \(info.title) in the Play panel beside the companion; the user plays it there. Say it in a few words.",
                          card: ResultCard(kind: .info, title: String(localized: "Play \(info.title)", comment: "Opening a game in the Play panel: “Play Trivia”")))
    }
}
