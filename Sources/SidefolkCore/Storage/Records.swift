import Foundation
import GRDB

/// Shared column and date conventions for every table (snake_case columns, UTC seconds).
public protocol SidefolkRecord: Codable, FetchableRecord, PersistableRecord, Sendable {}

extension SidefolkRecord {
    public static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    public static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    // GRDB 7 asks per column; properties with these names would be ignored and dates stored as text.
    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy { .timeIntervalSince1970 }
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy { .timeIntervalSince1970 }
}

/// How strongly something may claim the user's attention.
public enum AttentionLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case ambient, gentle, attention, critical

    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

// MARK: Notebook

public struct NotebookCollection: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "collections"
    /// `profile` is "About you": facts and preferences Sidefolk keeps in mind in every conversation.
    public enum Kind: String, Codable, Sendable, CaseIterable { case inbox, profile, project, topic, list }

    public var id: String
    public var name: String
    public var kind: Kind
    /// The person's own touch (D53): an emoji, or else an SF Symbol name, and a colour from the app's palette by
    /// name ("blue"). Unset, the kind decides.
    public var emoji: String?
    public var symbol: String?
    public var color: String?
    /// Who named it, as for items (`user | user:agent | agent | …`): a name is quoted to the model only
    /// when it is the user's own (SECURITY T3).
    public var source: String
    public var createdAt: Date
    public var updatedAt: Date
    public var archivedAt: Date?

    public init(id: String = Identifier.make(), name: String, kind: Kind, emoji: String? = nil, source: String = "user",
                now: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.emoji = emoji
        self.source = source
        createdAt = now
        updatedAt = now
    }
}

public struct NotebookItem: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "items"
    public enum Kind: String, Codable, Sendable, CaseIterable { case note, idea, task, link }
    public enum Status: String, Codable, Sendable { case open, done }

    public var id: String
    public var collectionId: String
    public var kind: Kind
    public var title: String
    public var body: String
    public var url: String?
    public var tags: String
    public var status: Status
    public var dueAt: Date?
    public var source: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    /// Pinned items come first in their collection, newest pin first.
    public var pinnedAt: Date?
    /// The AI run that saved it, when Sidefolk's own agent did: the way back to the conversation it came from.
    public var runId: String?

    public init(
        id: String = Identifier.make(), collectionId: String, kind: Kind, title: String, body: String = "",
        url: String? = nil, tags: [String] = [], source: String, runId: String? = nil, now: Date = Date()
    ) {
        self.id = id
        self.collectionId = collectionId
        self.kind = kind
        self.title = title
        self.body = body
        self.url = url
        self.tags = tags.joined(separator: " ")
        status = .open
        self.source = source
        self.runId = runId
        createdAt = now
        updatedAt = now
    }

    public var tagList: [String] { tags.split(separator: " ").map(String.init) }
}

/// A Claude Code or Codex session Sidefolk is keeping an eye on (reported by hooks or the session itself).
public struct AgentSession: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "sessions"
    public enum State: String, Codable, Sendable { case working, needsYou = "needs_you", idle, finished }

    public var id: String
    public var agent: String
    public var cwd: String?
    public var title: String?
    public var state: State
    public var detail: String?
    public var hostApp: String?
    public var hostPid: Int?
    public var tty: String?
    public var startedAt: Date
    public var updatedAt: Date
    public var endedAt: Date?

    public init(id: String, agent: String, cwd: String?, state: State, now: Date = Date()) {
        self.id = id
        self.agent = agent
        self.cwd = cwd
        self.state = state
        startedAt = now
        updatedAt = now
    }

    /// "sidefolk" from "/Users/me/git/sidefolk".
    public var projectName: String? { cwd.map { URL(fileURLWithPath: $0).lastPathComponent } }
}

/// A command started with `sidefolk run`, or another background job Sidefolk follows to the end.
public struct Job: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "jobs"
    public enum Kind: String, Codable, Sendable { case command }
    public enum State: String, Codable, Sendable { case running, succeeded, failed, cancelled }

    public var id: String
    public var kind: Kind
    public var title: String
    public var command: String?
    public var cwd: String?
    public var pid: Int?
    public var state: State
    public var exitCode: Int?
    public var outputTail: String?
    public var level: AttentionLevel
    public var source: String
    public var startedAt: Date
    public var endedAt: Date?

    public init(id: String = Identifier.make(), kind: Kind, title: String, command: String?, cwd: String?, pid: Int?,
                level: AttentionLevel = .attention, source: String, now: Date = Date()) {
        self.id = id
        self.kind = kind
        self.title = title
        self.command = command
        self.cwd = cwd
        self.pid = pid
        state = .running
        self.level = level
        self.source = source
        startedAt = now
    }
}

// MARK: Time

public struct Recurrence: Codable, Sendable, Hashable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case minutely, hourly, daily, weekdays, weekly, monthly, yearly

        /// Counted in elapsed time, not on the wall clock: "every 30 minutes" stays 30 real minutes apart across
        /// daylight saving and time zone moves, and has no time of day of its own.
        public var isElapsed: Bool { self == .minutely || self == .hourly }
    }
    public var frequency: Frequency
    /// Every N units (1 = every minute/hour/day/...). Minutes are the finest step: a reminder never repeats
    /// more often than once a minute (a value that must come faster is a report, not a reminder).
    public var interval: Int
    /// For weekly: ISO weekdays 1 = Monday ... 7 = Sunday. Empty means the weekday of the first fire.
    public var weekdays: [Int]
    public var until: Date?

    /// "every 1000 years" is the longest repeat: past it the date arithmetic overflows and traps, so a
    /// reminder an agent made with a giant interval would crash Sidefolk at every launch.
    public static let maxInterval = 1000

    public init(frequency: Frequency, interval: Int = 1, weekdays: [Int] = [], until: Date? = nil) {
        self.frequency = frequency
        self.interval = min(max(1, interval), Self.maxInterval)
        self.weekdays = weekdays
        self.until = until
    }
}

/// What happens when a reminder fires: tell the user, or run a prompt through the agent (a routine).
public struct ReminderAction: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case notify, prompt }
    public var kind: Kind
    public var prompt: String?
    public init(kind: Kind, prompt: String? = nil) {
        self.kind = kind
        self.prompt = prompt
    }
}

public struct Reminder: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "reminders"
    public enum State: String, Codable, Sendable { case scheduled, fired, snoozed, done, cancelled }
    /// Why a reminder that belongs to a notebook item stopped with it (D49): its task was done, or the item went to
    /// the Trash. It comes back when the item does, if its time is still ahead.
    public enum EndedWithItem: String, Codable, Sendable { case done, trashed }

    public var id: String
    public var title: String
    public var notes: String?
    public var fireAt: Date
    public var timezone: String
    public var recurrence: Recurrence?
    public var state: State
    public var snoozedUntil: Date?
    public var lastFiredAt: Date?
    public var firedCount: Int
    public var level: AttentionLevel
    public var action: ReminderAction?
    /// The note or task this reminder belongs to (D49).
    public var itemId: String?
    public var endedWithItem: EndedWithItem?
    public var source: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = Identifier.make(), title: String, notes: String? = nil, fireAt: Date,
        timezone: String = TimeZone.current.identifier, recurrence: Recurrence? = nil,
        level: AttentionLevel = .attention, action: ReminderAction? = nil, source: String, now: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.fireAt = fireAt
        self.timezone = timezone
        self.recurrence = recurrence
        state = .scheduled
        firedCount = 0
        self.level = level
        self.action = action
        self.source = source
        createdAt = now
        updatedAt = now
    }

    /// When the reminder should next fire, if it is still pending.
    public var nextDue: Date? {
        switch state {
        case .scheduled: return fireAt
        case .snoozed: return snoozedUntil ?? fireAt
        case .fired, .done, .cancelled: return nil
        }
    }
}

public struct Watcher: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "watchers"
    public enum State: String, Codable, Sendable { case active, paused, triggered, expired, error }
    /// once: tell once, then stop. repeat: tell every time it happens. report: tell the current value every check (D35).
    public enum Mode: String, Codable, Sendable { case once, `repeat`, report }

    public var id: String
    public var kind: String
    public var title: String
    public var config: JSONValue
    public var condition: JSONValue
    public var intervalS: Double
    public var state: State
    public var mode: Mode
    public var level: AttentionLevel
    public var lastCheckedAt: Date?
    public var nextCheckAt: Date?
    public var lastState: JSONValue?
    public var lastError: String?
    public var errorCount: Int
    public var fireCount: Int
    public var expiresAt: Date?
    public var source: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = Identifier.make(), kind: String, title: String, config: JSONValue, condition: JSONValue = .object([:]),
        intervalS: Double, mode: Mode = .once, level: AttentionLevel = .attention, expiresAt: Date? = nil,
        source: String, now: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.config = config
        self.condition = condition
        self.intervalS = intervalS
        state = .active
        self.mode = mode
        self.level = level
        nextCheckAt = now
        errorCount = 0
        fireCount = 0
        self.expiresAt = expiresAt
        self.source = source
        createdAt = now
        updatedAt = now
    }
}

// MARK: Conversation, audit, permissions

public struct Exchange: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "exchanges"
    public enum Role: String, Codable, Sendable { case user, assistant, tool, event }

    public var id: String
    public var threadId: String
    public var role: Role
    public var content: String
    public var meta: JSONValue?
    public var createdAt: Date

    public init(id: String = Identifier.make(), threadId: String, role: Role, content: String, meta: JSONValue? = nil, now: Date = Date()) {
        self.id = id
        self.threadId = threadId
        self.role = role
        self.content = content
        self.meta = meta
        createdAt = now
    }
}

public struct ActivityEntry: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "activity"
    public enum Decision: String, Codable, Sendable {
        case auto, allowed, always, denied, blocked, failed
        /// Done without asking because the person chose Auto or Full access (D37).
        case autoMode = "auto_mode"
        case fullAccess = "full_access"
        /// Nobody answered in time; the step was skipped, or its task stopped (D37).
        case skipped
        /// Read a page or used a built-in service without asking because the person chose so for the internet (D47).
        case webSetting = "web_setting"
    }

    public var id: Int64?
    public var at: Date
    public var caller: String
    public var tool: String
    public var risk: String
    public var decision: Decision
    public var summary: String
    public var args: JSONValue?
    public var outcome: String?
    public var error: String?
    public var runId: String?

    public init(
        at: Date = Date(), caller: String, tool: String, risk: String, decision: Decision, summary: String,
        args: JSONValue? = nil, outcome: String? = nil, error: String? = nil, runId: String? = nil
    ) {
        self.at = at
        self.caller = caller
        self.tool = tool
        self.risk = risk
        self.decision = decision
        self.summary = summary
        self.args = args
        self.outcome = outcome
        self.error = error
        self.runId = runId
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct Grant: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "grants"
    public var id: String
    public var tool: String
    /// Optional narrowing: {"folder": "/path"} or {"command": "exact command"} or {"extension": "id"}.
    public var scope: JSONValue
    public var callerKind: String
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(id: String = Identifier.make(), tool: String, scope: JSONValue = .object([:]), callerKind: String, now: Date = Date()) {
        self.id = id
        self.tool = tool
        self.scope = scope
        self.callerKind = callerKind
        createdAt = now
    }
}

public struct GrantedFolder: SidefolkRecord, Hashable {
    public static let databaseTableName = "folders"
    public enum Access: String, Codable, Sendable { case read, readwrite }
    public var path: String
    public var access: Access
    public var createdAt: Date

    public init(path: String, access: Access, now: Date = Date()) {
        self.path = path
        self.access = access
        createdAt = now
    }
}

public struct ExtensionRecord: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "extensions"
    public enum Kind: String, Codable, Sendable { case sidefolk, mcp }
    public var id: String
    public var version: String
    public var path: String
    public var enabled: Bool
    public var kind: Kind
    public var granted: JSONValue?
    public var manifestHash: String?
    public var installedAt: Date
    public var lastError: String?

    public init(id: String, version: String, path: String, enabled: Bool, kind: Kind, granted: JSONValue? = nil,
                manifestHash: String? = nil, now: Date = Date()) {
        self.id = id
        self.version = version
        self.path = path
        self.enabled = enabled
        self.kind = kind
        self.granted = granted
        self.manifestHash = manifestHash
        installedAt = now
    }
}

public struct AgentRun: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "agent_runs"
    public var id: String
    public var threadId: String
    public var provider: String
    public var model: String
    public var startedAt: Date
    public var endedAt: Date?
    public var steps: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var outcome: String?
    public var error: String?

    public init(id: String = Identifier.make(), threadId: String, provider: String, model: String, now: Date = Date()) {
        self.id = id
        self.threadId = threadId
        self.provider = provider
        self.model = model
        startedAt = now
        steps = 0
        inputTokens = 0
        outputTokens = 0
    }
}

public struct AttentionAction: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var isPrimary: Bool
    public init(id: String, title: String, isPrimary: Bool = false) {
        self.id = id
        self.title = title
        self.isPrimary = isPrimary
    }
}

public struct AttentionItem: SidefolkRecord, Identifiable, Hashable {
    public static let databaseTableName = "attention"
    public enum State: String, Codable, Sendable { case pending, shown, acknowledged, expired }

    public var id: String
    public var level: AttentionLevel
    public var source: String
    public var title: String
    public var body: String?
    public var actions: [AttentionAction]
    public var refKind: String?
    public var refId: String?
    public var state: State
    public var createdAt: Date
    public var shownAt: Date?
    public var acknowledgedAt: Date?
    public var renudged: Bool

    public init(
        id: String = Identifier.make(), level: AttentionLevel, source: String, title: String, body: String? = nil,
        actions: [AttentionAction] = [], refKind: String? = nil, refId: String? = nil, now: Date = Date()
    ) {
        self.id = id
        self.level = level
        self.source = source
        self.title = title
        self.body = body
        self.actions = actions
        self.refKind = refKind
        self.refId = refId
        state = .pending
        createdAt = now
        renudged = false
    }
}

struct KeyValue: SidefolkRecord {
    static let databaseTableName = "kv"
    var key: String
    var value: JSONValue
}
