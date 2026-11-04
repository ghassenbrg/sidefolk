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
    /// What a report read this time (`Watcher.Mode.report`): shown in place of a notice.
    public var reading: ReadingText?
    /// The text a page or file watch compared, on its first look and when it changed, so the watch keeps its last two
    /// versions (D87).
    public var compared: ComparedText?

    public init(state: JSONValue, triggered: Bool = false, summary: String = "", detail: String? = nil,
                openTarget: String? = nil, level: AttentionLevel? = nil, recheckIn: TimeInterval? = nil, firstLookNote: String? = nil,
                reading: ReadingText? = nil, compared: ComparedText? = nil) {
        self.state = state
        self.triggered = triggered
        self.summary = summary
        self.detail = detail
        self.openTarget = openTarget
        self.level = level
        self.recheckIn = recheckIn
        self.firstLookNote = firstLookNote
        self.reading = reading
        self.compared = compared
    }
}

/// What a page or file watch compared this time (D87): the text now and, when the probe still had it, the text it was
/// compared with. A page keeps its last text in its state; a file's is the version the watch kept last time.
public struct ComparedText: Sendable, Equatable {
    public var text: String
    public var before: String?

    public init(_ text: String, before: String? = nil) {
        self.text = text
        self.before = before
    }
}

/// A value a report read: words for people, in the app's language ("18,4 °C"), and the same in English for a
/// model ("18.4 °C"). `fromOutside` marks text taken from a web page or a command's output (SECURITY T2).
public struct ReadingText: Sendable, Equatable {
    public var shown: String
    public var forModel: String
    public var fromOutside: Bool

    public init(shown: String, forModel: String, fromOutside: Bool = false) {
        self.shown = shown
        self.forModel = forModel
        self.fromOutside = fromOutside
    }
}

/// The latest value of a report, as the app shows it beside the companion and on Now. Carries what the app needs
/// so that a reading every few seconds costs no database read.
public struct WatchReading: Sendable, Hashable {
    public var watcherId: String
    public var title: String
    /// The short name a pill beside the companion shows: "CPU", "Fukuoka".
    public var label: String
    public var value: String
    public var at: Date
    public var intervalS: TimeInterval
    /// The person asked for a notification with every reading.
    public var notify: Bool
    /// The value as a pin shows it at rest (`PinValue`), with what is set around it.
    public var atRest: String
    /// The value alone, for reading a number from: "Q3" around it is no part of a line drawn from it.
    public var plain: String
    public var display: Watcher.Display = .beside

    public init(watcherId: String, title: String, label: String, value: String, at: Date, intervalS: TimeInterval, notify: Bool) {
        self.watcherId = watcherId
        self.title = title
        self.label = label
        self.value = value
        self.at = at
        self.intervalS = intervalS
        self.notify = notify
        atRest = PinValue.atRest(value)
        plain = value
    }

    /// Whether a value set to come and go is due its moment beside the companion: at each reading, once a minute at most.
    public func dueItsMoment(last: Date?) -> Bool {
        guard display == .notify else { return false }
        guard let last else { return true }
        return at.timeIntervalSince(last) >= max(intervalS, WatchLimits.momentFloor)
    }

    /// Whether this value also goes out as a system notification (D35): when the person asked for one, or when
    /// the companion is hidden and values come slower than once a minute, if it would have been showing beside it.
    /// Never in quiet mode, which lets only urgent things through: a value every few seconds or minutes never is, and
    /// the pill still shows it.
    public func notifies(companionVisible: Bool, quiet: Bool) -> Bool {
        !quiet && (notify || (display == .beside && !companionVisible && intervalS > 60))
    }

    init(_ w: Watcher, value: String, at: Date) {
        let plain = value.displaySafe.clipped(WatchLimits.readingLimit)
        self.init(watcherId: w.id, title: w.title, label: w.config.string("place")?.components(separatedBy: ",").first ?? w.title,
                  value: WatchValue.dressed(plain, w), at: at, intervalS: w.intervalS,
                  notify: w.config["notify"]?.boolValue == true)
        atRest = WatchValue.dressed(PinValue.atRest(plain), w)
        self.plain = plain
        display = w.display
    }
}

/// A value with what was set around it: "$45", "GPU 45 %". The value is isolated so its digits never reorder among
/// words of another direction; in an Arabic window the prefix simply reads first, from the right. A value with neither
/// stays exactly as it was. A word gets a space, a sign doesn't.
enum WatchValue {
    static func dressed(_ value: String, _ w: Watcher) -> String {
        guard w.valuePrefix != nil || w.valueSuffix != nil else { return value }
        let before = w.valuePrefix.map { $0 + (($0.last?.isLetter ?? false) ? " " : "") } ?? ""
        let after = w.valueSuffix.map { (($0.first?.isLetter ?? false) ? " " : "") + $0 } ?? ""
        return "\(before)\u{2068}\(value)\u{2069}\(after)"
    }

    /// What may be set: one short line, or nil for nothing.
    static func affix(_ text: String?) -> String? {
        let clean = (text ?? "").displaySafe.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : String(clean.prefix(WatchLimits.maxAffix))
    }
}

extension WatchReading {
    /// The first number in a shown value ("34 %", "18.5 °C", "1,2 GB"), or nil for words ("Rain"). A comma between
    /// digits is read as a decimal point, as several languages write it.
    public static func number(in shown: String) -> Double? {
        guard let match = shown.firstMatch(of: /-?\d+(?:[.,]\d+)?/) else { return nil }
        return Double(match.output.replacingOccurrences(of: ",", with: "."))
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
    /// The floor for this watcher, when it depends on more than the kind (a command that reports its output
    /// may run more often than one that waits for a change).
    func minimumInterval(for watcher: Watcher) -> TimeInterval
}

public extension WatcherProbe {
    var defaultInterval: TimeInterval { 300 }
    var minimumInterval: TimeInterval { 60 }
    var repeatCooldown: TimeInterval { WatchLimits.defaultCooldown }
    func prepare(_ watcher: Watcher) throws -> Watcher { watcher }
    func eventTargets(for watcher: Watcher) -> [WatchEventTarget] { [] }
    func minimumInterval(for watcher: Watcher) -> TimeInterval { minimumInterval }
}

/// A watcher that cannot be created or changed. The message is written for the user, in the app's language.
/// What `WatcherEngine.edit` changes; nil leaves it.
public struct WatchEdit: Sendable {
    public var title: String?
    public var intervalS: TimeInterval?
    public var level: AttentionLevel?
    public var mode: Watcher.Mode?
    public var condition: JSONValue?

    public init(title: String? = nil, intervalS: TimeInterval? = nil, level: AttentionLevel? = nil, mode: Watcher.Mode? = nil, condition: JSONValue? = nil) {
        self.title = title
        self.intervalS = intervalS
        self.level = level
        self.mode = mode
        self.condition = condition
    }
}

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
    /// Asking again can't help (no such place, no battery, no value where the page was told to look): the watcher
    /// stops with this message instead of retrying.
    case invalid(String)

    public var description: String {
        switch self {
        case .failed(let m), .invalid(let m): m
        case .deferred: String(localized: "Waiting a moment before asking that site again.")
        case .offline: String(localized: "No internet connection.")
        }
    }
}

/// The numbers that keep watchers calm (docs/SECURITY.md T24).
public enum WatchLimits {
    /// How many other agents may keep going together before the person is asked (T4): their names are self-chosen, so
    /// a new client buys no new room. The person's own and Sidefolk's agent have no count, only the floors below (D116).
    public static let externalRoom = 25
    /// How much room the person's yes to `watch.more_room` adds, and the most it ever comes to.
    public static let externalRoomStep = 25
    public static let externalRoomMost = 200
    /// What runs without the person's own words (routines, extensions, a turn that read outside content) together.
    public static let maxUnattended = 50
    /// Live values always beside the companion: the desktop's room is what is short, not the running of them (D116).
    public static let maxBeside = 3
    /// Of those, what every external agent together may hold (T4, T29).
    public static let maxExternalBeside = 2
    /// The longest "$" or "GPU" around a value.
    public static let maxAffix = 8
    /// However often a value is read, a moment beside the companion comes no more often than this, and lasts this long (D116).
    public static let momentFloor: TimeInterval = 60
    public static let momentLength: TimeInterval = 8
    public static let onceExpiry: TimeInterval = 7 * 86400
    public static let repeatExpiry: TimeInterval = 30 * 86400
    /// A report stops on its own unless the person said to keep going: after an hour when it reads more often
    /// than once a minute, after a day otherwise (D35).
    public static let fastReportLifetime: TimeInterval = 3600
    public static let reportLifetime: TimeInterval = 86400
    /// External agents' watchers stop after a day unless they said `until` when made (T4, D160).
    public static let externalExpiry: TimeInterval = 86400
    /// How long one may run when it says so at the start (`until`, D160), and no longer however it's changed.
    public static let externalLongest: TimeInterval = 7 * 86400
    public static let defaultCooldown: TimeInterval = 30 * 60
    public static let maxBackoff: TimeInterval = 6 * 3600
    public static let maxInterval: TimeInterval = 7 * 86400
    /// Consecutive failures before the user hears about it.
    public static let failuresBeforeNotice = 3
    /// Notice titles and snippets are kept short (T17).
    public static let summaryLimit = 200
    /// A report's value: a number or a short line (the pill beside the companion shows the start of it).
    public static let readingLimit = 80
}

extension Watcher {
    /// When a repeating watch that just fired looks again, if that's later than its schedule says: read from the watch itself, so it holds after a restart.
    public func restingUntil(now: Date) -> Date? {
        guard state == .active, mode == .repeat, errorCount == 0, fireCount > 0, let next = nextCheckAt, let last = lastCheckedAt,
              next > now, next.timeIntervalSince(last) > intervalS * 1.5 + 5 else { return nil }
        return next
    }
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
    /// Reports (`watch.report`): a system metric, the weather somewhere, a value on a web page.
    public static let metric = "metric"
    public static let weather = "weather"
    public static let webValue = "web_value"

    /// Kinds the `watch.create` tool offers (the command kind has its own tool, reports have `watch.report`).
    public static let creatable = [urlChange, siteStatus, fileAppears, fileChanges, folderNewFile, processExits]
}

/// The fastest each kind of report may read, stated in the tool descriptions so models pick valid values. Faster
/// requests are raised to these and the answer says so; nothing is refused for being too frequent (D35).
public enum ReportFloors {
    /// CPU, memory, battery, disk, network: a few system calls, no process, no network.
    public static let metric: TimeInterval = 5
    /// A command starts a process each time.
    public static let command: TimeInterval = 10
    /// Someone else's server, which HostThrottle already asks at most once a minute.
    public static let web: TimeInterval = 60
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
        case .command(let id): "command:\(id)"
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
        case .routine, .external, .extension, .command: string(for: caller) == source
        }
    }
}

/// Test and "check now" hook: a check the user asked for right now skips polite delays.
public enum WatchContext {
    @TaskLocal public static var isManualCheck = false
    /// One value asked for now (`watch.read`): a rate (CPU, network) is measured over a fresh moment, not since
    /// whichever report sampled last, which could be many minutes ago.
    @TaskLocal public static var isReadingNow = false
}

// MARK: Small helpers shared by the probes

extension JSONValue {
    /// A copy of an object with `key` set (or removed when `value` is nil).
    public func setting(_ key: String, _ value: JSONValue?) -> JSONValue {
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
            // What can't be seen, or reads as blank: soft hyphens, Arabic and Mongolian marks, Hangul fillers, C1 controls (D160).
            case 0x00AD, 0x034F, 0x061C, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x180B...0x180F, 0x3164, 0xFFA0, 0x80...0x9F: continue
            case 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2069, 0xFEFF, 0xE0000...0xE007F: continue
            case 0x00...0x08, 0x0B...0x0C, 0x0E...0x1F, 0x7F: continue
            case 0x09, 0x0A, 0x0D, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: out.append(" ")
            default: out.append(u)
            }
        }
        return String(out).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}

extension Watcher {
    /// Who its notices are from: an extension's watch is that extension's ("extension:<id>"), so Settings › Attention
    /// can set it apart (D88); every other watch is "watcher". The card still reads as Scout's watch (`refKind`).
    public var noticeSource: String {
        guard kind == "extension", let id = config.string("extension"), !id.isEmpty else { return "watcher" }
        return "extension:\(id)"
    }
}
