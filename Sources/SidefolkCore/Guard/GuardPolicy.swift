import Foundation

/// How much Sidefolk asks before its own agent acts (D37). A mode changes how often Guard asks,
/// never where Sidefolk may work or what it may do at all: capabilities turned off, protected places
/// and the folder list hold in every mode, and so does asking before anything a web page, file or
/// extension could have steered carries data out.
public enum GuardMode: String, Codable, Sendable, CaseIterable {
    /// Asks before every action that changes something outside Sidefolk; "Always allow" is ignored.
    case askEveryTime
    /// Asks once for each kind of action and remembers "Always allow". The default.
    case askOncePerKind
    /// Acts on its own, except high-risk actions and anything outside content could have steered.
    case auto
    /// Acts without asking, except where outside content could steer data out of the Mac.
    case fullAccess

    /// A name saved by an older or newer Sidefolk never loosens Guard: it reads as the default.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.savedBeforeModes[raw] ?? .askOncePerKind
    }

    /// The two modes as they were saved before D37.
    static let savedBeforeModes: [String: GuardMode] = ["standard": .askOncePerKind, "cautious": .askEveryTime]
}

/// How Sidefolk's own agent reads the web and uses online services without the person typing the address (D47).
/// Like the mode, it changes how often Guard asks, never what may happen at all. After outside content was read
/// (SECURITY T2), a site the person hasn't allowed for good always asks, whichever is chosen: that is where a
/// steered model would write their data into an address.
public enum InternetRule: String, Codable, Sendable, CaseIterable {
    /// Every page and online service Sidefolk chose itself asks, every time; "Always allow" isn't offered for them.
    case askEachTime
    /// "Always allow" remembers a site or a built-in service, and holds even after outside content was read. The default.
    case oncePerSite
    /// Pages and built-in services are used without asking; after outside content was read, only the sites the
    /// person allowed for good go without a card.
    case withoutAsking

    /// A name saved by another version never loosens Guard: it reads as the default.
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .oncePerSite
    }
}

/// What happens when Sidefolk's own agent waits on an approval and nobody answers (D37).
public struct UnansweredRule: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable, CaseIterable {
        /// Wait for the answer, a day at most; then the task stops.
        case keepWaiting
        /// After `minutes`, the model hears the step was skipped and the run carries on without it.
        case skip
        /// After `minutes`, the task stops.
        case stop
    }

    public var action: Action = .skip
    public var minutes: Int = 10

    /// The waits Settings offers.
    public static let minuteChoices = [2, 5, 10, 30, 60]
    /// Even "keep waiting" ends, so no run holds a question, and the brain process behind it, forever.
    public static let longestMinutes = 24 * 60

    public init(action: Action = .skip, minutes: Int = 10) {
        self.action = action
        self.minutes = minutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = (try? c.decode(Action.self, forKey: .action)) ?? .skip
        minutes = (try? c.decode(Int.self, forKey: .minutes)) ?? 10
    }

    /// How long a card waits, in minutes.
    public var waitMinutes: Int { action == .keepWaiting ? Self.longestMinutes : min(max(1, minutes), Self.longestMinutes) }

    /// What happens when the wait runs out: the end of "keep waiting" stops the task.
    public var whenTimeIsUp: Action { action == .keepWaiting ? .stop : action }
}

public struct GuardPolicy: Codable, Sendable, Equatable {
    public var mode: GuardMode = .askOncePerKind
    /// Capabilities the user switched off entirely.
    public var disabled: Set<Capability> = []
    public var unanswered = UnansweredRule()
    public var internet: InternetRule = .oncePerSite

    public init(mode: GuardMode = .askOncePerKind, disabled: Set<Capability> = [], unanswered: UnansweredRule = UnansweredRule(),
                internet: InternetRule = .oncePerSite) {
        self.mode = mode
        self.disabled = disabled
        self.unanswered = unanswered
        self.internet = internet
    }

    /// Every field has a default and is read on its own, so a policy saved before a field existed (or
    /// naming a capability this version doesn't know) keeps the rest: a synthesized decoder would throw,
    /// and the capabilities the person turned off would quietly come back on.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decode(GuardMode.self, forKey: .mode)) ?? .askOncePerKind
        disabled = Set(((try? c.decode([String].self, forKey: .disabled)) ?? []).compactMap(Capability.init(rawValue:)))
        unanswered = (try? c.decode(UnansweredRule.self, forKey: .unanswered)) ?? UnansweredRule()
        internet = (try? c.decode(InternetRule.self, forKey: .internet)) ?? .oncePerSite
    }

    /// The mode Guard applies to `caller`. Only Sidefolk's own agent, which acts on the person's own
    /// request from the Ask panel, is ever asked less, and a command the person typed acts as it (D50). Asking
    /// every time applies to every caller Guard asks for; other agents and extensions otherwise keep their own
    /// rules (SECURITY T4, D37).
    public func mode(for caller: Caller) -> GuardMode {
        if Self.actsForTheAgent(caller) { return mode }
        return mode == .askEveryTime ? .askEveryTime : .askOncePerKind
    }

    /// The internet rule Guard applies to `caller`, or nil: only Sidefolk's own agent has one (D47), and the
    /// commands that act as it (D50). Other agents, routines and extensions keep the rules they had (SECURITY T4).
    public func internet(for caller: Caller) -> InternetRule? {
        Self.actsForTheAgent(caller) ? internet : nil
    }

    private static func actsForTheAgent(_ caller: Caller) -> Bool {
        switch caller {
        case .agent, .command: true
        case .user, .routine, .external, .extension: false
        }
    }
}
