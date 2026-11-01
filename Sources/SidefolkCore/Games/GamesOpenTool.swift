import Foundation

/// A game to open in the Play panel, and whether the panel takes the keyboard: it does when the person asked
/// (their words, the Play menu, Home), and waits for a click when the AI opened it (D75).
public struct GameRequest: Sendable, Hashable {
    public var info: GameInfo
    public var level: String?
    public var focus: Bool
    /// A new game even when this one was put away ("rematch", "make it harder"), rather than resuming it.
    public var fresh: Bool
    /// What the person said about the game ("about space", "up to 500"), passed to it with Sidefolk's options (D93).
    public var slots: GameSlots

    public init(info: GameInfo, level: String? = nil, focus: Bool = true, fresh: Bool = false, slots: GameSlots = GameSlots()) {
        self.info = info
        self.level = level
        self.focus = focus
        self.fresh = fresh
        self.slots = slots
    }
}

/// `games.open`: opens a game in the Play panel beside the companion, or, without a game (or `"game": "menu"`), the
/// panel's menu of every game (D79 amended). Since D93 it also does what the person's game commands do, so the AI can
/// too: `last` (resume the game put away, else open the last one), `again` (a new round of it), `random`, `center`
/// (the Game Center in Home), a level one step `harder` or `easier`, and the slots a game takes. All of it only shows a
/// panel or a page, so it needs no approval; it is a tool so the person's words, the Play menu and the AI reach it the
/// same way, audited.
struct GamesOpenTool: Tool {
    let events: EventBus
    let shelf: GameShelf
    let settings: SettingsStore
    let activity: ActivityStore

    /// What `game` may say besides a game's name.
    enum Special: String, CaseIterable { case menu, last, again, random, center }

    var spec: ToolSpec {
        let games = ([GameInfo.handsMatch] + shelf.all.filter(\.ai)).map { g in
            "\(g.extensionId)/\(g.game) (\(g.title)\(g.levels.isEmpty ? "" : ", levels: " + g.levels.joined(separator: ", ")))"
        }
        return ToolSpec(
            name: "games.open", title: String(localized: "Open a game"),
            description: """
                Opens a game the user plays against you in the Play panel beside the companion, offline and without you: \
                the game runs itself once open. Use it when the user wants to play, or for a break ("want a round of \
                trivia?"). Without a game (or with "game": "menu") it opens the panel's menu of every game: do that when \
                the user asks what games there are, to see them, or wants to play without naming one, rather than listing \
                them in words. "game" may also be "last" (resume the game put away, or open the last one played), "again" \
                (a new round of the last one: a rematch), "random" (you pick one), or "center" (the Game Center in Home: \
                the user's scores, records, badges and game settings). "level" may be "harder" or "easier" (one step from \
                the last). "players": 2 opens it for the user and a friend on this Mac. A quiz takes "topic" and "count"; a number game "min", "max" and "mode" (mine: the user \
                guesses your number; yours: you guess theirs). Games: \(games.joined(separator: "; ")).
                """,
            inputSchema: Schema.object([
                "extension": Schema.string("Who the game belongs to: the part before the slash above (sidefolk for the companion's own)."),
                "game": Schema.string("The game's name: the part after the slash; or menu, last, again, random or center. Leave both out for the menu."),
                "level": Schema.string("One of the game's levels, if it has them, or harder or easier."),
                "topic": Schema.string("A quiz's subject in the user's words, at most \(GameSlots.maxTopic) characters."),
                "count": Schema.integer("How many questions or rounds.", minimum: GameSlots.counts.lowerBound, maximum: GameSlots.counts.upperBound),
                "min": Schema.integer("A number game's lowest number.", minimum: GameSlots.range.lowerBound, maximum: GameSlots.range.upperBound),
                "max": Schema.integer("A number game's highest number.", minimum: GameSlots.range.lowerBound, maximum: GameSlots.range.upperBound),
                "mode": Schema.string("A number game: who guesses.", enum: GameSlots.Mode.allCases.map(\.rawValue)),
                "players": Schema.integer("2 when the user plays a friend on this Mac rather than you (any game but the puzzles and Guess My Animal).",
                                          minimum: 1, maximum: 2),
            ], required: []),
            risk: .low, capabilities: [.system], category: .system, mutates: false)
    }

    func summary(for input: JSONValue) -> String {
        switch Self.special(input) {
        case .menu: return String(localized: "Show the games", comment: "Opening the Play panel's menu of every game")
        case .center: return String(localized: "Show the Game Center", comment: "Opening Playtime's page in Home, the Game Center")
        case .random: return String(localized: "Play a random game", comment: "The companion picks a game to open")
        case .last, .again: return String(localized: "Play again", comment: "Opening the last game again")
        case nil: break
        }
        return find(input).map { String(localized: "Play \($0.title)", comment: "Opening a game in the Play panel: “Play Trivia”") }
            ?? String(localized: "Open a game")
    }

    /// No game named (an extension alone is no game either) is the menu; a special word without an extension is that.
    static func special(_ input: JSONValue) -> Special? {
        guard let game = input.string("game"), !game.isEmpty else { return .menu }
        return input.string("extension") == nil || game == Special.menu.rawValue ? Special(rawValue: game) : nil
    }

    static func wantsMenu(_ input: JSONValue) -> Bool { special(input) == .menu }

    func scope(for input: JSONValue) -> ToolScope { ToolScope() }

    func find(_ input: JSONValue) -> GameInfo? {
        guard let id = input.string("extension"), let game = input.string("game") else { return nil }
        return find(id: "\(id)/\(game)")
    }

    private func find(id: String) -> GameInfo? {
        if id == GameInfo.handsMatch.id { return .handsMatch }
        return shelf.all.first { $0.id == id }
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let focus = context.caller == .user
        let step = input.string("level").flatMap(GameLevels.Step.init(rawValue:))
        switch Self.special(input) {
        case .menu:
            return menu(focus: focus)
        case .center:
            events.publish(.gameCenter)
            return ToolResult(text: "Opened the Game Center in Home: the user's scores, records, badges and game settings. Say it in a few words.",
                              card: ResultCard(kind: .info, title: String(localized: "Show the Game Center",
                                                                          comment: "Opening Playtime's page in Home, the Game Center")))
        case .random:
            let all = [GameInfo.handsMatch] + shelf.all
            guard let info = all.filter({ $0.id != shelf.last?.id }).randomElement() ?? all.first else { return menu(focus: focus) }
            return try await open(info, input: input, focus: focus, fresh: true)
        case .last, .again:
            guard let info = await lastGame() else { return menu(focus: focus) }
            return try await open(info, input: input, focus: focus, fresh: Self.special(input) == .again || step != nil)
        case nil:
            guard let info = find(input) else {
                throw ToolError.invalidInput(String(localized: "There's no such game. Games are listed in this tool's description."))
            }
            return try await open(info, input: input, focus: focus, fresh: step != nil)
        }
    }

    private func menu(focus: Bool) -> ToolResult {
        events.publish(.gamesMenu(focus: focus))
        let titles = ([GameInfo.handsMatch] + shelf.all).map(\.title)
        return ToolResult(text: "Opened the Play panel's menu of games beside the companion: \(titles.joined(separator: ", ")). "
                              + "The user picks one there. Say it in a few words; don't list them.",
                          card: ResultCard(kind: .info, title: String(localized: "Show the games", comment: "Opening the Play panel's menu of every game")))
    }

    /// The game opened last in this run, else the last one Activity says was played.
    private func lastGame() async -> GameInfo? {
        if let id = shelf.last?.id, let info = find(id: id) { return info }
        guard let row = try? await activity.recent(limit: 1, tool: "games.play").first,
              let ext = row.args?["extension"]?.stringValue, let game = row.args?["game"]?.stringValue else { return nil }
        return find(id: "\(ext)/\(game)")
    }

    /// Opens `info` at the level asked (a level, or a step from the last), else the person's chosen one. A level the
    /// person asked for becomes theirs for that game, as the Game Center's setting; the AI's choice doesn't.
    private func open(_ info: GameInfo, input: JSONValue, focus: Bool, fresh: Bool) async throws -> ToolResult {
        let asked = input.string("level")
        let chosen = settings.current.games.levels[info.id].flatMap { info.levels.contains($0) ? $0 : nil }
        var level = asked.flatMap { info.levels.contains($0) ? $0 : nil }
        if let step = asked.flatMap(GameLevels.Step.init(rawValue:)) {
            guard !info.levels.isEmpty else {
                throw ToolError.invalidInput(String(localized: "\(info.title) has no levels.", comment: "Asked to make a game harder or easier"))
            }
            let current = shelf.last?.id == info.id ? shelf.last?.level ?? chosen : chosen
            guard let next = GameLevels.step(step, from: current, in: info.levels) else {
                throw ToolError.invalidInput(step == .harder
                    ? String(localized: "\(info.title) is already at its hardest.", comment: "Asked to make a game harder at its top level")
                    : String(localized: "\(info.title) is already at its easiest.", comment: "Asked to make a game easier at its first level"))
            }
            level = next
        }
        if let level, focus, level != chosen {
            let id = info.id
            await settings.update { $0.games.levels[id] = level }
        }
        let opened = level ?? chosen
        var slots = GameSlots(input)
        // Two people only where two can play (D96): not the puzzles, not Guess My Animal.
        if info.look?.solo == true || info.look == .animals { slots.players = nil }
        shelf.opened(info, level: opened)
        events.publish(.game(GameRequest(info: info, level: opened, focus: focus, fresh: fresh, slots: slots)))
        let title = opened.map { String(localized: "Play \(info.title) · \(GameLevels.name($0))", comment: "Opening a game at a level: “Play Trivia · Hard”") }
            ?? String(localized: "Play \(info.title)", comment: "Opening a game in the Play panel: “Play Trivia”")
        return ToolResult(text: "Opened \(info.title)\(opened.map { " (\($0))" } ?? "") in the Play panel beside the companion; the user plays it there. "
                              + "Say it in a few words.",
                          card: ResultCard(kind: .info, title: title))
    }
}
