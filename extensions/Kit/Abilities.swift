import Foundation

/// What the host gives an extension beyond its requests (D100): its settings, one History row, and the person's AI.
@MainActor enum ExtensionServices {
    static var send: ((_ method: String, _ params: [String: Any]) -> Void)?
}

/// The settings the manifest declares (`settings`), as the host keeps them. They come with every request, so they are current when
/// the request is answered; the person changes them on the extension's page or in Settings › Add-ons.
@MainActor public enum ExtensionSettings {
    private static var values: [String: Any] = [:]

    static func use(_ any: Any?) {
        if let new = any as? [String: Any] { values = new }
    }

    public static var all: Arguments { Arguments(values) }
    public static func bool(_ key: String) -> Bool? { all.bool(key) }
    public static func string(_ key: String) -> String? { all.string(key) }
    public static func double(_ key: String) -> Double? { all.double(key) }
    public static func int(_ key: String) -> Int? { all.int(key) }

    /// Changes one of its own settings (a speaker button on its surface): checked against the schema, through Guard, in History.
    public static func set(_ key: String, _ value: Any) {
        ExtensionServices.send?("sidefolk/settings.set", ["key": key, "value": value])
    }
}

/// One row in History from a surface, in the extension's words (D100). `key` is its own name for what it was about, `result`
/// `win`, `loss`, `draw` or `done`. At most one every five seconds.
public enum Activity {
    @MainActor public static func add(_ text: String, key: String? = nil, result: String? = nil) {
        var params: [String: Any] = ["text": text]
        if let key { params["key"] = key }
        if let result { params["result"] = result }
        ExtensionServices.send?("sidefolk/activity.add", params)
    }
}

/// The person's AI, for an extension that declares `permissions.ai` (D100). It gets the words sent here and nothing else, has no tools,
/// and its answer comes back only to this program: check it before use, as anything from outside.
///
/// ```swift
/// guard AI.available != nil else { return }                   // on, within reach, the person's switch not off
/// switch await AI.ask("Three riddles about {topic} as JSON…", label: "Riddles about the sea") {
/// case .answer(let text, let madeBy): …                      // label it "Made by \(madeBy), not checked"
/// case .refused(let reason): …                               // off, busy, limit, unusable, failed, denied
/// }
/// ```
@MainActor public enum AI {
    public enum Result: Equatable, Sendable {
        case answer(text: String, madeBy: String)
        case refused(String)
    }

    /// The person's AI by name while this extension may ask; nil when it is off or there is none.
    public private(set) static var available: String?
    private static var waiting: [String: CheckedContinuation<Result, Never>] = [:]

    /// Requests say whether it may ask: a request without the key means no.
    static func use(_ name: String?, asked method: String) {
        guard method == "tools/call" || method.hasPrefix("sidefolk/") else { return }
        available = name
    }

    /// Asks once and waits, at most `seconds`. One at a time; `label` is a few words for History ("Riddles about the sea").
    public static func ask(_ prompt: String, label: String? = nil, seconds: Double = 90) async -> Result {
        let id = UUID().uuidString
        var params: [String: Any] = ["request": id, "prompt": prompt]
        if let label { params["label"] = label }
        params["language"] = Language.code
        return await withCheckedContinuation { (c: CheckedContinuation<Result, Never>) in
            waiting[id] = c
            ExtensionServices.send?("sidefolk/ai.request", params)
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                finish(id, .refused("failed"))
            }
        }
    }

    static func receive(_ args: Arguments) {
        guard let id = args.string("request") else { return }
        if args.bool("ok") == true, let text = args.string("text") {
            finish(id, .answer(text: text, madeBy: args.string("made_by") ?? ""))
        } else {
            finish(id, .refused(args.string("reason") ?? "failed"))
        }
    }

    private static func finish(_ id: String, _ result: Result) {
        waiting.removeValue(forKey: id)?.resume(returning: result)
    }
}

/// Where the person is, for an extension that declares `permissions.place` and only once they said yes (D106). Their place never changes
/// by itself here: requests carry it, and `ext.placeChanged` says when it moved or they took it back.
@MainActor public enum SharedPlace {
    public struct Place: Sendable {
        public var city: String
        public var region: String?
        public var country: String?
        public var countryCode: String?
        public var latitude: Double
        public var longitude: Double
        public var timeZone: String?
        public var updatedAt: Date?

        init?(_ json: [String: Any]?) {
            guard let json, let city = json["city"] as? String, let latitude = (json["latitude"] as? NSNumber)?.doubleValue,
                  let longitude = (json["longitude"] as? NSNumber)?.doubleValue else { return nil }
            self.city = city
            region = json["region"] as? String
            country = json["country"] as? String
            countryCode = json["country_code"] as? String
            self.latitude = latitude
            self.longitude = longitude
            timeZone = json["time_zone"] as? String
            updatedAt = (json["updated_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        }
    }

    public struct Found: Sendable {
        public var places: [Place]
        /// Why there is nothing, in the person's language: no connection, or too soon after the last.
        public var problem: String?
    }

    /// The person's place while they allow it; nil when they don't, or Sidefolk doesn't know one.
    public private(set) static var current: Place?
    /// Whether they said yes.
    public private(set) static var shared = false
    private static var waiting: [String: CheckedContinuation<Found, Never>] = [:]

    /// Requests say what it may know: a request without the key changes nothing, since not every request has one.
    static func use(_ params: [String: Any]) {
        guard let status = params["place_share"] as? String else { return }
        shared = status == "on"
        current = shared ? Place(params["place"] as? [String: Any]) : nil
    }

    /// Looks a place up by name through Sidefolk's own place search. Only the words typed leave the Mac.
    public static func search(_ query: String) async -> Found {
        let request = UUID().uuidString
        return await withCheckedContinuation { continuation in
            waiting[request] = continuation
            ExtensionServices.send?("sidefolk/place.search", ["request": request, "query": query])
        }
    }

    static func found(_ args: Arguments) {
        guard let request = args.string("request"), let continuation = waiting.removeValue(forKey: request) else { return }
        let places = (args.values["places"] as? [[String: Any]] ?? []).compactMap { Place($0) }
        continuation.resume(returning: Found(places: places, problem: args.string("problem")))
    }
}

/// One moment to tell the person something, for an extension that declares `permissions.schedule` and only once they said yes (D107). Sidefolk
/// keeps the timer, so the program needn't be running. Its words go to the person, never a model.
public struct Occurrence {
    public var id: String
    public var at: Date
    public var expiresAt: Date
    public var title: String
    public var body: String?
    public var group: String?
    public var systemFallback: Bool
    public var openPage: String?
    public var openState: [String: Any]?

    /// `id` names this moment for good (`[a-z0-9._:-]`, at most 120): one that was told is never told again.
    public init(id: String, at: Date, expiresAt: Date, title: String, body: String? = nil, group: String? = nil, systemFallback: Bool = false,
                openPage: String? = nil, openState: [String: Any]? = nil) {
        self.id = id
        self.at = at
        self.expiresAt = expiresAt
        self.title = title
        self.body = body
        self.group = group
        self.systemFallback = systemFallback
        self.openPage = openPage
        self.openState = openState
    }

    var json: [String: Any] {
        let format = ISO8601DateFormatter()
        var out: [String: Any] = ["id": id, "at": format.string(from: at), "expires_at": format.string(from: expiresAt), "title": title, "system_fallback": systemFallback]
        if let body { out["body"] = body }
        if let group { out["group"] = group }
        if let openPage { out["open"] = ["page": openPage, "state": openState ?? [:]] as [String: Any] }
        return out
    }
}

/// A plan of reminders, the whole of it: what isn't in it no longer comes.
public struct OccurrencePlan {
    public var revision: Int
    public var occurrences: [Occurrence]

    public init(revision: Int, occurrences: [Occurrence]) {
        self.revision = revision
        self.occurrences = occurrences
    }

    var json: [String: Any] { ["revision": revision, "occurrences": occurrences.map(\.json)] }
}

@MainActor public enum Occurrences {
    public enum Notifications: String, Sendable { case allowed, denied, unknown }

    /// The person said yes.
    public private(set) static var allowed = false
    /// What macOS says of notifications from Sidefolk: only matters for `systemFallback`.
    public private(set) static var notifications = Notifications.unknown
    public private(set) static var pending = 0
    public private(set) static var revision = 0

    static func use(_ params: [String: Any]) {
        guard let status = params["occurrences"] as? [String: Any] else { return }
        allowed = status["allowed"] as? Bool ?? false
        notifications = (status["notifications"] as? String).flatMap(Notifications.init(rawValue:)) ?? .unknown
        pending = (status["pending"] as? NSNumber)?.intValue ?? 0
        revision = (status["revision"] as? NSNumber)?.intValue ?? 0
    }

    /// How the last plan went, for a program that wants to say so: `reason` when it wasn't taken.
    public private(set) static var lastResult: (ok: Bool, reason: String?)?

    static func received(_ args: Arguments) {
        lastResult = (args.bool("ok") ?? false, args.string("reason"))
        pending = args.int("pending") ?? pending
        revision = args.int("revision") ?? revision
    }

    /// Replaces the whole plan at once. A plan with a lower `revision` than the last is ignored; one with nothing in it cancels what was left.
    public static func replace(_ plan: OccurrencePlan) {
        ExtensionServices.send?("sidefolk/occurrences.replace", plan.json)
    }
}
