import Synchronization
import Foundation

/// An extension using Sidefolk's tools through Guard (`permissions.act`, D110): the list, Guard's answer without running, a call, and
/// plans the person read so exactly that needs no more cards. Everything runs through `ExtensionActionGateway`; each answer goes back
/// to this program alone, as a notice, because a program never sends the host a request (MCPClient).
extension ExtensionHost {
    /// Calls a minute per extension: each is a row in History, and maybe a card.
    private static let callsPerMinute = 60

    func handleAction(_ id: String, method: String, params: JSONValue) async {
        guard let rt = runtimes[id], rt.record.enabled, rt.record.kind == .sidefolk, rt.pin.permissions?.act != nil,
              let gateway = configuration.actions, let client = rt.client else {
            await runtimes[id]?.client?.notify(Self.answerMethod(method), params: ["request": params["request"] ?? .null, "ok": false, "reason": "off"])
            return
        }
        let request = params["request"] ?? .null
        switch method {
        case "sidefolk/tools.list":
            let tools = gateway.tools(for: id).map(Self.listed)
            await client.notify("sidefolk/tools.listed", params: ["request": request, "ok": true, "tools": .array(tools), "plans": .array(livePlans(id).map(Self.listed))])
        case "sidefolk/tools.check":
            guard let tool = params["tool"]?.stringValue, let input = params["input"], input.objectValue != nil else {
                await client.notify("sidefolk/tools.checked", params: ["request": request, "ok": false, "reason": "unusable"])
                return
            }
            let standing = await standing(id, tool: tool, input: input, plan: params["plan"]?.stringValue, counting: false, gateway: gateway) != nil
            guard let check = await gateway.check(tool, input: input, extensionId: id, standing: standing) else {
                await client.notify("sidefolk/tools.checked", params: ["request": request, "ok": false, "reason": "unknown"])
                return
            }
            var reply: [String: JSONValue] = ["request": request, "ok": true, "decision": .string(check.decision.rawValue), "summary": .string(check.summary),
                                              "risk": .string(check.risk.rawValue), "mutates": .bool(check.mutates), "standing": .bool(standing)]
            if let why = check.why { reply["why"] = .string(why) }
            if let share = check.share { reply["share"] = ["path": .string(share.path), "write": .bool(share.write)] }
            await client.notify("sidefolk/tools.checked", params: .object(reply))
        case "sidefolk/tools.call":
            guard let asked = params["tool"]?.stringValue, let input = params["input"], input.objectValue != nil else {
                await client.notify("sidefolk/tools.result", params: ["request": request, "ok": false, "status": "failed", "text": "That call wasn't usable."])
                return
            }
            // By its one real name: a tool also answers to the name a model knows it by, and what's checked below goes by this.
            let tool = gateway.tool(named: asked, for: id)?.spec.name ?? asked
            let now = Date()
            let recent = (runtimes[id]?.actionCalls ?? []).filter { now.timeIntervalSince($0) < 60 }
            guard recent.count < Self.callsPerMinute else {
                runtimes[id]?.actionCalls = recent
                await client.notify("sidefolk/tools.result", params: ["request": request, "ok": false, "status": "busy", "text": "Too many actions in a minute."])
                return
            }
            runtimes[id]?.actionCalls = recent + [now]
            // Nothing to call: an extension off or removed, a server gone. The caller may wait for it, which it can't if this reads as a no.
            guard gateway.tool(named: tool, for: id) != nil else {
                await client.notify("sidefolk/tools.result", params: ["request": request, "ok": false, "status": "unavailable", "text": "That tool isn't here now."])
                return
            }
            // A job uses the person's AI: only with leave to, and it counts toward the same day's cap.
            if tool == CompanionJobTool.name, let why = await spendOnAI(id) {
                await client.notify("sidefolk/tools.result", params: ["request": request, "ok": false, "status": "denied", "text": .string(why)])
                return
            }
            let timeout = params["timeout"]?.doubleValue.map { min(max($0, 1), 600) }
            let step = await standing(id, tool: tool, input: input, plan: params["plan"]?.stringValue, counting: true, gateway: gateway)
            let standing = step != nil
            // A plan's step as written, or the program's word for a call it filled in without one (a run from a draft): checked against
            // what it sent, and only where the closed table leaves words open. All it can do is keep those words out of History (D127).
            let template = step ?? params["written"].flatMap { ExtensionPlanRules.readable(written: $0, for: input) ? .some($0) : .none }
            let filled = template.map { ExtensionPlanRules.fillsIn($0) && ExtensionPlanRules.matches(input, template: $0, fillable: ExtensionActionPolicy.fillable[tool] ?? []) } == true
            let written = filled ? template : nil
            let asker = asker(rt)
            begin(id)
            // Off this actor: a card can wait two minutes, and everything else this host does waits for nothing of that.
            let key = request.stringValue ?? UUID().uuidString
            let keptFrom = Self.hearsOnlyThatItsDone(tool: tool, permissions: rt.pin.permissions)
            runtimes[id]?.actionTasks[key] = Task { [weak self] in
                let following = keptFrom ? nil : ExtensionHost.following(request: request, client: client)
                let outcome = await ToolProgress.$report.withValue(following) {
                    await gateway.call(tool, input: input, extensionId: id, asker: asker, standing: standing, written: written, timeout: timeout)
                }
                await self?.finishAction(id, request: request, standing: standing, outcome: outcome, tool: tool, key: key)
            }
        case "sidefolk/tools.cancel":
            // Told, not done: it says so by answering, and that answer can only say it may or may not have happened.
            if let key = params["request"]?.stringValue { runtimes[id]?.actionTasks[key]?.cancel() }
        case "sidefolk/plan.approve":
            await approvePlan(id, request: request, params: params, gateway: gateway)
        case "sidefolk/plan.forget":
            if let plan = params["plan"]?.stringValue { await updatePreferences(id) { $0.plans[plan] = nil } }
            events.changed(.extensions)
        default:
            break
        }
    }

    /// Why a job can't be paid for, or nil once it's counted.
    private func spendOnAI(_ id: String) async -> String? {
        guard let rt = runtimes[id], let ai = rt.pin.permissions?.ai, rt.preferences.aiOn != false, configuration.aiName() != nil, configuration.aiHeldBack() == nil else { return "A job uses the person's AI, and this extension hasn't been given it." }
        let today = AIHelper.dayKey(Date())
        guard rt.preferences.calls(on: today) < ai.dailyCap else { return "Today's AI requests are used up." }
        await updatePreferences(id) { p in
            p.aiCalls = p.calls(on: today) + 1
            p.aiDay = today
        }
        events.changed(.extensions)
        return nil
    }

    /// A job that never ran cost nothing: "Not now" doesn't use up the day's AI requests.
    private func refundAI(_ id: String, tool: String) async {
        guard tool == CompanionJobTool.name else { return }
        let today = AIHelper.dayKey(Date())
        await updatePreferences(id) { p in
            if p.calls(on: today) > 0 { p.aiCalls = p.calls(on: today) - 1 }
        }
    }

    /// What the companion found may be anything of theirs: an extension that could carry it off hears only that it's done, and nothing on the way.
    static func hearsOnlyThatItsDone(tool: String, permissions: ExtensionPermissions?) -> Bool {
        tool == CompanionJobTool.name && !(permissions ?? ExtensionPermissions()).isContained
    }

    /// Passes on how far along a call is: its own words, cleaned, at most once a second. It's only ever heard by the program that made the call.
    private static func following(request: JSONValue, client: MCPClient) -> ToolProgress.Report {
        let last = Mutex(Date.distantPast)
        return { progress, total, message in
            let due = last.withLock { at -> Bool in
                guard Date().timeIntervalSince(at) >= 1 else { return false }
                at = Date()
                return true
            }
            guard due else { return }
            var params: [String: JSONValue] = ["request": request]
            if let progress, progress.isFinite { params["progress"] = .number(progress) }
            if let total, total.isFinite { params["total"] = .number(total) }
            if let message { params["message"] = .string(ExtensionText.line(message, characters: 120)) }
            Task { await client.notify("sidefolk/tools.progress", params: .object(params)) }
        }
    }

    private func finishAction(_ id: String, request: JSONValue, standing: Bool, outcome: ToolOutcome, tool: String = "", key: String? = nil) async {
        end(id)
        if let key { runtimes[id]?.actionTasks[key] = nil }
        let summary = ToolFormat.oneLine(ExtensionText.clean(outcome.activity.summary), 240)
        var reply: [String: JSONValue] = ["request": request, "summary": .string(summary), "standing": .bool(standing), "undoable": .bool(outcome.activity.undoAvailable)]
        switch outcome.status {
        case .ok(let result):
            reply["ok"] = .bool(!result.isError)
            reply["status"] = .string(result.isError ? "error" : "ok")
            let carries = Self.hearsOnlyThatItsDone(tool: tool, permissions: runtimes[id]?.pin.permissions)
            reply["text"] = .string(carries ? "Done." : result.text)
            if !carries, let data = result.data { reply["data"] = data }
            reply["untrusted"] = .bool(result.untrusted)
        case .denied(let why):
            await refundAI(id, tool: tool)
            reply["ok"] = false
            reply["status"] = "denied"
            reply["text"] = .string(why)
        case .failed(let error):
            reply["ok"] = false
            reply["status"] = "failed"
            reply["text"] = .string(error.message)
            if error.notFound { reply["not_found"] = true }
        case .unanswered:
            await refundAI(id, tool: tool)
            reply["ok"] = false
            reply["status"] = "unanswered"
            reply["text"] = .string(outcome.problem?.message ?? "")
        }
        await runtimes[id]?.client?.notify("sidefolk/tools.result", params: .object(reply))
    }

    private static func answerMethod(_ method: String) -> String {
        switch method {
        case "sidefolk/tools.list": "sidefolk/tools.listed"
        case "sidefolk/tools.check": "sidefolk/tools.checked"
        case "sidefolk/plan.approve": "sidefolk/plan.result"
        default: "sidefolk/tools.result"
        }
    }

    private static func listed(_ tool: any Tool) -> JSONValue {
        let spec = tool.spec
        var out: [String: JSONValue] = ["reads_only": .bool(ExtensionActionPolicy.readsOnly(tool)), "name": .string(spec.name), "title": .string(spec.title), "description": .string(spec.description), "schema": spec.inputSchema,
                                        "risk": .string(spec.risk.rawValue), "mutates": .bool(spec.mutates), "category": .string(spec.category.rawValue)]
        if let output = spec.outputSchema { out["output_schema"] = output }
        if spec.name.hasPrefix("ext.") { out["extension"] = .string(String(spec.name.dropFirst(4).prefix { $0 != "." })) }
        // Who offers it, in that extension's or server's own words: for the person, so a caller can name what it's missing.
        if let from = ((tool as? ExternalFacade)?.base ?? tool) as? ExtensionTool {
            out["extension_title"] = .string(from.extensionName)
            if from.extensionId.hasPrefix("mcp.") { out["from_server"] = true }
        }
        return .object(out)
    }

    private static func listed(_ plan: ExtensionPlan) -> JSONValue {
        var out: [String: JSONValue] = ["id": .string(plan.id), "title": .string(plan.title),
                                        "standing": .array(plan.steps.map { .bool($0.standing) })]
        if let ends = plan.expiresAt { out["expires_at"] = .number(ends.timeIntervalSince1970) }
        return .object(out)
    }

    private func asker(_ rt: Runtime) -> ApprovalRequest.Asker {
        ApprovalRequest.Asker(name: name(rt), firstParty: rt.pin.origin?.firstParty == true)
    }

    // MARK: Plans

    /// The person's click or typed command to this extension, or a clean request of Sidefolk's own agent: only just after one may it ask
    /// for a plan (T3). Called by its tools (`ExtensionTool.began`).
    func notePersonCall(_ id: String, caller: Caller, tainted: Bool) {
        switch caller {
        case .user, .command: runtimes[id]?.lastPersonCall = Date()
        case .agent(let run) where !tainted && !run.hasPrefix(AgentRuntime.jobPrefix): runtimes[id]?.lastPersonCall = Date()
        default: break
        }
    }

    /// Who a plan was allowed for.
    private func owner(_ rt: Runtime) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let permissions = (try? encoder.encode(rt.pin.permissions ?? ExtensionPermissions())) ?? Data()
        return ExtensionHash.sha256(permissions + Data("\(rt.pin.origin.map { "\($0)" } ?? "none")".utf8))
    }

    private func livePlans(_ id: String, now: Date = Date()) -> [ExtensionPlan] {
        guard let rt = runtimes[id] else { return [] }
        let owner = owner(rt)
        return rt.preferences.plans.values.filter { $0.live(at: now, owner: owner) }.sorted { $0.id < $1.id }
    }

    /// The plans Settings › Add-ons lists.
    func planInfos(_ id: String) -> [ExtensionPlanInfo] {
        livePlans(id).map {
            ExtensionPlanInfo(id: $0.id, title: $0.title, when: $0.when, actions: $0.steps.filter(\.standing).count, approvedAt: $0.approvedAt, expiresAt: $0.expiresAt)
        }
    }

    /// The person ended it; its program hears, so it can say so.
    func endPlan(extensionId id: String, plan: String) async {
        guard runtimes[id]?.preferences.plans[plan] != nil else { return }
        await updatePreferences(id) { $0.plans[plan] = nil }
        await runtimes[id]?.client?.notify("sidefolk/plan.ended", params: ["plan": .string(plan)])
        events.changed(.extensions)
    }

    /// The step of a live plan this call fits, as it was written; nil when it fits none, and it asks.
    private func standing(_ id: String, tool name: String, input: JSONValue, plan: String?, counting: Bool, gateway: ExtensionActionGateway) async -> JSONValue? {
        guard let rt = runtimes[id], let plan, let saved = rt.preferences.plans[plan], saved.live(at: Date(), owner: owner(rt)),
              (rt.pin.permissions ?? ExtensionPermissions()).isContained, ExtensionPlanRules.short(input), let tool = gateway.tool(named: name, for: id) else { return nil }
        let definition = ExtensionPlanRules.definition(tool.spec), reach = ExtensionPlanRules.reach(tool.scope(for: input))
        let provider = ExtensionPlanRules.provider(tool)
        let fillable = ExtensionActionPolicy.fillable[tool.spec.name] ?? []
        let fits = saved.steps.first { step in
            step.standing && step.tool == tool.spec.name && step.definition == definition && (step.provider ?? "") == provider
                && ExtensionPlanRules.same(step.reach, reach)
                && ExtensionPlanRules.matches(input, template: step.input, fillable: fillable)
        }
        guard let fits else { return nil }
        // "Ask each time" for the internet is the person's word for every page, whoever asks (D47).
        if tool.spec.capabilities.contains(.network), await configuration.askEachTimeOnline() { return nil }
        guard counting else { return fits.input }
        // Read after the wait above, and kept: a burst, or a restart, doesn't buy a new budget.
        let day = AIHelper.dayKey(Date()), used = runtimes[id]?.preferences.planCalls[plan]
        let count = used?.day == day ? used?.count ?? 0 : 0
        guard count < saved.perDay else { return nil }
        await updatePreferences(id) { $0.planCalls[plan] = ExtensionPreferences.PlanCount(day: day, count: count + 1) }
        return fits.input
    }

    private func approvePlan(_ id: String, request: JSONValue, params: JSONValue, gateway: ExtensionActionGateway) async {
        func refuse(_ reason: String) async {
            await runtimes[id]?.client?.notify("sidefolk/plan.result", params: ["request": request, "ok": false, "reason": .string(reason)])
        }
        guard let rt = runtimes[id], let plan = params["plan"] else { return await refuse("unusable") }
        // One card at a time for a plan: what the person is reading is what is saved.
        guard !rt.planAsking else { return await refuse("busy") }
        guard (rt.pin.permissions ?? ExtensionPermissions()).isContained else { return await refuse("not_contained") }
        guard Date().timeIntervalSince(rt.lastPersonCall) <= ExtensionPlanRules.personWindow else { return await refuse("not_asked") }
        guard let planId = plan["id"]?.stringValue, planId.range(of: #"^[A-Za-z0-9._:-]{1,64}$"#, options: .regularExpression) != nil,
              let rawSteps = plan["steps"]?.arrayValue, (0...ExtensionPlanRules.maxSteps).contains(rawSteps.count) else { return await refuse("unusable") }
        // No action to allow is still something to read when `when` says what it sets off. With nothing to say at all there's no card to show.
        guard !rawSteps.isEmpty || plan["when"]?.stringValue.map({ ExtensionText.clean($0).trimmingCharacters(in: .whitespacesAndNewlines) })?.isEmpty == false else { return await refuse("unusable") }
        let ttl = plan["ttl"]?.intValue
        if let ttl, !ExtensionPlanRules.ttls.contains(ttl) { return await refuse("unusable") }
        let perDay = plan["per_day"]?.intValue ?? ExtensionPlanRules.defaultPerDay
        guard ExtensionPlanRules.perDays.contains(perDay) else { return await refuse("unusable") }

        let owner = owner(rt)
        let previous = rt.preferences.plans[planId].flatMap { $0.live(at: Date(), owner: owner) ? $0 : nil }
        var steps: [ExtensionPlan.Step] = [], lines: [(text: String, standing: Bool, new: Bool)] = []
        for raw in rawSteps {
            guard let name = raw["tool"]?.stringValue, let input = raw["input"], input.objectValue != nil, let tool = gateway.tool(named: name, for: id) else {
                return await refuse("unknown_tool")
            }
            let stands = ExtensionPlanRules.standing(tool: tool, template: input)
            let step = ExtensionPlan.Step(tool: tool.spec.name, input: input, definition: ExtensionPlanRules.definition(tool.spec),
                                          reach: ExtensionPlanRules.reach(tool.scope(for: input)), standing: stands,
                                          provider: ExtensionPlanRules.provider(tool))
            guard !steps.contains(step) else { continue }
            steps.append(step)
            let seen = previous?.steps.contains { $0.tool == step.tool && $0.input == step.input && $0.provider == step.provider } ?? false
            lines.append((ExtensionPlanWords.line(tool: tool, template: input), stands, previous != nil && !seen))
        }
        let title = ExtensionText.line(plan["title"]?.stringValue ?? "", characters: 80)
        let when = ExtensionText.line(plan["when"]?.stringValue ?? "", characters: 600)
        let body = ExtensionPlanWords.body(name: name(rt), lines: lines, when: when, perDay: perDay, ttl: ttl, revised: previous != nil, holdsJob: steps.contains { $0.tool == CompanionJobTool.name })
        let card = ExtensionPlanTool(extensionId: id, plan: title.isEmpty ? planId : title, when: when, body: body)
        let asker = asker(rt)
        runtimes[id]?.planAsking = true
        Task { [weak self] in
            let outcome = await gateway.askForPlan(card, input: ["extension": .string(id), "plan": .string(planId)], extensionId: id, asker: asker)
            await self?.finishPlan(id, request: request, outcome: outcome, plan: ExtensionPlan(
                id: planId, title: title, when: when, steps: steps, owner: "", approvedAt: Date(),
                expiresAt: ttl.map { Date().addingTimeInterval(Double($0)) }, perDay: perDay))
        }
    }

    private func finishPlan(_ id: String, request: JSONValue, outcome: ToolOutcome, plan: ExtensionPlan) async {
        runtimes[id]?.planAsking = false
        guard outcome.isOK, let rt = runtimes[id] else {
            let reason = if case .unanswered = outcome.status { "unanswered" } else { "denied" }
            await runtimes[id]?.client?.notify("sidefolk/plan.result", params: ["request": request, "ok": false, "reason": .string(reason)])
            return
        }
        var plan = plan
        plan.owner = owner(rt)
        await updatePreferences(id) { $0.plans[plan.id] = plan }
        events.changed(.extensions)
        await runtimes[id]?.client?.notify("sidefolk/plan.result", params: ["request": request, "ok": true, "plan": .string(plan.id),
                                                                             "standing": .array(plan.steps.map { .bool($0.standing) })])
    }

    // MARK: Its own watches

    /// Something happened: those with `permissions.events` hear it, with its words, whatever else they can reach: the founder's choice (D129).
    func tell(_ happening: Happening) async {
        // One id for one happening, whoever hears it and however often: telling something twice mustn't make it happen twice.
        let id = UUID().uuidString
        for rt in runtimes.values where rt.record.enabled && rt.pin.permissions?.events != nil {
            var params: [String: JSONValue] = ["id": .string(id), "name": .string(happening.name), "at": .number(Date().timeIntervalSince1970)]
            if let title = happening.title { params["title"] = .string(ExtensionText.line(title, characters: 200)) }
            if let detail = happening.detail { params["detail"] = .string(ExtensionText.untrusted(detail, bytes: 2_000)) }
            await rt.client?.notify("sidefolk/happened", params: .object(params))
        }
    }

    /// Whether anyone is listening, so nothing is looked up for nobody.
    public var hearsHappenings: Bool { runtimes.values.contains { $0.record.enabled && $0.pin.permissions?.events != nil } }

    /// A watch this extension made fired: it hears, not the person (`WatcherEngine.announce`). The words are the page's or the file's.
    func tellWatchFired(extensionId id: String, watch: String, title: String, summary: String) async {
        guard let rt = runtimes[id], rt.record.enabled, rt.pin.permissions?.act != nil else { return }
        await rt.client?.notify("sidefolk/watch.fired", params: ["watch": .string(watch), "title": .string(ExtensionText.line(title, characters: 80)),
                                                                  "summary": .string(ExtensionText.untrusted(summary, bytes: 2_000))])
    }
}
