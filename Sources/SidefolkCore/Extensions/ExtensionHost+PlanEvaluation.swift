import Foundation

/// What a plan an extension sends comes to, worked out by the host and never by the program: which steps stand and how, which are new since the
/// plan the person read, and whether the terms are wider (D186, D187). `plan.approve` shows a card from it, or none; `plan.check` only says it.
struct PlanEvaluation {
    struct Line {
        var step: ExtensionPlan.Step
        /// The tool behind it, nil for a step the host doesn't run (an AI step, another flow).
        var tool: (any Tool)?
        var verdict: ExtensionPlanRules.Verdict
        /// The step as written (name, tool, provider, definition, kind, what an AI step reads, input), hashed once: what a fingerprint of the steps
        /// that feed another is made of, so working one out never reads a large input again.
        let digest: String

        init(step: ExtensionPlan.Step, tool: (any Tool)?, verdict: ExtensionPlanRules.Verdict) {
            self.step = step
            self.tool = tool
            self.verdict = verdict
            let text = "\(step.name ?? "")|\(step.tool)|\(step.provider ?? "")|\(step.definition)|\(step.kind ?? "")|\((step.reads ?? ["*"]).joined(separator: ","))|\(step.input.jsonString)"
            digest = ExtensionHash.sha256(Data(text.utf8))
        }
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
        var earlier: [(name: String?, tool: String, kind: String?, reads: [String]?)] = [], named = Set<String>(), definitions: [String: String] = [:]
        for raw in rawSteps {
            // A name that can't be read as one is refused, not dropped: dropped, a step would answer to nothing and a slot could point at the wrong one.
            if let given = raw["as"], given.stringValue.map(Self.isName) != true { return .failure(.unusable) }
            let name = raw["as"]?.stringValue
            // A step's name is how later steps point at it, and the host reads it first: one name twice, or one the host reads as the clock, would let words
            // from outside pass for the person's own.
            if let name, !named.insert(name).inserted || ExtensionPlanRules.reservedNames.contains(name.lowercased()) { return .failure(.unusable) }
            let title = raw["title"]?.stringValue.map { ExtensionPlanRules.visible(ExtensionText.line($0, characters: 80)) }.flatMap { $0.isEmpty ? nil : $0 }
            var line: PlanEvaluation.Line
            if let kind = raw["kind"]?.stringValue {
                // A step with no tool of Sidefolk's behind it: it is read, never run by the host (D186). Only a signed extension's word for what it does is put
                // under Sidefolk's own headings.
                guard firstParty else { return .failure(.unusable) }
                switch kind {
                case "ai":
                    guard let reads = Self.reads(raw["reads"], required: false) else { return .failure(.unusable) }
                    var step = ExtensionPlan.Step(tool: "", input: .object([:]), definition: "", reach: "", standing: false, name: name, kind: kind, title: title, reads: reads)
                    step.feeds = ["*": Self.fingerprint(reads.map { names in Self.closure(of: names, in: lines) } ?? lines)]
                    line = .init(step: step, tool: nil, verdict: .init())
                case "value":
                    // Words passed from step to step with nothing run: never shown, but what it reads decides where later steps' words come from.
                    guard let name, let found = Self.reads(raw["reads"], required: true), let reads = found else { return .failure(.unusable) }
                    var step = ExtensionPlan.Step(tool: "", input: .object([:]), definition: "", reach: "", standing: false, name: name, kind: kind, title: nil, reads: reads)
                    step.feeds = ["*": Self.fingerprint(Self.closure(of: reads, in: lines))]
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
                let sources = ExtensionPlanRules.sources(of: input, steps: earlier, inside: inside, fromPerson: fromPerson)
                let open = ExtensionActionPolicy.fillable[tool.spec.name] ?? []
                let ext = ExtensionPlanRules.extensionTool(tool)
                // Off this actor: the first look at a large program is a long read.
                let command = ext?.program, arguments = ext?.programArguments ?? []
                let checked = await command.asyncMap { path in await Task.detached { ProgramPin.check(of: path, arguments: arguments) }.value }
                var program: String?, unchecked: ProgramPin.Unchecked?
                switch checked {
                case .pinned(let hash)?: program = hash
                case .unchecked(let why)?: unchecked = why
                case nil: break
                }
                var verdict = ExtensionPlanRules.verdict(tool: tool, template: input, sources: sources.filter { !open.contains($0.key) }, pinned: ext?.sandboxed != false || program != nil, context: context)
                if verdict.why == "server_unpinned" { verdict.detail = unchecked?.rawValue }
                let definition = definitions[tool.spec.name] ?? ExtensionPlanRules.definition(tool.spec)
                definitions[tool.spec.name] = definition
                var step = ExtensionPlan.Step(tool: tool.spec.name, input: input, definition: definition,
                                              reach: ExtensionPlanRules.reach(tool.scope(for: input)), standing: verdict.stands, provider: ExtensionPlanRules.provider(tool),
                                              name: name, sources: sources.nonEmpty, fullAccessOnly: verdict.fullAccessOnly ? true : nil,
                                              program: program)
                step.title = title
                step.feeds = Self.feeds(of: input, tool: tool.spec.name, earlier: lines)
                line = .init(step: step, tool: tool, verdict: verdict)
            }
            // The same line is the same bytes: Swift's `==` takes two spellings of one letter for equal.
            if let seen = lines.firstIndex(where: { $0.digest == line.digest && ExtensionPlanRules.same($0.step.title ?? "", line.step.title ?? "") && $0.step == line.step }) {
                rows.append(seen)
            } else {
                lines.append(line)
                rows.append(lines.count - 1)
                earlier.append((line.step.name, line.step.tool, line.step.kind, line.step.reads))
            }
        }
        // At most 64 different lines: the same line again (whatever it is called) is one to read, and the card says so.
        guard lines.count <= ExtensionPlanRules.maxRows, Set(lines.filter { $0.step.kind != "value" }.map { Array(Self.contentKey($0.step).utf8) }).count <= ExtensionPlanRules.maxSteps else { return .failure(.unusable) }
        Self.markCrossing(&lines)

        let title = ExtensionPlanRules.visible(ExtensionText.line(plan["title"]?.stringValue ?? "", characters: 80))
        let when = ExtensionPlanRules.visible(ExtensionText.line(plan["when"]?.stringValue ?? "", characters: 600))
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
            // A line Auto let through without a card was not read either.
            let readSteps = read.steps.filter { $0.answeredInAuto != true }
            fresh = lines.indices.filter { i in !readSteps.contains { $0.tool == lines[i].step.tool && $0.kind == lines[i].step.kind && ExtensionPlanRules.covers($0, lines[i].step) } }
            // A plan that now reads private things and outside words and fills a server line from them: those lines are new, however they stood before.
            if crossing, read.crossing != true { fresh = Array(Set(fresh).union(lines.indices.filter { lines[$0].verdict.warning != nil })).sorted() }
            widened = ExtensionPlanRules.widened(read, to: candidate)
        }
        // A step that only passes words on is never shown, so it is never "new" by itself: what it feeds shows where it is used.
        fresh.removeAll { lines[$0].step.kind == "value" }
        let intent = plan["intent"]?.stringValue.flatMap { ["run", "turn_on"].contains($0) ? $0 : nil }
        return .success(PlanEvaluation(lines: lines, rows: rows, plan: candidate, previous: read, fresh: fresh, widened: widened, intent: intent, askOnline: askOnline, mode: flow.mode))
    }

    enum PlanRefusal: String, Error {
        case unusable
        case unknownTool = "unknown_tool"
    }

    /// The names a step reads: every one a valid name, each once, at most 32. Nothing is dropped quietly (a dropped name could make words look closer than
    /// they are); a list that can't be read as it is makes the plan unusable. The outer nil is that; the inner nil is a step that names nothing.
    static func reads(_ value: JSONValue?, required: Bool) -> [String]?? {
        guard let value else { return required ? nil : .some(nil) }
        guard let items = value.arrayValue, items.count <= 64 else { return nil }
        var out: [String] = []
        for item in items {
            guard let name = item.stringValue, isName(name) else { return nil }
            if !out.contains(name) { out.append(name) }
        }
        guard out.count <= 32 else { return nil }
        if out.isEmpty { return required ? nil : .some(nil) }
        return .some(out)
    }

    private static func isName(_ text: String) -> Bool { text.range(of: nameShape, options: .regularExpression) != nil }

    /// A flow that reads the person's own things and outside words, and fills a line for a server or another extension from what it reads, is where a
    /// stranger's page could take private words to that place unattended. The destination is written (or the line asks, or stands only in Full access),
    /// so the page doesn't choose where they go: the card says it in plain words, naming the server, and the person's switch turns it back to asking
    /// (D189, T53). Worked out from the whole plan, and conservative. An AI step reads what it names, or everything else in the plan when it names nothing.
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
            // A job for the companion reads what it likes, pages included, and writes what it hands on. A file, the clipboard, another app's notes,
            // reminders or calendar hold what others wrote or what was pasted from a page: the Trust text says "a page or a file", and so does this.
            ExtensionPlanRules.extensionTool(tool) != nil || tool.spec.name == CompanionJobTool.name || tool.spec.capabilities.contains(.network)
                || (!tool.spec.mutates && !tool.spec.capabilities.isDisjoint(with: [.filesRead, .clipboard, .calendar, .macApps]))
        }
        // For each line that hands words to a server or another extension: does any OTHER step of the plan read the person's own things and outside content?
        // The order the steps are written in is not the order they are called in, so every step counts (and a line that appears twice is one line). What each
        // step reads is worked out once, and an AI step's named steps are looked up by name, so a large plan is the size of the plan and no more.
        var at: [String: Int] = [:]
        for (i, line) in lines.enumerated() { if line.tool != nil, let name = line.step.name { at[name] = i } }
        let reads: [(privately: Bool, outside: Bool)] = lines.map { line in line.tool.map { (privateRead($0), outsideRead($0)) } ?? (false, false) }
        let named: [[Int]?] = lines.map { line in line.step.kind == "ai" ? line.step.reads.map { $0.compactMap { at[$0] } } : nil }
        for i in lines.indices {
            guard let tool = lines[i].tool, ExtensionPlanRules.extensionTool(tool) != nil, lines[i].step.standing,
                  (lines[i].step.sources ?? [:]).values.contains("outside") else { continue }
            var privately = false, outside = false
            for j in lines.indices where j != i {
                if lines[j].tool != nil {
                    privately = privately || reads[j].privately
                    outside = outside || reads[j].outside
                } else if lines[j].step.kind == "ai" {
                    guard let from = named[j] else { privately = true; outside = true; continue }
                    for k in from where k != i {
                        privately = privately || reads[k].privately
                        outside = outside || reads[k].outside
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
    /// A step without its name, title or what feeds it: what a person reads, to count the lines that differ.
    static func contentKey(_ step: ExtensionPlan.Step) -> String {
        "\(step.tool)|\(step.provider ?? "")|\(step.definition)|\(step.kind ?? "")|\((step.reads ?? []).joined(separator: ","))|\(step.input.jsonString)"
    }

    /// The steps with these names, and the steps whose words they pass on, down to the ones that run something. Each step once, by its name (a name is
    /// never shared): the work is the size of the plan, not of its paths.
    static func closure(of names: [String], in lines: [PlanEvaluation.Line]) -> [PlanEvaluation.Line] {
        var at: [String: Int] = [:]
        for (i, line) in lines.enumerated() { if let name = line.step.name { at[name] = i } }
        var added = Set<Int>(), todo = names
        while let name = todo.popLast() {
            guard let i = at[name], added.insert(i).inserted else { continue }
            let step = lines[i].step
            if step.kind == "value" || step.kind == "ai" { todo.append(contentsOf: step.reads ?? []) }
        }
        return added.sorted().map { lines[$0] }
    }

    /// A fingerprint of the steps a value or an AI step is fed by: each one as written (its name, tool, provider, definition, kind, what an AI step reads, and its input).
    static func fingerprint(_ lines: [PlanEvaluation.Line]) -> String {
        // The whole step as written, name included: which words a name points at is what this fingerprints, so two steps of one tool that trade names differ.
        ExtensionHash.sha256(Data(lines.map(\.digest).joined(separator: "\n").utf8))
    }

    /// For each field a step fills in, a fingerprint of the earlier steps its slots name (a name no step makes stands for itself).
    static func feeds(of template: JSONValue, tool: String, earlier: [PlanEvaluation.Line]) -> [String: String]? {
        var out: [String: String] = [:]
        // Not the table's text fields: those stay inside Sidefolk, and their words may change (D187).
        let open = ExtensionActionPolicy.fillable[tool] ?? []
        for (key, value) in template.objectValue ?? [:] {
            guard !open.contains(key), let text = value.stringValue, ExtensionPlanRules.hasSlot(text) else { continue }
            let roots = Set(ExtensionPlanRules.roots(text)).sorted()
            let named = closure(of: roots, in: earlier)
            let unplaced = roots.filter { root in !earlier.contains { $0.step.name == root } }
            out[key] = fingerprint(named) + unplaced.joined(separator: ",")
        }
        return out.isEmpty ? nil : out
    }
}
