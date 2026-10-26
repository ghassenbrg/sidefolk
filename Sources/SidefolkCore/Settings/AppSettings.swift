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

/// Who lives on the desktop (DECISIONS D27): the vector robot, or one of the founder's two earlier
/// characters drawn as sprites.
public enum CompanionChoice: String, Codable, Sendable, CaseIterable {
    case sidefolk, mochi, spark

    /// The name it goes by until the user gives it another.
    public var defaultName: String {
        switch self {
        case .sidefolk: "Sidefolk"
        case .mochi: "Mochi"
        case .spark: "Spark"
        }
    }
}

/// The colour of the Sidefolk robot's light, from the brand palette. Sprite companions keep the
/// colours they were drawn with.
public enum CompanionAccent: String, Codable, Sendable, CaseIterable {
    case aqua, coral, mint, lightBlue
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
    public var companionName = "Sidefolk"
    /// Change it with `choose(_:)`, which keeps the name in step.
    public var companion: CompanionChoice = .sidefolk
    public var accent: CompanionAccent = .aqua
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
        read(.accent, &accent)
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
