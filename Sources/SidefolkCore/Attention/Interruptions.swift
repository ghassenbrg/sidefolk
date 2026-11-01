import Foundation

/// How far one source may interrupt (D88): its ceiling, from most to least. A card may step forward and stay; a whisper
/// comes gently and, if it needs an answer, folds into the stack; Only in Today keeps it off the desktop and in Today's
/// lists; Off keeps it in History only.
public enum InterruptLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case off, today, whisper, card

    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }

    /// One step quieter, for the Sidecard's "Fewer like this"; nil from Off.
    public var quieter: InterruptLevel? { rank > 0 ? Self.allCases[rank - 1] : nil }
}

/// Who a notice is from, as Settings › Attention lists them (D88). Stored by `key`.
public enum InterruptSource: Hashable, Sendable {
    case reminders
    case watches
    /// One watch, set apart from the rest.
    case watch(String)
    /// `sidefolk run` commands ending.
    case commands
    /// Another agent by its client name: "claude-code", "codex", "cursor"…
    case agent(String)
    /// An extension whose watches report to the person.
    case `extension`(String)
    /// The lines the companion says during a game.
    case games
    /// What the companion says on its own: its AI's notices and routines, folk introductions, "All clear".
    case companion
    /// Add-on updates waiting (D89): the whisper after a day and an update to look at.
    case addonUpdates

    public var key: String {
        switch self {
        case .reminders: "reminders"
        case .watches: "watches"
        case .watch(let id): "watch:\(id)"
        case .commands: "commands"
        case .agent(let name): "agent:\(name)"
        case .extension(let id): "extension:\(id)"
        case .games: "games"
        case .companion: "companion"
        case .addonUpdates: "addons"
        }
    }

    public init?(key: String) {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first ?? "", parts.count == 2 ? parts[1] : nil) {
        case ("reminders", nil): self = .reminders
        case ("watches", nil): self = .watches
        case ("watch", let id?): self = .watch(id)
        case ("commands", nil): self = .commands
        case ("agent", let name?): self = .agent(name)
        case ("extension", let id?): self = .extension(id)
        case ("games", nil): self = .games
        case ("companion", nil): self = .companion
        case ("addons", nil): self = .addonUpdates
        default: return nil
        }
    }

    /// What the table offers. A reminder is the person's own: it may come quieter, never not at all. The game's
    /// lines are a caption beside the game, so they are on or off.
    public var choices: [InterruptLevel] {
        switch self {
        case .reminders: [.card, .whisper, .today]
        case .games: [.whisper, .off]
        default: [.card, .whisper, .today, .off]
        }
    }

    /// Today's behaviour (D88): each notice at its own level; the game's lines as they were; add-on updates gently (D89).
    public var defaultLevel: InterruptLevel { self == .games || self == .addonUpdates ? .whisper : .card }

    /// "Claude Code" and "claude" are one agent, as are Codex's client names; others by their lowercased name.
    public static func agentName(_ client: String) -> String {
        let name = client.trimmingCharacters(in: .whitespaces).lowercased()
        switch name {
        case "claude-code", "claude code", "claude": return "claude-code"
        case "codex", "codex-mcp-client", "codex_cli": return "codex"
        default: return String(name.prefix(40))
        }
    }

    /// The sources a notice counts against, the most specific first, from what the attention center stores: a watch,
    /// then the extension behind it, then all watches; an agent by name; the companion's own.
    public static func of(source: String, refKind: String?, refId: String?) -> [InterruptSource] {
        let parts = source.split(separator: ":", maxSplits: 1).map(String.init)
        let rest = parts.count == 2 ? parts[1] : nil
        let watch: [InterruptSource] = refKind == "watcher" ? refId.map { [.watch($0)] } ?? [] : []
        switch (parts.first ?? "", rest) {
        case ("reminder", nil): return [.reminders]
        case ("watcher", nil): return watch + [.watches]
        case ("job", nil): return [.commands]
        case ("external", let client?): return [.agent(agentName(client))]
        // "session:<agent>:<id>"; a session from before D88 ("session:<id>") names no agent.
        case ("session", let rest?):
            let session = rest.split(separator: ":", maxSplits: 1).map(String.init)
            return session.count == 2 ? [.agent(agentName(session[0]))] : []
        // An extension's watch counts as that watch, the extension, then watches.
        case ("extension", let id?): return refKind == "watcher" ? watch + [.extension(id), .watches] : [.extension(id)]
        case ("agent", nil), ("routine", _), ("companion", nil): return [.companion]
        case ("addons", nil): return [.addonUpdates]
        default: return []
        }
    }
}

/// The person's ceilings per source (D88), in `AppSettings.interruptions`. What isn't set is the source's default,
/// which is today's behaviour; a value a newer Sidefolk wrote that this one doesn't know is skipped.
public struct Interruptions: Codable, Sendable, Equatable {
    public private(set) var levels: [String: InterruptLevel] = [:]

    public init(_ levels: [InterruptSource: InterruptLevel] = [:]) {
        for (source, level) in levels { set(level, for: source) }
    }

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode([String: String].self)) ?? [:]
        levels = raw.compactMapValues(InterruptLevel.init(rawValue:)).filter { InterruptSource(key: $0.key) != nil }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(levels.mapValues(\.rawValue))
    }

    /// The level the person chose, or the default.
    public func level(for source: InterruptSource) -> InterruptLevel {
        explicit(source) ?? source.defaultLevel
    }

    /// Only what the person chose.
    public func explicit(_ source: InterruptSource) -> InterruptLevel? { levels[source.key] }

    /// Sets a level; the default (or nil) clears it, so a later change of default reaches everyone who never chose. A
    /// watch set apart has no default of its own (it would be the other watches' level): only nil clears it. A choice
    /// the source doesn't offer is ignored.
    public mutating func set(_ level: InterruptLevel?, for source: InterruptSource) {
        let setApart = if case .watch = source { true } else { false }
        guard let level, setApart || level != source.defaultLevel else { levels[source.key] = nil; return }
        guard source.choices.contains(level) else { return }
        levels[source.key] = level
    }

    /// The watches set apart from the rest, by watch id.
    public var watchOverrides: [String: InterruptLevel] {
        Dictionary(uniqueKeysWithValues: levels.compactMap { key, level in
            if case .watch(let id)? = InterruptSource(key: key) { return (id, level) }
            return nil
        })
    }

    /// Agents and extensions the person set a level for, so the table lists them even when they're quiet now.
    public var named: [InterruptSource] { levels.keys.compactMap(InterruptSource.init(key:)) }

    /// The ceiling for a notice from these sources: the most specific one the person set, else the first's default.
    public func ceiling(for sources: [InterruptSource]) -> InterruptLevel {
        sources.lazy.compactMap(explicit).first ?? sources.first?.defaultLevel ?? .card
    }

    /// What may never be turned down: a question that waits for an answer, and an agent session that needs the person
    /// (an approval in its own window). Approvals inside Sidefolk never go through the attention center at all.
    public static func mustReach(level: AttentionLevel, refKind: String?) -> Bool {
        refKind == "ask" || (refKind == "session" && level >= .attention)
    }

    public enum Route: Sendable, Equatable {
        /// Through the attention rules (Focus, Quiet, the limits) at this level.
        case deliver(AttentionLevel)
        /// Kept off the desktop, in Today.
        case today
        /// Kept in History only.
        case off
    }

    /// The lower of the notice's own level and its source's ceiling (D88); Focus and Quiet apply after.
    public func route(level: AttentionLevel, source: String, refKind: String?, refId: String?) -> Route {
        if Self.mustReach(level: level, refKind: refKind) { return .deliver(level) }
        switch ceiling(for: InterruptSource.of(source: source, refKind: refKind, refId: refId)) {
        case .card: return .deliver(level)
        case .whisper: return .deliver(min(level, .gentle))
        case .today: return .today
        case .off: return .off
        }
    }

    public func route(_ item: AttentionItem) -> Route {
        route(level: item.level, source: item.source, refKind: item.refKind, refId: item.refId)
    }
}
