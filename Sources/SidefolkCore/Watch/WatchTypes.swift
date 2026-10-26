import Foundation

/// What one check of a watcher found.
public struct ProbeResult: Sendable, Equatable {
    /// The probe's memory for the next check; stored as the watcher's `last_state`.
    public var state: JSONValue
    public var triggered: Bool
    /// One line that becomes the notice title ("example.com/pricing changed").
    public var summary: String
    /// A short before → after snippet or other context for the notice body.
    public var detail: String?
    /// What "Open" should show: a web address or an absolute path.
    public var openTarget: String?
    /// Overrides the watcher's level for this notice (a gentle "that isn't running" note).
    public var level: AttentionLevel?
    /// Ask the engine to look again before the interval is up, e.g. to see if a download has settled.
    public var recheckIn: TimeInterval?
    /// Set by a probe's very first look when something is off but not wrong enough to fail ("it isn't answering",
    /// "that program isn't running"). Only the card that confirms the new watcher shows it.
    public var firstLookNote: String?

    public init(state: JSONValue, triggered: Bool = false, summary: String = "", detail: String? = nil,
                openTarget: String? = nil, level: AttentionLevel? = nil, recheckIn: TimeInterval? = nil, firstLookNote: String? = nil) {
        self.state = state
        self.triggered = triggered
        self.summary = summary
        self.detail = detail
        self.openTarget = openTarget
        self.level = level
        self.recheckIn = recheckIn
        self.firstLookNote = firstLookNote
    }
}

/// Something the system can tell us about, so a check can happen the moment it changes.
public enum WatchEventTarget: Sendable, Hashable {
    /// Entries added, removed or renamed inside a folder.
    case directory(String)
    /// Contents or metadata of one file.
    case file(String)
    /// A process exiting.
    case process(Int32)
}

/// One kind of watcher. Extensions can contribute more through `WatcherEngine.register`.
public protocol WatcherProbe: Sendable {
    /// The `watchers.kind` value this probe handles.
    var kind: String { get }
    /// Seconds between checks when the user did not say.
    var defaultInterval: TimeInterval { get }
    /// The shortest interval allowed; shorter requests are raised to it.
    var minimumInterval: TimeInterval { get }
    /// Quiet time after a repeat watcher fires before it looks again.
    var repeatCooldown: TimeInterval { get }

    /// Validates a new watcher and returns it normalised (defaults filled, paths canonical).
    /// Throws `WatchError.invalid` with a message written for people.
    func prepare(_ watcher: Watcher) throws -> Watcher
    /// Looks once. Throws `ProbeError` for failures the engine should back off from.
    func check(_ watcher: Watcher, now: Date) async throws -> ProbeResult
    /// Things that should trigger an early check, derived from the config and the last state.
    func eventTargets(for watcher: Watcher) -> [WatchEventTarget]
}

public extension WatcherProbe {
    var defaultInterval: TimeInterval { 300 }
    var minimumInterval: TimeInterval { 60 }
    var repeatCooldown: TimeInterval { WatchLimits.defaultCooldown }
    func prepare(_ watcher: Watcher) throws -> Watcher { watcher }
    func eventTargets(for watcher: Watcher) -> [WatchEventTarget] { [] }
}

/// A watcher that cannot be created or changed. The message is written for the user, in the app's language.
public enum WatchError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalid(String)
    case unknownKind(String)
    case limit(String)
    case notFound(String)
    case notAllowed(String)

    public var description: String {
        switch self {
        case .invalid(let m), .limit(let m), .notAllowed(let m): m
        case .unknownKind(let k): String(localized: "I don't know how to watch “\(k)”.")
        case .notFound(let m): String(localized: "I couldn't find \(m).")
        }
    }
}

/// Why a check did not produce a result.
public enum ProbeError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The check failed; the message says why. Counts toward backoff.
    case failed(String)
    /// Not now (another request to the same host went out a moment ago). Does not count as a failure.
    case deferred(until: Date)
    /// The Mac has no network. Does not count as a failure, and nothing is shown.
    case offline

    public var description: String {
        switch self {
        case .failed(let m): m
        case .deferred: String(localized: "Waiting a moment before asking that site again.")
        case .offline: String(localized: "No internet connection.")
        }
    }
}

/// The numbers that keep watchers calm (docs/SECURITY.md T24).
public enum WatchLimits {
    public static let maxActive = 50
    public static let maxActivePerExternalClient = 10
    /// Every external agent together (T4): a new client name doesn't buy new room.
    public static let maxActiveExternal = 10
    public static let maxActiveCommands = 5
    public static let onceExpiry: TimeInterval = 7 * 86400
    public static let repeatExpiry: TimeInterval = 30 * 86400
    /// External agents' watchers stop after a day, however they were set up (T4).
    public static let externalExpiry: TimeInterval = 86400
    public static let defaultCooldown: TimeInterval = 30 * 60
    public static let maxBackoff: TimeInterval = 6 * 3600
    public static let maxInterval: TimeInterval = 7 * 86400
    /// Consecutive failures before the user hears about it.
    public static let failuresBeforeNotice = 3
    /// Notice titles and snippets are kept short (T17).
    public static let summaryLimit = 200
}

/// The built-in watcher kinds.
public enum WatchKind {
    public static let urlChange = "url_change"
    public static let siteStatus = "site_status"
    public static let fileAppears = "file_appears"
    public static let fileChanges = "file_changes"
    public static let folderNewFile = "folder_new_file"
    public static let processExits = "process_exits"
    public static let command = "command"

    /// Kinds the `watch.create` tool offers (the command kind has its own tool).
    public static let creatable = [urlChange, siteStatus, fileAppears, fileChanges, folderNewFile, processExits]
}

/// Who made a watcher, recorded in `watchers.source`. It decides what the watcher may do.
public enum WatchSource {
    /// What a new watcher records: `ToolContext.provenanceTag` (Sidefolk's agent in a clean turn acts for
    /// the user, "user:agent"; in a tainted turn it is plain "agent"). A routine keeps its id, so it can
    /// manage its own watchers later (`canManage`).
    public static func string(for context: ToolContext) -> String {
        if case .routine = context.caller { return string(for: context.caller) }
        return context.provenanceTag
    }

    /// Who a caller is when it manages watchers.
    public static func string(for caller: Caller) -> String {
        switch caller {
        case .user: "user"
        case .agent: "agent"
        case .routine(let id): "routine:\(id)"
        case .external(let client): "external:\(client)"
        case .extension(let id): "extension:\(id)"
        }
    }

    /// Only the user, never an agent, may point a watcher at their own Mac or network (D21, SECURITY T11).
    /// Not even "user:agent": a clean turn still builds the address itself, and only a request the user
    /// typed or a button they pressed may reach local addresses.
    public static func mayTargetLocal(_ source: String) -> Bool { source == "user" }
    /// Commands are created by the user, or by Sidefolk's own agent in a clean turn after a high-risk
    /// approval ("user:agent"). A command from a tainted turn ("agent") may have been dictated by a page.
    public static func mayRunCommands(_ source: String) -> Bool { source == "user" || source == "user:agent" }
    /// Whether a watcher's title is the user's own words and may be quoted to the model. Anyone else's
    /// (another agent, an extension, a routine, a tainted turn) is counted or marked untrusted (T3).
    public static func isUserSourced(_ source: String) -> Bool { ContextBuilder.isUserSourced(source) }
    public static func isExternal(_ source: String) -> Bool { source.hasPrefix("external:") }
    /// Whether `caller` may change a watcher made by `source`: external agents and extensions only touch their own.
    public static func canManage(caller: Caller, watcherSource source: String) -> Bool {
        switch caller {
        case .user, .agent: true
        case .routine, .external, .extension: string(for: caller) == source
        }
    }
}

/// Test and "check now" hook: a check the user asked for right now skips polite delays.
public enum WatchContext {
    @TaskLocal public static var isManualCheck = false
}

// MARK: Small helpers shared by the probes

extension JSONValue {
    /// A copy of an object with `key` set (or removed when `value` is nil).
    func setting(_ key: String, _ value: JSONValue?) -> JSONValue {
        var o = objectValue ?? [:]
        o[key] = value
        return .object(o)
    }
}

extension Watcher {
    /// Whether this watcher may reach local addresses: the user chose it, and only the user can.
    var allowsLocal: Bool { config["allow_local"]?.boolValue == true && WatchSource.mayTargetLocal(source) }
}

extension String {
    /// Text that came from outside (a web page, a file name, command output) made safe to show:
    /// invisible and bidirectional control characters removed, whitespace collapsed (docs/SECURITY.md T2).
    var displaySafe: String {
        var out = String.UnicodeScalarView()
        for u in unicodeScalars {
            switch u.value {
            case 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2069, 0xFEFF, 0xE0000...0xE007F: continue
            case 0x00...0x08, 0x0B...0x0C, 0x0E...0x1F, 0x7F: continue
            case 0x09, 0x0A, 0x0D, 0xA0: out.append(" ")
            default: out.append(u)
            }
        }
        return String(out).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}
