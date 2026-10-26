import Foundation
import Synchronization

/// How present the companion is on the desktop.
public enum PresenceMode: String, Codable, Sendable, CaseIterable {
    /// Always on the desktop.
    case always
    /// Tucked away (a small peek) until something needs you.
    case whenNeeded
    /// Only the menu bar icon; attention uses system notifications.
    case menuBarOnly
}

public enum CompanionSize: String, Codable, Sendable, CaseIterable {
    case small, medium, large
    public var points: Double {
        switch self {
        case .small: 56
        case .medium: 76
        case .large: 100
        }
    }
}

/// Who lives on the desktop: Mochi (the default, D29), the original robot, Spark, or one of the
/// Folk Family (D30). The app offers the ones whose rigs are finished.
public enum CompanionChoice: String, Codable, Sendable, CaseIterable {
    case mochi, sidefolk, spark
    case pip, byte, seed, melody, scout, tempo, play, guard_ = "guard", nova, brew

    /// The name it goes by until the user gives it another.
    public var defaultName: String {
        switch self {
        case .guard_: "Guard"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// How it comes dressed: Mochi in its scarf, the others in nothing, aqua accents for all.
    public var standardStyle: CompanionStyle {
        CompanionStyle(color: .aqua, accessory: self == .mochi ? .scarf : .none)
    }
}

/// A brand colour (D29 palette) for a companion's accents: the robot's light, Spark's headphones,
/// and whatever it wears.
public enum CompanionAccent: String, Codable, Sendable, CaseIterable {
    case aqua, coral, mint, lightBlue
}

/// Something any companion can wear (D30).
public enum CompanionAccessory: String, Codable, Sendable, CaseIterable {
    case none, scarf
}

/// The same small set of choices for every companion.
public struct CompanionStyle: Codable, Sendable, Equatable {
    public var color: CompanionAccent
    public var accessory: CompanionAccessory

    public init(color: CompanionAccent, accessory: CompanionAccessory) {
        self.color = color
        self.accessory = accessory
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = (try? c.decode(CompanionAccent.self, forKey: .color)) ?? .aqua
        accessory = (try? c.decode(CompanionAccessory.self, forKey: .accessory)) ?? .none
    }
}

public enum ProviderKind: String, Codable, Sendable, CaseIterable {
    case none
    case claudeCode
    case anthropic
    case openAICompatible

    public var displayName: String {
        switch self {
        case .none: "No AI"
        case .claudeCode: "Claude Code (your Claude subscription)"
        case .anthropic: "Anthropic API"
        case .openAICompatible: "OpenAI-compatible (OpenAI, Ollama, LM Studio, OpenRouter)"
        }
    }
}

public struct ProviderSettings: Codable, Sendable, Equatable {
    public var kind: ProviderKind = .none
    /// Main model ("sonnet", "claude-sonnet-4-5", "gpt-4o-mini", "llama3.1").
    public var model: String = ""
    /// Used by "Think harder"; empty means the main model.
    public var smartModel: String = ""
    /// For OpenAI-compatible endpoints.
    public var baseURL: String = ""
    /// Path to the `claude` executable when it is not found automatically.
    public var claudePath: String = ""
    public init() {}
}

/// Everything the user can change. Stored as one JSON document; every field has a default so
/// older or newer stored versions decode safely.
public struct AppSettings: Codable, Sendable, Equatable {
    public var companionName = "Mochi"
    /// Change it with `choose(_:)`, which keeps the name in step.
    public var companion: CompanionChoice = .mochi
    /// Each companion keeps its own colour and accessory, so switching back finds it as it was.
    /// Keyed by `CompanionChoice.rawValue`; read them with `style(for:)`.
    public var styles: [String: CompanionStyle] = [:]
    public var presence: PresenceMode = .always
    public var size: CompanionSize = .medium
    public var eyesFollowPointer = true
    public var sleepWhenIdle = true
    public var showFolks = true
    public var sounds = true
    /// Quiet mode end; nil when off.
    public var quietUntil: Date?
    /// Hour (0-23) "morning" means for "tomorrow morning" and the morning brief.
    public var morningHour = 9
    public var afternoonHour = 14
    public var eveningHour = 18
    public var morningBrief = true
    public var useSystemNotificationsWhenHidden = true
    public var provider = ProviderSettings()
    /// Short-term conversation history is kept this many days.
    public var historyDays = 7
    public var activityDays = 90
    public var debugLogging = false
    public var onboardingDone = false

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ into: inout T) { if let v = try? c.decode(T.self, forKey: key) { into = v } }
        read(.companionName, &companionName)
        read(.companion, &companion)
        read(.styles, &styles)
        // Before D30 the robot's light colour was the only style ("accent"); keep it.
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        if styles[CompanionChoice.sidefolk.rawValue] == nil, let accent = try? legacy.decode(CompanionAccent.self, forKey: .accent) {
            styles[CompanionChoice.sidefolk.rawValue] = CompanionStyle(color: accent, accessory: .none)
        }
        read(.presence, &presence)
        read(.size, &size)
        read(.eyesFollowPointer, &eyesFollowPointer)
        read(.sleepWhenIdle, &sleepWhenIdle)
        read(.showFolks, &showFolks)
        read(.sounds, &sounds)
        quietUntil = try? c.decodeIfPresent(Date.self, forKey: .quietUntil)
        read(.morningHour, &morningHour)
        read(.afternoonHour, &afternoonHour)
        read(.eveningHour, &eveningHour)
        read(.morningBrief, &morningBrief)
        read(.useSystemNotificationsWhenHidden, &useSystemNotificationsWhenHidden)
        read(.provider, &provider)
        read(.historyDays, &historyDays)
        read(.activityDays, &activityDays)
        read(.debugLogging, &debugLogging)
        read(.onboardingDone, &onboardingDone)
    }

    public func isQuiet(at now: Date) -> Bool { (quietUntil ?? .distantPast) > now }

    /// Switches companion. A name that is still one of the built-in defaults follows the new
    /// companion ("Sidefolk" becomes "Mochi"); a name the user chose stays.
    public mutating func choose(_ next: CompanionChoice) {
        if !hasCustomName { companionName = next.defaultName }
        companion = next
    }

    private enum LegacyKeys: String, CodingKey { case accent }

    /// How `companion` is dressed: what the user chose for it, or how it comes.
    public func style(for companion: CompanionChoice) -> CompanionStyle {
        styles[companion.rawValue] ?? companion.standardStyle
    }

    public mutating func setStyle(_ style: CompanionStyle, for companion: CompanionChoice) {
        styles[companion.rawValue] = style
    }

    /// Whether the user named the companion themselves (anything but a built-in default).
    public var hasCustomName: Bool {
        let name = companionName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !name.isEmpty && !CompanionChoice.allCases.contains { $0.defaultName.lowercased() == name }
    }
}

/// Loads, caches and saves `AppSettings`; publishes `.dataChanged(.settings)`.
public final class SettingsStore: Sendable {
    private let kv: KVStore
    private let events: EventBus
    private let cache: Mutex<AppSettings>

    public init(db: AppDatabase, events: EventBus) async {
        kv = KVStore(db)
        self.events = events
        let loaded = (try? await KVStore(db).get("settings", as: AppSettings.self)) ?? AppSettings()
        cache = Mutex(loaded)
    }

    public var current: AppSettings { cache.withLock { $0 } }

    public func update(_ change: @Sendable (inout AppSettings) -> Void) async {
        let next = cache.withLock { s -> AppSettings in
            change(&s)
            return s
        }
        try? await kv.set("settings", next)
        events.changed(.settings)
    }
}
