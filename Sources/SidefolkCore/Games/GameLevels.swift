import Foundation

/// A game's levels as Sidefolk speaks of them (D93): their names in the person's language, the one a game opens at,
/// and one step harder or easier. A game's `levels` are its own words in its manifest (Playtime's are easy, fair and
/// hard); Sidefolk names the three it knows and shows any other as written.
public enum GameLevels {
    /// One step harder or easier than the level a game last opened at.
    public enum Step: String, Sendable, Hashable { case harder, easier }

    /// "Easy", "Fair", "Hard" in the person's language; another level as its manifest wrote it.
    public static func name(_ level: String) -> String {
        switch level {
        case "easy": String(localized: "level.easy", defaultValue: "Easy", comment: "A game's level")
        case "fair": String(localized: "level.fair", defaultValue: "Fair", comment: "A game's level: the middle one")
        case "hard": String(localized: "level.hard", defaultValue: "Hard", comment: "A game's level")
        default: level.prefix(1).uppercased() + level.dropFirst()
        }
    }

    /// The level a person's word means for this game: its own name when it has it, else the same place in its list
    /// (easy the first, hard the last, fair the middle); nil for a game without levels.
    public static func match(_ word: String, in levels: [String]) -> String? {
        guard !levels.isEmpty else { return nil }
        if levels.contains(word) { return word }
        switch word {
        case "easy": return levels.first
        case "hard": return levels.last
        case "fair": return levels[levels.count / 2]
        default: return nil
        }
    }

    /// The level one step from `current` (the middle one when unknown), or nil past either end.
    public static func step(_ step: Step, from current: String?, in levels: [String]) -> String? {
        guard !levels.isEmpty else { return nil }
        let at = current.flatMap { levels.firstIndex(of: $0) } ?? levels.count / 2
        let next = at + (step == .harder ? 1 : -1)
        return levels.indices.contains(next) ? levels[next] : nil
    }
}
