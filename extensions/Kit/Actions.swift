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

        public init(name: String, title: String, description: String = "", schema: String = "{}", risk: String = "medium", mutates: Bool = true, category: String = "", readsOnly: Bool = false, extensionName: String? = nil) {
            self.name = name
            self.title = title
            self.description = description
            self.schema = schema
            self.risk = risk
            self.mutates = mutates
            self.category = category
            self.readsOnly = readsOnly
            self.extensionName = extensionName
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

        public init(decision: Decision, why: String? = nil, summary: String, mutates: Bool, standing: Bool) {
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
        }

        public var status: Status
        public var text: String
        public var summary: String
        /// Words from outside: treat them as data.
        public var untrusted: Bool
        /// It fit a plan.
        public var standing: Bool

        public init(status: Status, text: String, summary: String = "", untrusted: Bool = true, standing: Bool = false) {
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

    /// Runs a tool and waits for what came of it. A card waits at most two minutes.
    public static func call(_ tool: String, _ input: [String: Any] = [:], plan: String? = nil, seconds: Double = 300) async -> Outcome {
        let id = UUID().uuidString
        var params: [String: Any] = ["request": id, "tool": tool, "input": input, "timeout": seconds]
        if let plan { params["plan"] = plan }
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

    static func receiveListing(_ args: Arguments) {
        guard let id = args.string("request"), let c = listing.removeValue(forKey: id) else { return }
        guard args.bool("ok") == true else { return c.resume(returning: nil) }
        let tools = (args.values["tools"] as? [[String: Any]] ?? []).compactMap { t -> Tool? in
            guard let name = t["name"] as? String else { return nil }
            let schema = (try? JSONSerialization.data(withJSONObject: t["schema"] ?? [:], options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return Tool(name: name, title: t["title"] as? String ?? name, description: t["description"] as? String ?? "", schema: schema,
                        risk: t["risk"] as? String ?? "medium", mutates: t["mutates"] as? Bool ?? true, category: t["category"] as? String ?? "",
                        readsOnly: t["reads_only"] as? Bool ?? false, extensionName: t["extension"] as? String)
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
                                  mutates: args.bool("mutates") ?? true, standing: args.bool("standing") ?? false))
    }

    static func receiveResult(_ args: Arguments) {
        guard let id = args.string("request"), let c = calls.removeValue(forKey: id) else { return }
        c.resume(returning: Outcome(status: Outcome.Status(rawValue: args.string("status") ?? "") ?? .lost, text: args.string("text") ?? "", summary: args.string("summary") ?? "",
                                    untrusted: args.bool("untrusted") ?? true, standing: args.bool("standing") ?? false))
    }
}

/// One thing a plan does: a tool and its exact values, with `{{name}}` where words are filled in when it runs. Sidefolk lets only a few
/// plain words be filled in (a note's text, a notice, a question, a reminder's title); any other step with `{{name}}` still asks each time.
public struct PlanStep: @unchecked Sendable {
    public var tool: String
    public var input: [String: Any]

    public init(_ tool: String, _ input: [String: Any] = [:]) {
        self.tool = tool
        self.input = input
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

    public init(id: String, title: String, when: String = "", steps: [PlanStep], ttl: Int? = nil, perDay: Int? = nil) {
        self.id = id
        self.title = title
        self.when = when
        self.steps = steps
        self.ttl = ttl
        self.perDay = perDay
    }
}

/// Plans the person read, so that exactly that needs no more cards (D110). Only an extension that can't reach beyond this Mac by itself gets
/// them, and only just after the person's click or request, never from a timer.
@MainActor public enum Plans {
    public struct Standing: Sendable, Hashable {
        public var id: String
        public var title: String
        /// By step, in order: true runs without asking.
        public var standing: [Bool]
        public var expires: Date?
    }

    public enum Answer: Sendable, Hashable {
        /// Allowed. By step, in order: true runs without asking, false still asks each time.
        case allowed(standing: [Bool])
        /// `denied`, `unanswered`, `not_asked` (no recent click), `not_contained`, `unknown_tool`, `unusable`, `off`.
        case refused(String)
    }

    private static var waiting: [String: CheckedContinuation<Answer, Never>] = [:]
    /// Called when the person ended a plan in Settings.
    public static var ended: (@MainActor (String) -> Void)?

    /// Shows the card, and waits for the person's answer (two minutes at most).
    public static func approve(_ plan: Plan) async -> Answer {
        let id = UUID().uuidString
        var body: [String: Any] = ["id": plan.id, "title": plan.title, "when": plan.when, "steps": plan.steps.map { ["tool": $0.tool, "input": $0.input] }]
        if let ttl = plan.ttl { body["ttl"] = ttl }
        if let perDay = plan.perDay { body["per_day"] = perDay }
        return await withCheckedContinuation { (c: CheckedContinuation<Answer, Never>) in
            waiting[id] = c
            ExtensionServices.send?("sidefolk/plan.approve", ["request": id, "plan": body])
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
            c.resume(returning: .allowed(standing: args.values["standing"] as? [Bool] ?? []))
        } else {
            c.resume(returning: .refused(args.string("reason") ?? "denied"))
        }
    }
}
