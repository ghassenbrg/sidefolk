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

public enum ProviderKind: String, Codable, Sendable, CaseIterable {
    case none
    case claudeCode
    case codex
    case anthropic
    /// OpenAI's chat completions API, spoken by many services: which one is `ProviderSettings.preset`.
    case openAICompatible

    public var displayName: String {
        switch self {
        case .none: "No AI"
        case .claudeCode: "Claude Code (your Claude subscription)"
        case .codex: "Codex (your ChatGPT plan)"
        case .anthropic: "Anthropic API"
        case .openAICompatible: "OpenAI-compatible"
        }
    }
}

public struct ProviderSettings: Codable, Sendable, Equatable {
    public var kind: ProviderKind = .none
    /// Main model ("sonnet", "claude-sonnet-4-5", "gpt-5-mini", "llama3.1"); empty lets a CLI use its default.
    public var model: String = ""
    /// Used by "Think harder"; empty means the main model.
    public var smartModel: String = ""
    /// Which OpenAI-compatible service (D26). Settings saved before presets existed get the preset their address matches.
    public var preset: ProviderPreset = .custom
    /// For a custom OpenAI-compatible endpoint; presets have fixed addresses.
    public var baseURL: String = ""
    /// Path to the `claude` executable when it is not found automatically.
    public var claudePath: String = ""
    /// Path to the `codex` executable when it is not found automatically.
    public var codexPath: String = ""
    public init() {}

    enum CodingKeys: String, CodingKey {
        case kind, model, smartModel, preset, baseURL, claudePath, codexPath
    }

    /// Every field has a default, so settings written by an older or newer Sidefolk still load (a
    /// synthesized decoder would throw over one missing key, and the whole provider would be lost).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ into: inout T) { if let v = try? c.decode(T.self, forKey: key) { into = v } }
        read(.kind, &kind)
        read(.model, &model)
        read(.smartModel, &smartModel)
        read(.baseURL, &baseURL)
        read(.claudePath, &claudePath)
        read(.codexPath, &codexPath)
        preset = (try? c.decode(ProviderPreset.self, forKey: .preset)) ?? ProviderPreset.matching(baseURL: baseURL)
    }
}

/// Everything the user can change. Stored as one JSON document; every field has a default so
/// older or newer stored versions decode safely.
public struct AppSettings: Codable, Sendable, Equatable {
    public var companionName = "Sidefolk"
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
