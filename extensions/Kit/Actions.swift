import Foundation

/// Sidefolk's tools, for an extension that declares `permissions.act` (D110). Everything runs through Guard as this extension: each call
/// asks the person on a card, unless it fits a plan they read and allowed. It never decides anything here: a call that isn't allowed
/// comes back as such, and everything goes in History.
///
/// ```swift
/// let tools = await Actions.list()                                       // what you may ask for, with each schema
/// let outcome = await Actions.call("notes.save", ["text": "Hello"])      // on a card
/// let plan = Plan(id: "morning", title: "Morning brief", when: "Weekdays at 8:30",
///                 steps: [PlanStep("agenda.today"), PlanStep("notify.user", ["title": "{{brief}}"])])
/// _ = await Plans.approve(plan)                                          // only just after the person's click or request
/// _ = await Actions.call("agenda.today", plan: "morning")                // no card now
/// ```
@MainActor public enum Actions {
    /// One tool you may ask for.
    public struct Tool: Sendable, Hashable {
        public var name: String
        public var title: String
        public var description: String
        /// JSON Schema, as a JSON string: the model's own view of it, so another author's words aren't in it.
        public var schema: String
        public var risk: String
        public var mutates: Bool
        public var category: String
        /// Sidefolk itself says it changes nothing: one of its own tools, or one of its signed extensions'. An author's word alone isn't this.
        public var readsOnly: Bool
        /// The last part of the id of the extension it comes from; nil for Sidefolk's own.
        public var extensionName: String?
        /// That extension's own name, or the MCP server's.
        public var extensionTitle: String?
        /// It comes from an MCP server the person added.
        public var fromServer: Bool
        /// What its answer holds, as a JSON string, if it says.
        public var outputSchema: String?

        public init(name: String, title: String, description: String = "", schema: String = "{}", risk: String = "medium", mutates: Bool = true, category: String = "", readsOnly: Bool = false, extensionName: String? = nil, extensionTitle: String? = nil, fromServer: Bool = false, outputSchema: String? = nil) {
            self.name = name
            self.title = title
            self.description = description
            self.schema = schema
            self.risk = risk
            self.mutates = mutates
            self.category = category
            self.readsOnly = readsOnly
            self.extensionName = extensionName
            self.extensionTitle = extensionTitle
            self.fromServer = fromServer
            self.outputSchema = outputSchema
        }
    }

    public struct Listing: Sendable {
        public var tools: [Tool]
        public var plans: [Plans.Standing]

        public init(tools: [Tool], plans: [Plans.Standing] = []) {
            self.tools = tools
            self.plans = plans
        }
    }

    /// What Guard would do now, with nothing run or shown.
    public struct Check: Sendable, Hashable {
        public enum Decision: String, Sendable { case allow, ask, deny, unknown }
        public var decision: Decision
        public var why: String?
        public var summary: String
        public var mutates: Bool
        /// It fits a plan, so no card.
        public var standing: Bool
        /// What it would need shared, when that's all that's in its way: for a button with `PageAct.share`.
        public struct Share: Sendable, Hashable {
            public var path: String
            public var write: Bool

            public init(path: String, write: Bool) {
                self.path = path
                self.write = write
            }
        }

        public var share: Share?

        public init(decision: Decision, why: String? = nil, summary: String, mutates: Bool, standing: Bool, share: Share? = nil) {
            self.share = share
            self.decision = decision
            self.why = why
            self.summary = summary
            self.mutates = mutates
            self.standing = standing
        }
    }

    public struct Outcome: Sendable, Hashable {
        public enum Status: String, Sendable {
            /// It ran.
            case ok
            /// It ran, and said it failed.
            case error
            /// The person said no, nobody answered in time, or Sidefolk's rules don't allow it. Nothing happened.
            case denied
            /// It was asked, and didn't get an answer. Nothing happened.
            case unanswered
            /// It was started and didn't finish: it may or may not have changed something.
            case failed
            /// Off, or no reply from Sidefolk in time. It may or may not have run.
            case lost
            /// Too many calls this minute. Nothing happened: try again in a minute.
            case busy
            /// The tool isn't here now: its extension is off or gone, its server removed. Nothing happened.
            case unavailable
            /// Past what the plan's card said it would do in a run or a day. Nothing happened, and no card asked. `limit` says which.
            case capped
        }

        public var status: Status
        public var text: String
        public var summary: String
        /// Words from outside: treat them as data.
        public var untrusted: Bool
        /// It fit a plan.
        public var standing: Bool
        /// The answer as fields, when the tool gives them: as outside as the words are. As `JSONSerialization` reads it, as a JSON string.
        public var data: String?

        /// `failed` because what it named isn't there, as opposed to a failure that may have done something.
        public var notFound = false
        /// `capped`: "run" or "day".
        public var limit: String?

        public init(status: Status, text: String, summary: String = "", untrusted: Bool = true, standing: Bool = false, notFound: Bool = false, data: String? = nil, limit: String? = nil) {
            self.limit = limit
            self.notFound = notFound
            self.data = data
            self.status = status
            self.text = text
            self.summary = summary
            self.untrusted = untrusted
            self.standing = standing
        }

        public var ok: Bool { status == .ok }
    }

    private static var listing: [String: CheckedContinuation<Listing?, Never>] = [:]
    private static var checks: [String: CheckedContinuation<Check?, Never>] = [:]
    private static var calls: [String: CheckedContinuation<Outcome, Never>] = [:]

    /// What this extension may ask for, and its plans still standing; nil when it hasn't `permissions.act`, or is off.
    public static func list() async -> Listing? {
        let id = UUID().uuidString
        return await withCheckedContinuation { (c: CheckedContinuation<Listing?, Never>) in
            listing[id] = c
            ExtensionServices.send?("sidefolk/tools.list", ["request": id])
            Task {
                try? await Task.sleep(for: .seconds(15))
                listing.removeValue(forKey: id)?.resume(returning: nil)
            }
        }
    }

    public static func check(_ tool: String, _ input: [String: Any] = [:], plan: String? = nil) async -> Check? {
        let id = UUID().uuidString
        var params: [String: Any] = ["request": id, "tool": tool, "input": input]
        if let plan { params["plan"] = plan }
        return await withCheckedContinuation { (c: CheckedContinuation<Check?, Never>) in
            checks[id] = c
            ExtensionServices.send?("sidefolk/tools.check", params)
            Task {
                try? await Task.sleep(for: .seconds(15))
                checks.removeValue(forKey: id)?.resume(returning: nil)
            }
        }
    }

    /// Runs a tool and waits for what came of it. A card waits at most two minutes. `written`: the call before you filled words in, `{{name}}` where
    /// they went, for History to keep instead of them (only where a plan may leave words open; Sidefolk checks it fits).
    /// - Parameters:
    ///   - request: hands you this call's id as it starts, for `cancel`.
    ///   - progress: how far along it is, when the tool says: at most once a second, and the tool's own words.
    ///   - run: what a plan's limit for one run counts by.
    public static func call(_ tool: String, _ input: [String: Any] = [:], plan: String? = nil, written: [String: Any]? = nil, seconds: Double = 300, run: String? = nil,
                            request: ((String) -> Void)? = nil, progress: ((Progress) -> Void)? = nil) async -> Outcome {
        let id = UUID().uuidString
        request?(id)
        following[id] = progress
        defer { following[id] = nil }
        var params: [String: Any] = ["request": id, "tool": tool, "input": input, "timeout": seconds]
        if let plan { params["plan"] = plan }
        if let written { params["written"] = written }
        if let run { params["run"] = run }
        return await withCheckedContinuation { (c: CheckedContinuation<Outcome, Never>) in
            calls[id] = c
            ExtensionServices.send?("sidefolk/tools.call", params)
            Task {
                // Past Sidefolk's own limit: its answer is what reports a slow tool.
                try? await Task.sleep(for: .seconds(seconds + 150))
                calls.removeValue(forKey: id)?.resume(returning: Outcome(status: .lost, text: "", summary: "", untrusted: false, standing: false))
            }
        }
    }

    /// How far along a call is. `fraction` is nil if it can't say.
    public struct Progress: Sendable, Hashable {
        public var fraction: Double?
        public var message: String?

        public init(fraction: Double? = nil, message: String? = nil) {
            self.fraction = fraction
            self.message = message
        }
    }

    /// Asks Sidefolk to stop a call under way. A card still up goes away and nothing happens. Past that the tool is told, and may or may not stop: the answer comes back as for any call.
    public static func cancel(_ request: String) {
        ExtensionServices.send?("sidefolk/tools.cancel", ["request": request])
    }

    private static var following: [String: (Progress) -> Void] = [:]

    static func receiveProgress(_ args: Arguments) {
        guard let id = args.string("request"), let report = following[id] else { return }
        let done = args.double("progress"), total = args.double("total")
        let fraction = total.flatMap { t in t > 0 ? done.map { min(max($0 / t, 0), 1) } : nil }
        report(Progress(fraction: fraction, message: args.string("message")))
    }

    static func receiveListing(_ args: Arguments) {
        guard let id = args.string("request"), let c = listing.removeValue(forKey: id) else { return }
        guard args.bool("ok") == true else { return c.resume(returning: nil) }
        let tools = (args.values["tools"] as? [[String: Any]] ?? []).compactMap { t -> Tool? in
            guard let name = t["name"] as? String else { return nil }
            let schema = (try? JSONSerialization.data(withJSONObject: t["schema"] ?? [:], options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return Tool(name: name, title: t["title"] as? String ?? name, description: t["description"] as? String ?? "", schema: schema,
                        risk: t["risk"] as? String ?? "medium", mutates: t["mutates"] as? Bool ?? true, category: t["category"] as? String ?? "",
                        readsOnly: t["reads_only"] as? Bool ?? false, extensionName: t["extension"] as? String,
                        extensionTitle: t["extension_title"] as? String, fromServer: t["from_server"] as? Bool ?? false,
                        outputSchema: t["output_schema"].flatMap { JSONSerialization.isValidJSONObject($0) ? try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) : nil }.flatMap { String(data: $0, encoding: .utf8) })
        }
        let plans = (args.values["plans"] as? [[String: Any]] ?? []).compactMap { p -> Plans.Standing? in
            guard let id = p["id"] as? String else { return nil }
            return Plans.Standing(id: id, title: p["title"] as? String ?? "", standing: p["standing"] as? [Bool] ?? [],
                                  expires: (p["expires_at"] as? Double).map(Date.init(timeIntervalSince1970:)))
        }
        c.resume(returning: Listing(tools: tools, plans: plans))
    }

    static func receiveCheck(_ args: Arguments) {
        guard let id = args.string("request"), let c = checks.removeValue(forKey: id) else { return }
        guard args.bool("ok") == true else { return c.resume(returning: nil) }
        c.resume(returning: Check(decision: Check.Decision(rawValue: args.string("decision") ?? "") ?? .unknown, why: args.string("why"), summary: args.string("summary") ?? "",
                                  mutates: args.bool("mutates") ?? true, standing: args.bool("standing") ?? false,
                                  share: (args.values["share"] as? [String: Any]).flatMap { s in (s["path"] as? String).map { Check.Share(path: $0, write: s["write"] as? Bool ?? false) } }))
    }

    static func receiveResult(_ args: Arguments) {
        guard let id = args.string("request"), let c = calls.removeValue(forKey: id) else { return }
        c.resume(returning: Outcome(status: Outcome.Status(rawValue: args.string("status") ?? "") ?? .lost, text: args.string("text") ?? "", summary: args.string("summary") ?? "",
                                    untrusted: args.bool("untrusted") ?? true, standing: args.bool("standing") ?? false, notFound: args.bool("not_found") ?? false,
                                    data: args.values["data"].flatMap { JSONSerialization.isValidJSONObject($0) ? try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) : nil }.flatMap { String(data: $0, encoding: .utf8) }, limit: args.string("limit")))
    }
}

/// One thing a plan does: a tool and its exact values, with `{{name}}` where words are filled in when it runs. Sidefolk lets only a few
/// plain words be filled in (a note's text, a notice, a question, a reminder's title); any other step with `{{name}}` still asks each time.
public struct PlanStep: @unchecked Sendable {
    public var tool: String
    public var input: [String: Any]
    /// The step's own name: what another step's `{{name}}` goes by, so the card can say where a value comes from. One name, one step.
    public var named: String?
    /// Your words for it, as the card shows them beside its own.
    public var title: String?
    /// A field you filled from the person or the clock, by name: "person" or "clock". Believed from a signed pack only.
    public var from: [String: String]?
    private var kind: String?
    private var reads: [String]?
    private var flow: String?

    public init(_ tool: String, _ input: [String: Any] = [:], named: String? = nil, title: String? = nil, from: [String: String]? = nil) {
        self.tool = tool
        self.input = input
        self.named = named
        self.title = title
        self.from = from
    }

    /// A step that gives what it read to the person's AI. `reads`: the names it uses; none means everything before it.
    public static func ai(named: String? = nil, title: String? = nil, reads: [String] = []) -> PlanStep {
        var step = PlanStep("", named: named, title: title)
        step.kind = "ai"
        step.reads = reads.isEmpty ? nil : reads
        return step
    }

    /// A step that only passes something on: never on the card, but what a later step's value really comes from. `reads`: the names it's made from, at least one.
    /// A name Sidefolk can't place counts as from outside.
    public static func value(named: String, reads: [String]) -> PlanStep {
        var step = PlanStep("", named: named)
        step.kind = "value"
        step.reads = reads
        return step
    }

    /// A step that sets off another flow, which has its own approval.
    public static func flow(_ name: String, named: String? = nil, title: String? = nil) -> PlanStep {
        var step = PlanStep("", named: named, title: title)
        step.kind = "flow"
        step.flow = name
        return step
    }

    var wire: [String: Any] {
        var out: [String: Any] = [:]
        if let kind { out["kind"] = kind } else {
            out["tool"] = tool
            out["input"] = input
        }
        if let flow { out["name"] = flow }
        if let reads { out["reads"] = reads }
        if let named { out["as"] = named }
        if let title { out["title"] = title }
        if let from { out["from"] = from }
        return out
    }

    /// It's only there to say where a value comes from, and isn't on the card.
    public var onlyPassesOn: Bool { kind == "value" }

    /// What makes it the same line on a card as another step.
    public var line: String {
        if let kind { return "\(kind) \(flow ?? "") \(reads ?? [])" }
        let written = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return "\(tool) \(written)"
    }
}

/// What the person reads on the card. `ttl`: it ends by itself after so many seconds (60 to 3600), for something only tried once.
public struct Plan: @unchecked Sendable {
    public var id: String
    public var title: String
    public var when: String
    public var steps: [PlanStep]
    public var ttl: Int?
    public var perDay: Int?
    /// The most calls in one run, 1 to 1000: past it they're refused, with no card. Sidefolk's own default otherwise.
    public var perRun: Int?
    /// "run" or "turn_on": which the card is headed for.
    public var intent: String?
    /// It goes round: the card says the higher limit that takes.
    public var goesRound: Bool
    /// Names of steps whose values come only from the person or the clock. Believed from a signed pack only.
    public var inside: [String]

    public init(id: String, title: String, when: String = "", steps: [PlanStep], ttl: Int? = nil, perDay: Int? = nil, perRun: Int? = nil, intent: String? = nil, goesRound: Bool = false, inside: [String] = []) {
        self.id = id
        self.title = title
        self.when = when
        self.steps = steps
        self.ttl = ttl
        self.perDay = perDay
        self.perRun = perRun
        self.intent = intent
        self.goesRound = goesRound
        self.inside = inside
    }

    var wire: [String: Any] {
        var body: [String: Any] = ["id": id, "title": title, "when": when, "steps": steps.map(\.wire)]
        if let ttl { body["ttl"] = ttl }
        if let perDay { body["per_day"] = perDay }
        if let perRun { body["per_run"] = perRun }
        if let intent { body["intent"] = intent }
        if goesRound { body["goes_round"] = true }
        if !inside.isEmpty { body["inside"] = inside }
        return body
    }
}

/// Plans the person read, so that exactly that needs no more cards (D110). Only an extension that can't reach beyond this Mac by itself gets
/// them, and only just after the person's click or request, never from a timer.
@MainActor public enum Plans {
    /// The most different lines a plan may hold; Sidefolk refuses more, and a plan with none and no `when` to say what it's for.
    public nonisolated static let maxSteps = 64
    /// The most steps it may list, alike or not.
    public nonisolated static let maxRows = 256
    /// The highest `perRun`.
    public nonisolated static let mostPerRun = 1000

    public struct Standing: Sendable, Hashable {
        public var id: String
        public var title: String
        /// By step, in order: true runs without asking.
        public var standing: [Bool]
        public var expires: Date?

        public init(id: String, title: String, standing: [Bool], expires: Date? = nil) {
            self.id = id
            self.title = title
            self.standing = standing
            self.expires = expires
        }
    }

    public enum Answer: Sendable, Hashable {
        /// Allowed. By different line, in order: true runs without asking, false still asks each time. `silent`: nothing new, so no card. `new`: how many lines were new.
        case allowed(standing: [Bool], silent: Bool = false, new: Int = 0)
        /// `denied`, `unanswered`, `not_asked` (no recent click), `not_contained`, `unknown_tool`, `unusable`, `off`, `changed` (the extension was replaced under the card), `busy`.
        case refused(String)
    }

    /// What would happen if this plan were approved, with nothing shown or changed.
    public struct Checked: Sendable, Hashable {
        public struct Line: Sendable, Hashable {
            /// `stands`, `stands_in_full_access`, `asks`, `refused`, `listed`.
            public var state: String
            /// Why it asks or is refused: `code_field`, `reach_field`, `server_unpinned`, `switch_off`, `text_to_read`, `shell`, `high_risk`, `nested_slot`, `unreadable_value`, `filled_value`, `private_read`, `ask_every_time`.
            public var why: String?
            /// `crossing`: it stands, and the card warns about what it passes on.
            public var warning: String?

            public init(state: String, why: String? = nil, warning: String? = nil) {
                self.state = state
                self.why = why
                self.warning = warning
            }
        }

        /// By step as sent.
        public var steps: [Line]
        /// The steps that aren't covered yet, by place in `steps`.
        public var new: [Int]
        /// Approving it would show no card.
        public var silent: Bool
        /// Its terms go further than what stands, even with no new line.
        public var widened: Bool

        public init(steps: [Line], new: [Int] = [], silent: Bool = false, widened: Bool = false) {
            self.steps = steps
            self.new = new
            self.silent = silent
            self.widened = widened
        }
    }

    private static var checking: [String: CheckedContinuation<Checked?, Never>] = [:]

    /// Nil when Sidefolk gives no answer: an older copy, or the extension has no `permissions.act`.
    public static func check(_ plan: Plan) async -> Checked? {
        let id = UUID().uuidString
        return await withCheckedContinuation { (c: CheckedContinuation<Checked?, Never>) in
            checking[id] = c
            ExtensionServices.send?("sidefolk/plan.check", ["request": id, "plan": plan.wire])
            Task {
                try? await Task.sleep(for: .seconds(15))
                checking.removeValue(forKey: id)?.resume(returning: nil)
            }
        }
    }

    static func receiveChecked(_ args: Arguments) {
        guard let id = args.string("request"), let c = checking.removeValue(forKey: id) else { return }
        guard args.bool("ok") == true else { return c.resume(returning: nil) }
        let lines = (args.values["steps"] as? [[String: Any]] ?? []).map { Checked.Line(state: $0["state"] as? String ?? "asks", why: $0["why"] as? String, warning: $0["warning"] as? String) }
        c.resume(returning: Checked(steps: lines, new: (args.values["new"] as? [NSNumber] ?? []).map(\.intValue), silent: args.bool("silent") ?? false, widened: args.bool("widened") ?? false))
    }

    private static var waiting: [String: CheckedContinuation<Answer, Never>] = [:]
    /// Called when the person ended a plan in Settings.
    public static var ended: (@MainActor (String) -> Void)?

    /// Shows the card, and waits for the person's answer (two minutes at most).
    public static func approve(_ plan: Plan) async -> Answer {
        let id = UUID().uuidString
        return await withCheckedContinuation { (c: CheckedContinuation<Answer, Never>) in
            waiting[id] = c
            ExtensionServices.send?("sidefolk/plan.approve", ["request": id, "plan": plan.wire])
            Task {
                try? await Task.sleep(for: .seconds(150))
                waiting.removeValue(forKey: id)?.resume(returning: .refused("unanswered"))
            }
        }
    }

    public static func forget(_ id: String) {
        ExtensionServices.send?("sidefolk/plan.forget", ["plan": id])
    }

    static func receive(_ args: Arguments) {
        guard let id = args.string("request"), let c = waiting.removeValue(forKey: id) else { return }
        if args.bool("ok") == true {
            c.resume(returning: .allowed(standing: args.values["standing"] as? [Bool] ?? [], silent: args.bool("silent") ?? false, new: args.int("new") ?? 0))
        } else {
            c.resume(returning: .refused(args.string("reason") ?? "denied"))
        }
    }
}
