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

    public init() {}

    /// Whether a game's sounds play: its own button, or the setting for all.
    public func soundsOn(_ game: String) -> Bool { speakers[game] ?? sounds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ into: inout T) { if let v = try? c.decode(T.self, forKey: key) { into = v } }
        read(.tone, &tone)
        read(.sounds, &sounds)
        read(.speakers, &speakers)
        read(.sneaky, &sneaky)
    }
}
