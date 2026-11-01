import Foundation

/// How games in the Play panel behave (D75). Calm by default: no sounds until the person turns a game's speaker on,
/// and the companion never cheats unless Sneaky is on.
public struct GameSettings: Codable, Sendable, Equatable {
    /// How the companion takes a win.
    public var tone: GameTone = .cheeky
    /// Sounds in every game until its own speaker button says otherwise.
    public var sounds = false
    /// Each game's speaker button, by `extension/game`, when the person pressed it.
    public var speakers: [String: Bool] = [:]
    /// The companion may cheat for fun in games that offer it (Which Cup? palms the gem), always confessing when caught.
    public var sneaky = false
    /// The names two people last played each other under on this Mac (D96), first and second: passed to every game as
    /// `options.names`, and remembered from what a two-player game's score shows. Empty until they play.
    public var players: [String] = []
    /// Trivia may ask the person's AI for fresh questions on any topic (D95); nil follows whether a provider is set up.
    public var aiTrivia: Bool?

    public init() {}

    /// Whether trivia makes new questions with AI now: the person's choice, or on while they have a provider.
    public func aiTriviaOn(providerSet: Bool) -> Bool { providerSet && (aiTrivia ?? true) }

    /// Whether a game's sounds play: its own button, or the setting for all.
    public func soundsOn(_ game: String) -> Bool { speakers[game] ?? sounds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ into: inout T) { if let v = try? c.decode(T.self, forKey: key) { into = v } }
        read(.tone, &tone)
        read(.sounds, &sounds)
        read(.speakers, &speakers)
        read(.sneaky, &sneaky)
        read(.players, &players)
        read(.aiTrivia, &aiTrivia)
    }
}
