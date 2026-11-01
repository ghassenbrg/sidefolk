import Foundation

/// `games.settings` (D93): the games' settings the Game Center shows, for the person's words ("turn game sounds off")
/// and the AI: sounds for every game, how the companion takes a win, Sneaky, and a game's level. Each only changes how
/// games play, so it is low risk and needs no approval; the Activity row says what changed.
struct GamesSettingsTool: Tool {
    let settings: SettingsStore
    let shelf: GameShelf

    var spec: ToolSpec {
        ToolSpec(
            name: "games.settings", title: String(localized: "Change game settings"),
            description: """
                Changes how the games in the Play panel play: "sounds" on or off for every game (each game's own speaker \
                button follows), "tone" (how you take a win: gentle, cheeky or competitive), "sneaky" (you may cheat for \
                fun where a game allows it, always owning up when caught), or a game's "level" (with its "extension" and \
                "game", as games.open lists them; "default" lets the game pick). Only what is given changes.
                """,
            inputSchema: Schema.object([
                "sounds": Schema.boolean("Game sounds on or off, for every game."),
                "tone": Schema.string("How you take a win.", enum: GameTone.allCases.map(\.rawValue)),
                "sneaky": Schema.boolean("Whether you may cheat for fun where a game allows it."),
                "extension": Schema.string("For a level: who the game belongs to."),
                "game": Schema.string("For a level: the game's name."),
                "level": Schema.string("One of the game's levels, or default."),
            ], required: []),
            risk: .low, capabilities: [.system], category: .system, mutates: true)
    }

    func summary(for input: JSONValue) -> String { Self.said(input, game: game(input)).first ?? String(localized: "Change game settings") }

    func scope(for input: JSONValue) -> ToolScope { ToolScope() }

    private func game(_ input: JSONValue) -> GameInfo? {
        guard let ext = input.string("extension"), let name = input.string("game") else { return nil }
        let id = "\(ext)/\(name)"
        return id == GameInfo.handsMatch.id ? .handsMatch : shelf.all.first { $0.id == id }
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let sounds = input["sounds"]?.boolValue, sneaky = input["sneaky"]?.boolValue
        let tone = input.string("tone").flatMap(GameTone.init(rawValue:))
        var level: (id: String, value: String?)?
        if let asked = input.string("level") {
            guard let info = game(input) else {
                throw ToolError.invalidInput(String(localized: "There's no such game. Games are listed in games.open's description."))
            }
            guard asked == "default" || info.levels.contains(asked) else {
                throw ToolError.invalidInput(String(localized: "\(info.title) has no level “\(asked)”.", comment: "A game's level the game doesn't have"))
            }
            level = (info.id, asked == "default" ? nil : asked)
        }
        guard sounds != nil || sneaky != nil || tone != nil || level != nil else {
            throw ToolError.invalidInput(String(localized: "Say what to change: sounds, tone, sneaky or a game's level."))
        }
        let newLevel = level
        await settings.update { s in
            // Every game, so a speaker turned on in one game doesn't keep playing after "sounds off".
            if let sounds { s.games.sounds = sounds; s.games.speakers = [:] }
            if let sneaky { s.games.sneaky = sneaky }
            if let tone { s.games.tone = tone }
            if let newLevel { s.games.levels[newLevel.id] = newLevel.value }
        }
        let said = Self.said(input, game: game(input))
        return ToolResult(text: "Changed: \(said.joined(separator: "; ")).",
                          card: ResultCard(kind: .info, title: said.joined(separator: " · ")))
    }

    /// What changes, in the person's words, one line each.
    static func said(_ input: JSONValue, game: GameInfo?) -> [String] {
        var out: [String] = []
        if let on = input["sounds"]?.boolValue {
            out.append(on ? String(localized: "Game sounds on", comment: "games.settings: sounds turned on for every game")
                : String(localized: "Game sounds off", comment: "games.settings: sounds turned off for every game"))
        }
        if let tone = input.string("tone").flatMap(GameTone.init(rawValue:)) {
            out.append(String(localized: "When it wins: \(tone.name)", comment: "games.settings: how the companion takes a win, then the choice"))
        }
        if let on = input["sneaky"]?.boolValue {
            out.append(on ? String(localized: "Sneaky on", comment: "games.settings: the companion may cheat for fun")
                : String(localized: "Sneaky off", comment: "games.settings: the companion plays fair"))
        }
        if let game, let level = input.string("level") {
            out.append(level == "default"
                ? String(localized: "\(game.title): the game picks its level", comment: "games.settings: a game's level back to its own")
                : String(localized: "\(game.title) on \(GameLevels.name(level))", comment: "games.settings: a game's level, “Sudoku on Hard”"))
        }
        return out
    }
}

extension GameTone {
    /// Its name in the person's language, as Settings shows it.
    public var name: String {
        switch self {
        case .gentle: String(localized: "tone.gentle", defaultValue: "Gentle", comment: "How the companion takes a win in games: kindly")
        case .cheeky: String(localized: "tone.cheeky", defaultValue: "Cheeky", comment: "How the companion takes a win in games: a small tease, then kind")
        case .competitive: String(localized: "tone.competitive", defaultValue: "Competitive", comment: "How the companion takes a win in games: a victory dance")
        }
    }
}
