import Foundation

/// What a plan an extension sends comes to, worked out by the host and never by the program: which steps stand and how, which are new since the
/// plan the person read, and whether the terms are wider (D186, D187). `plan.approve` shows a card from it, or none; `plan.check` only says it.
struct PlanEvaluation {
    struct Line {
        var step: ExtensionPlan.Step
        /// The tool behind it, nil for a step the host doesn't run (an AI step, another flow).
        var tool: (any Tool)?
        var verdict: ExtensionPlanRules.Verdict
    }

    /// The distinct lines, in order.
    var lines: [Line]
    /// For each row the program sent, the line it became.
    var rows: [Int]
    var plan: ExtensionPlan
    var previous: ExtensionPlan?
    /// Indexes of the lines the person hasn't read yet.
    var fresh: [Int]
    var widened: Bool
    var intent: String?
    /// The person said every page and online service asks each time (D47): lines that use the network ask whatever a plan says.
    var askOnline = false
    /// The person's mode when it was read.
    var mode: GuardMode = .askOncePerKind

    /// Whether the line would run without a card now, in this mode and with this setting for the internet: what the replies say, so they say one thing.
    func standsNow(_ line: Line) -> Bool {
        guard line.step.standing, line.step.kind == nil, mode != .askEveryTime else { return false }
        if line.step.isInFullAccessOnly, mode != .fullAccess { return false }
        return !(askOnline && line.tool?.spec.capabilities.contains(.network) == true)
    }

    /// Nothing is new: the plan they read already allows all of it.
    var covered: Bool { previous != nil && fresh.isEmpty && !widened }
}

extension ExtensionHost {
    /// A step's name has no dot or bracket, so the host and the program can't read a slot like `{{q.title}}` as pointing at different steps.
    private static let nameShape = #"^[A-Za-z0-9_-]{1,60}\z"#

    /// Reads the program's plan against what is standing. A reason (as `plan.result` gives it) when the plan can't be read at all.
    func evaluatePlan(_ id: String, plan: JSONValue, gateway: ExtensionActionGateway) async -> Result<PlanEvaluation, PlanRefusal> {
        // Read before anything else here, so what follows works from one view of the extension (no await between it and the plan it compares).
        let flow = await configuration.flowPolicy()
        let askOnline = await configuration.askEachTimeOnline()
        guard let rt = runtimes[id], plan.jsonString.utf8.count <= ExtensionPlanRules.maxPlanBytes else { return .failure(.unusable) }
        guard let planId = plan["id"]?.stringValue, planId.range(of: #"^[A-Za-z0-9._:-]{1,64}\z"#, options: .regularExpression) != nil,
              let rawSteps = plan["steps"]?.arrayValue, rawSteps.count <= ExtensionPlanRules.maxRows else { return .failure(.unusable) }
        // No action to allow is still something to read when `when` says what it sets off. With nothing to say at all there's no card to show.
        guard !rawSteps.isEmpty || plan["when"]?.stringValue.map({ ExtensionText.clean($0).trimmingCharacters(in: .whitespacesAndNewlines) })?.isEmpty == false else { return .failure(.unusable) }
        let ttl = plan["ttl"]?.intValue
        if let ttl, !ExtensionPlanRules.ttls.contains(ttl) { return .failure(.unusable) }
        let perDay = plan["per_day"]?.intValue ?? ExtensionPlanRules.defaultPerDay
        guard ExtensionPlanRules.perDays.contains(perDay) else { return .failure(.unusable) }
        let perRun = plan["per_run"]?.intValue
        if let perRun, !ExtensionPlanRules.perRuns.contains(perRun) { return .failure(.unusable) }

        let firstParty = rt.pin.origin?.firstParty == true
        let context = ExtensionPlanRules.Context(firstParty: firstParty, mayPassToServers: flow.mayPassToServers)
        // Only a signed extension is taken at its word about where its own values come from.
        let inside: Set<String> = firstParty ? Set((plan["inside"]?.arrayValue ?? []).compactMap(\.stringValue).filter(Self.isName)) : []
        let who = owner(rt)

        var lines: [PlanEvaluation.Line] = [], rows: [Int] = []
        var earlier: [(name: String?, tool: String)] = [], named = Set<String>(), definitions: [String: String] = [:]
        for raw in rawSteps {
            // A name that can't be read as one is refused, not dropped: dropped, a step would answer to nothing and a slot could point at the wrong one.
            if let given = raw["as"], given.stringValue.map(Self.isName) != true { return .failure(.unusable) }
            let name = raw["as"]?.stringValue
            // A step's name is how later steps point at it, and the host reads it first: one name twice, or one the host reads as the clock, would let words
            // from outside pass for the person's own.
            if let name, !named.insert(name).inserted || ExtensionPlanRules.reservedNames.contains(name) { return .failure(.unusable) }
            let title = raw["title"]?.stringValue.map { ExtensionText.line($0, characters: 80) }.flatMap { $0.isEmpty ? nil : $0 }
            var line: PlanEvaluation.Line
            if let kind = raw["kind"]?.stringValue {
                // A step with no tool of Sidefolk's behind it: it is read, never run by the host (D186). Only a signed extension's word for what it does is put
                // under Sidefolk's own headings.
                guard firstParty else { return .failure(.unusable) }
                switch kind {
                case "ai":
                    let reads = raw["reads"]?.arrayValue?.compactMap(\.stringValue).filter(Self.isName).nonEmptyList
                    var step = ExtensionPlan.Step(tool: "", input: .object([:]), definition: "", reach: "", standing: false, name: name, kind: kind, title: title, reads: reads)
                    step.feeds = ["*": Self.fingerprint(reads.map { names in lines.filter { names.contains($0.step.name ?? "\u{0}") } } ?? lines)]
                    line = .init(step: step, tool: nil, verdict: .init())
                case "flow":
                    guard let other = raw["name"]?.stringValue.map({ ExtensionText.line($0, characters: 80) }), !other.isEmpty else { return .failure(.unusable) }
                    line = .init(step: ExtensionPlan.Step(tool: "", input: ["name": .string(other)], definition: "", reach: "", standing: false, name: name, kind: kind, title: title),
                                 tool: nil, verdict: .init())
                default: return .failure(.unusable)
                }
            } else {
                guard let toolName = raw["tool"]?.stringValue, let input = raw["input"], input.objectValue != nil, let tool = gateway.tool(named: toolName, for: id) else {
                    return .failure(.unknownTool)
                }
                var fromPerson: Set<String> = []
                if firstParty { for (field, who) in raw["from"]?.objectValue ?? [:] where ["person", "clock"].contains(who.stringValue ?? "") { fromPerson.insert(field) } }
                let sources = ExtensionPlanRules.sources(of: input, earlier: earlier, inside: inside, fromPerson: fromPerson)
                let open = ExtensionActionPolicy.fillable[tool.spec.name] ?? []
                let ext = ExtensionPlanRules.extensionTool(tool)
                // Off this actor: the first look at a large program is a long read.
                let command = ext?.program, arguments = ext?.programArguments ?? []
                let program = await command.asyncMap { path in await Task.detached { ProgramPin.hash(of: path, arguments: arguments) }.value } ?? nil
                let verdict = ExtensionPlanRules.verdict(tool: tool, template: input, sources: sources.filter { !open.contains($0.key) }, pinned: ext?.sandboxed != false || program != nil, context: context)
                let definition = definitions[tool.spec.name] ?? ExtensionPlanRules.definition(tool.spec)
                definitions[tool.spec.name] = definition
                var step = ExtensionPlan.Step(tool: tool.spec.name, input: input, definition: definition,
                                              reach: ExtensionPlanRules.reach(tool.scope(for: input)), standing: verdict.stands, provider: ExtensionPlanRules.provider(tool),
                                              name: name, sources: sources.nonEmpty, fullAccessOnly: verdict.fullAccessOnly ? true : nil,
                                              program: verdict.stands ? program : nil)
                step.title = title
                step.feeds = Self.feeds(of: input, tool: tool.spec.name, earlier: lines)
                line = .init(step: step, tool: tool, verdict: verdict)
            }
            if let seen = lines.firstIndex(where: { $0.step == line.step }) {
                rows.append(seen)
            } else {
                lines.append(line)
                rows.append(lines.count - 1)
                earlier.append((line.step.name, line.step.tool))
            }
        }
        guard lines.count <= ExtensionPlanRules.maxSteps else { return .failure(.unusable) }
        Self.markCrossing(&lines)

        let title = ExtensionText.line(plan["title"]?.stringValue ?? "", characters: 80)
        let when = ExtensionText.line(plan["when"]?.stringValue ?? "", characters: 600)
        let round = plan["goes_round"]?.boolValue == true || (plan["goes_round"]?.intValue ?? 0) > 0
        var candidate = ExtensionPlan(id: planId, title: title, when: when, steps: lines.map(\.step), owner: who, approvedAt: Date(),
                                      expiresAt: ttl.map { Date().addingTimeInterval(Double($0)) }, perDay: perDay, perRun: perRun, ttl: ttl, goesRound: round ? true : nil)
        // The plan standing now, read after the last await above: it is what the candidate is compared with.
        let previous = runtimes[id]?.preferences.plans[planId].flatMap { $0.live(at: Date(), owner: who) ? $0 : nil }
        // What nobody read (Full access answered it with no card) is not a plan the person read, in any mode: an edit of it shows the whole card, or Full
        // access answers it again for the person's own click.
        let read = previous.flatMap { $0.answeredUnread == true ? nil : $0 }
        let crossing = lines.contains { $0.verdict.warning != nil }
        candidate.crossing = crossing ? true : nil
        var fresh = Array(lines.indices), widened = false
        if let read {
            fresh = lines.indices.filter { i in !read.steps.contains { ExtensionPlanRules.covers($0, lines[i].step) } }
            // A plan that now reads private things and outside words and fills a server line from them: those lines are new, however they stood before.
            if crossing, read.crossing != true { fresh = Array(Set(fresh).union(lines.indices.filter { lines[$0].verdict.warning != nil })).sorted() }
            widened = ExtensionPlanRules.widened(read, to: candidate)
        }
        let intent = plan["intent"]?.stringValue.flatMap { ["run", "turn_on"].contains($0) ? $0 : nil }
        return .success(PlanEvaluation(lines: lines, rows: rows, plan: candidate, previous: read, fresh: fresh, widened: widened, intent: intent, askOnline: askOnline, mode: flow.mode))
    }

    enum PlanRefusal: String, Error {
        case unusable
        case unknownTool = "unknown_tool"
    }

    private static func isName(_ text: String) -> Bool { text.range(of: nameShape, options: .regularExpression) != nil }

    /// A flow that reads the person's own things and outside words, and fills a line for a server or another extension from what it reads, is where a
    /// stranger's page could take private words to that place unattended. The destination is written (or the line asks, or stands only in Full access),
    /// so the page doesn't choose where they go: the card says it in plain words, naming the server, and the person's switch turns it back to asking
    /// (D189, T53). Worked out from the whole plan, and conservative. An AI step reads what it names, or everything before it when it names nothing.
    static func markCrossing(_ lines: inout [PlanEvaluation.Line]) {
        func privateRead(_ tool: any Tool) -> Bool {
            let spec = tool.spec
            // A server or another extension's tool may hold the person's own things (mail, a calendar), and a server's own word that it only writes is not
            // taken (an MCP tool's `mutates` is never known): the host can't tell, so it says so.
            if ExtensionPlanRules.extensionTool(tool) != nil { return true }
            return spec.name == CompanionJobTool.name || ["reminders.list", "applereminders.list"].contains(spec.name)
                || (!spec.mutates && !spec.capabilities.isDisjoint(with: [.notebook, .memory, .calendar, .clipboard, .filesRead, .macApps]))
        }
        func outsideRead(_ tool: any Tool) -> Bool {
            // A job for the companion reads what it likes, pages included, and writes what it hands on.
            ExtensionPlanRules.extensionTool(tool) != nil || tool.spec.capabilities.contains(.network) || tool.spec.name == CompanionJobTool.name
        }
        // For each line that hands words to a server or another extension: do the steps BEFORE it read the person's own things and outside content? (What
        // comes after can't feed it, and the line itself isn't its own reading.)
        for i in lines.indices {
            guard let tool = lines[i].tool, ExtensionPlanRules.extensionTool(tool) != nil, lines[i].step.standing,
                  (lines[i].step.sources ?? [:]).values.contains("outside") else { continue }
            var privately = false, outside = false
            for line in lines[..<i] {
                if let before = line.tool {
                    privately = privately || privateRead(before)
                    outside = outside || outsideRead(before)
                } else if line.step.kind == "ai" {
                    guard let reads = line.step.reads else { privately = true; outside = true; continue }
                    for named in lines[..<i] where named.tool != nil && reads.contains(named.step.name ?? "\u{0}") {
                        privately = privately || privateRead(named.tool!)
                        outside = outside || outsideRead(named.tool!)
                    }
                }
            }
            if privately, outside { lines[i].verdict.warning = "crossing" }
        }
    }
}

private extension Dictionary {
    var nonEmpty: Self? { isEmpty ? nil : self }
}

extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let value = self else { return nil }
        return await transform(value)
    }
}

extension ExtensionHost {
    /// A fingerprint of the steps a value or an AI step is fed by: each one as written (its name, tool, provider, definition, kind, what an AI step reads, and its input).
    static func fingerprint(_ lines: [PlanEvaluation.Line]) -> String {
        // The whole step as written, name included: which words a name points at is what this fingerprints, so two steps of one tool that trade names differ.
        let text = lines.map { line -> String in
            "\(line.step.name ?? "")|\(line.step.tool)|\(line.step.provider ?? "")|\(line.step.definition)|\(line.step.kind ?? "")|\((line.step.reads ?? ["*"]).joined(separator: ","))|\(line.step.input.jsonString)"
        }.joined(separator: "\n")
        return ExtensionHash.sha256(Data(text.utf8))
    }

    /// For each field a step fills in, a fingerprint of the earlier steps its slots name (a name no step makes stands for itself).
    static func feeds(of template: JSONValue, tool: String, earlier: [PlanEvaluation.Line]) -> [String: String]? {
        var out: [String: String] = [:]
        // Not the table's text fields: those stay inside Sidefolk, and their words may change (D187).
        let open = ExtensionActionPolicy.fillable[tool] ?? []
        for (key, value) in template.objectValue ?? [:] {
            guard !open.contains(key), let text = value.stringValue, ExtensionPlanRules.hasSlot(text) else { continue }
            let roots = Set(ExtensionPlanRules.roots(text)).sorted()
            let named = roots.flatMap { root in earlier.filter { $0.step.name == root } }
            let unplaced = roots.filter { root in !earlier.contains { $0.step.name == root } }
            out[key] = fingerprint(named) + unplaced.joined(separator: ",")
        }
        return out.isEmpty ? nil : out
    }
}

private extension Array {
    /// The list, or nothing for an empty one (an AI step that names no steps reads everything before it).
    var nonEmptyList: [Element]? { isEmpty ? nil : self }
}
