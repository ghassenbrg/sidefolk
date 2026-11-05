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
        await endIdlePlans(id)
        switch method {
        case "sidefolk/tools.list":
            let tools = gateway.tools(for: id).map(Self.listed)
            await client.notify("sidefolk/tools.listed", params: ["request": request, "ok": true, "tools": .array(tools), "plans": .array(livePlans(id).map(Self.listed))])
        case "sidefolk/tools.check":
            guard spendLook(id) else { return await client.notify("sidefolk/tools.checked", params: ["request": request, "ok": false, "reason": "busy"]) }
            guard let tool = params["tool"]?.stringValue, let input = params["input"], input.objectValue != nil else {
                await client.notify("sidefolk/tools.checked", params: ["request": request, "ok": false, "reason": "unusable"])
                return
            }
            let standing = await standing(id, tool: tool, input: input, plan: params["plan"]?.stringValue, run: nil, counting: false, gateway: gateway).step != nil
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
            let run = params["run"]?.stringValue.flatMap { $0.isEmpty || $0.count > 64 ? nil : $0 }
            let found = await standing(id, tool: tool, input: input, plan: params["plan"]?.stringValue, run: run, counting: true, gateway: gateway)
            let step = found.step
            let standing = step != nil
            // A plan's step as written, or the program's word for a call it filled in without one (a run from a draft): checked against
            // what it sent, and only where the closed table leaves words open. All it can do is keep those words out of History (D127).
            let template = step ?? params["written"].flatMap { ExtensionPlanRules.readable(written: $0, for: input) ? .some($0) : .none }
            let filled = template.map { ExtensionPlanRules.fillsIn($0) && ExtensionPlanRules.matches(input, template: $0, fillable: step == nil ? ExtensionActionPolicy.fillable[tool] ?? [] : ExtensionPlanRules.slotKeys($0),
                                                                                       whole: step == nil ? [] : ExtensionPlanRules.wholeKeys($0, tool: tool)) } == true
            // History keeps the step as written, and where its filled words came from.
            var written = filled ? template : nil
            if let prov = found.provenance, var fields = written?.objectValue {
                fields["_filled_from"] = .array(prov.map { .string($0) })
                written = .object(fields)
            }
            let asker = asker(rt)
            let key = request.stringValue ?? UUID().uuidString
            // One call to a request: a program that sends the same one twice would leave the first with nothing to stop it.
            guard runtimes[id]?.actionTasks[key] == nil else {
                await client.notify("sidefolk/tools.result", params: ["request": request, "ok": false, "status": "failed", "text": "That request is already running."])
                return
            }
            // The extension may have been turned off while this was being worked out.
            guard runtimes[id]?.record.enabled == true else { return }
            begin(id)
            // Off this actor: a card can wait two minutes, and everything else this host does waits for nothing of that.
            let keptFrom = Self.hearsOnlyThatItsDone(tool: tool, permissions: rt.pin.permissions)
            let task = Task { [weak self] in
                let following = keptFrom ? nil : ExtensionHost.following(request: request, client: client)
                let outcome = await ToolProgress.$report.withValue(following) {
                    await gateway.call(tool, input: input, extensionId: id, asker: asker, standing: standing, written: written, timeout: timeout, capped: found.capped, unread: found.unread)
                }
                await self?.finishAction(id, request: request, standing: standing, outcome: outcome, tool: tool, capped: found.capped, key: key)
            }
            runtimes[id]?.actionTasks[key] = task
            // A stop that came while this was being worked out (the program's messages are not handled in order) is not lost.
            if runtimes[id]?.takeEarlyCancel(key) == true { task.cancel() }
        case "sidefolk/tools.cancel":
            // Told, not done: it says so by answering, and that answer can only say it may or may not have happened.
            if let key = params["request"]?.stringValue {
                if let task = runtimes[id]?.actionTasks[key] { task.cancel() } else { runtimes[id]?.noteEarlyCancel(key) }
            }
        case "sidefolk/plan.approve":
            await approvePlan(id, request: request, params: params, gateway: gateway)
        case "sidefolk/plan.check":
            guard spendLook(id) else { return await reply(id, request, ["ok": false, "reason": "busy"]) }
            await checkPlan(id, request: request, params: params, gateway: gateway)
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

    private func finishAction(_ id: String, request: JSONValue, standing: Bool, outcome: ToolOutcome, tool: String = "", capped: String? = nil, key: String? = nil) async {
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
            reply["status"] = .string(capped == nil ? "denied" : "capped")
            reply["text"] = .string(why)
            if let capped { reply["limit"] = .string(capped) }
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
        case "sidefolk/plan.check": "sidefolk/plan.checked"
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

    /// One more look or plan in the minute, from a bucket of its own: working a plan out is work on this actor, and nothing is free to ask for in a loop,
    /// but an editor's looks can't use up the calls a flow runs on, nor those the person's own Run.
    private func spend(_ id: String, _ bucket: String, limit: Int) -> Bool {
        let now = Date()
        let recent = (runtimes[id]?.budgets[bucket] ?? []).filter { now.timeIntervalSince($0) < 60 }
        guard recent.count < limit else {
            runtimes[id]?.budgets[bucket] = recent
            return false
        }
        runtimes[id]?.budgets[bucket] = recent + [now]
        return true
    }

    private func spendLook(_ id: String) -> Bool { spend(id, "look", limit: Self.callsPerMinute) }

    private func asker(_ rt: Runtime) -> ApprovalRequest.Asker {
        ApprovalRequest.Asker(name: name(rt), firstParty: rt.pin.origin?.firstParty == true)
    }

    // MARK: Plans

    /// The person's click or typed command to this extension, or a clean request of Sidefolk's own agent: only just after one may it ask
    /// for a plan (T3). Called by its tools (`ExtensionTool.began`).
    func notePersonCall(_ id: String, caller: Caller, tainted: Bool) -> UUID? {
        switch caller {
        case .user:
            // The person's own hand, which only Full access answers a plan for: a clean turn of Sidefolk's agent is not that (D188).
            return click(id)
        case .command(let owner) where owner == id: return click(id)
        case .command: runtimes[id]?.lastPersonCall = Date()
        case .agent(let run) where !tainted && !run.hasPrefix(AgentRuntime.jobPrefix): runtimes[id]?.lastPersonCall = Date()
        default: break
        }
        return nil
    }

    /// A click is kept while its call runs, so a plan that comes with it is answered for it: a button that has returned, or a timer, leaves nothing to
    /// answer another plan with (D188). A call that never returns is cut off by its own timeout.
    private func click(_ id: String) -> UUID? {
        guard runtimes[id] != nil else { return nil }
        let token = UUID(), now = Date()
        runtimes[id]?.noteClick(token, at: now)
        return token
    }

    func endPersonClick(_ id: String, _ click: UUID) {
        runtimes[id]?.personClicks[click] = nil
    }

    /// Who a plan was allowed for.
    func owner(_ rt: Runtime) -> String {
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

    /// When a plan's actions run without asking, for Settings (`ExtensionPlanInfo.Stands`): a plan Full access answered stands in all its lines only in Full access;
    /// a line Auto let through only in Auto; a line marked for Full access only in Full access.
    private static func stands(_ plan: ExtensionPlan) -> ExtensionPlanInfo.Stands {
        if plan.answeredUnread == true { return .fullAccessUnread }
        let full = plan.steps.contains { $0.isInFullAccessOnly }, auto = plan.steps.contains { $0.answeredInAuto == true }
        return full && auto ? .either : full ? .fullAccessSome : auto ? .autoSome : .always
    }

    /// The plans Settings › Add-ons lists.
    func planInfos(_ id: String) -> [ExtensionPlanInfo] {
        // Listing is how the person sees plans: one that has gone idle is ended properly (a row in History, its program told) and not just left out.
        if !idlePlans(id).isEmpty { Task { [weak self] in await self?.endIdlePlans(id) } }
        let today = AIHelper.dayKey(Date())
        let signed = runtimes[id]?.pin.origin?.firstParty == true
        return livePlans(id).map { plan in
            let count = runtimes[id]?.preferences.planCalls[plan.id]
            return ExtensionPlanInfo(id: plan.id, title: plan.title, when: plan.when, actions: plan.steps.filter(\.standing).count, stands: Self.stands(plan),
                                     approvedAt: plan.approvedAt, expiresAt: plan.expiresAt,
                                     card: plan.card ?? "", lastUsed: plan.lastUsed, callsToday: count?.day == today ? count?.count ?? 0 : 0, signed: signed)
        }
    }

    /// The plans nobody has used for 60 days and that have not ended some other way.
    private func idlePlans(_ id: String, now: Date = Date()) -> [ExtensionPlan] {
        guard let rt = runtimes[id] else { return [] }
        let owner = owner(rt)
        return rt.preferences.plans.values.filter { $0.owner == owner && ($0.expiresAt.map { $0 > now } ?? true) && $0.idle(at: now) }.sorted { $0.id < $1.id }
    }

    /// A plan nobody has used for 60 days ends, and its program hears why, so the flow can pause and say so: never silently (D186), and not only when its
    /// program asks something: also when the app starts and when Trust is listed, so an extension that stopped, or was switched off, still leaves its row.
    /// The plans are taken out before anything is awaited, so a second sweep finds none and nothing ends twice.
    func endIdlePlans(_ id: String) async {
        let idle = idlePlans(id)
        guard !idle.isEmpty else { return }
        await updatePreferences(id) { prefs in for plan in idle { prefs.plans[plan.id] = nil } }
        for plan in idle {
            await configuration.actions?.recordPlanEnded(extensionId: id, plan: plan.id, title: plan.title)
            await runtimes[id]?.client?.notify("sidefolk/plan.ended", params: ["plan": .string(plan.id), "reason": "idle"])
        }
        events.changed(.extensions)
    }

    /// The person ended it; its program hears, so it can say so.
    func endPlan(extensionId id: String, plan: String) async {
        guard runtimes[id]?.preferences.plans[plan] != nil else { return }
        await updatePreferences(id) { $0.plans[plan] = nil }
        await runtimes[id]?.client?.notify("sidefolk/plan.ended", params: ["plan": .string(plan)])
        events.changed(.extensions)
    }

    /// What a call comes to against the plans: the step it fits, as written; or that a limit stopped it; or neither, and it asks.
    struct Standing {
        var step: JSONValue?
        /// The plan's own limit for today or for this run, reached: nothing is asked, the call is refused and the program says so (D189).
        var capped: String?
        /// The plan or the line was never read on a card (Full access or Auto let it through).
        var unread = false
        /// Where the step's filled words come from, for History: "body from page (outside content)".
        var provenance: [String]?
    }

    private func standing(_ id: String, tool name: String, input: JSONValue, plan: String?, run: String?, counting: Bool, gateway: ExtensionActionGateway) async -> Standing {
        guard let rt = runtimes[id], let plan, let saved = rt.preferences.plans[plan], saved.live(at: Date(), owner: owner(rt)),
              (rt.pin.permissions ?? ExtensionPermissions()).isContained, ExtensionPlanRules.short(input), let tool = gateway.tool(named: name, for: id) else { return Standing() }
        let definition = ExtensionPlanRules.definition(tool.spec), reach = ExtensionPlanRules.reach(tool.scope(for: input))
        let provider = ExtensionPlanRules.provider(tool)
        let flow = await configuration.flowPolicy()
        // Full access answered it and nobody read it: it stands while Full access is on, and asks for a card first otherwise (D188).
        if saved.answeredUnread == true, flow.mode != .fullAccess { return Standing() }
        let ext = ExtensionPlanRules.extensionTool(tool)
        let command = ext?.program, arguments = ext?.programArguments ?? []
        let program = await command.asyncMap { path in await Task.detached { ProgramPin.hash(of: path, arguments: arguments) }.value } ?? nil
        let fits = saved.steps.first { step in
            guard step.kind == nil, step.standing, step.tool == tool.spec.name, step.definition == definition, (step.provider ?? "") == provider,
                  ExtensionPlanRules.same(step.reach, reach) else { return false }
            // What stands only in Full access stops when it ends (D188). A server's program is the one the person read, and the switch is theirs still.
            if step.isInFullAccessOnly, flow.mode != .fullAccess { return false }
            if step.answeredInAuto == true, flow.mode != .auto { return false }
            if let pinned = step.program, pinned != program { return false }
            if ext?.sandboxed == false, step.program == nil { return false }
            if !flow.mayPassToServers, ext != nil, (step.sources ?? [:]).values.contains("outside") { return false }
            // A slot is a place for words only where the table opens one or the host worked out where the words come from when it read the plan: a plan saved
            // before that was written has no sources, and a slot written in some other field is a plain written value there.
            let open = ExtensionActionPolicy.fillable[tool.spec.name] ?? []
            let fillable = ExtensionPlanRules.slotKeys(step.input).filter { open.contains($0) || step.sources?[$0] != nil }
            return ExtensionPlanRules.matches(input, template: step.input, fillable: fillable,
                                              whole: ExtensionPlanRules.wholeKeys(step.input, tool: tool.spec.name).intersection(fillable))
        }
        guard let fits else { return Standing() }
        // "Ask each time" for the internet is the person's word for every page, whoever asks (D47).
        if tool.spec.capabilities.contains(.network), await configuration.askEachTimeOnline() { return Standing() }
        let provenance = Self.provenance(fits)
        let unread = saved.answeredUnread == true || fits.answeredInAuto == true
        guard counting else { return Standing(step: fits.input, unread: unread, provenance: provenance) }
        // Read after the wait above, and kept: a burst, or a restart, doesn't buy a new budget.
        let day = AIHelper.dayKey(Date()), used = runtimes[id]?.preferences.planCalls[plan]
        let count = used?.day == day ? used?.count ?? 0 : 0
        guard count < saved.perDay else { return Standing(capped: "day") }
        if let run {
            let key = plan + "\u{1}" + run
            let made = runtimes[id]?.runCalls[key] ?? 0
            guard made < (saved.perRun ?? ExtensionPlanRules.defaultPerRun) else { return Standing(capped: "run") }
            runtimes[id]?.countRun(key)
        }
        await updatePreferences(id) {
            $0.planCalls[plan] = ExtensionPreferences.PlanCount(day: day, count: count + 1)
            $0.plans[plan]?.lastUsed = Date()
        }
        return Standing(step: fits.input, unread: unread, provenance: provenance)
    }

    /// Where a step's filled words come from, so History says it afterwards (D189): the field, the names of the steps it reads (as the extension wrote
    /// them), and what the plan declared them to be. The last is what the host worked out when the plan was read, not a fact about this run.
    /// One short line per filled field (a long list would be clipped by History where it is kept, and the end of it would be lost); past twenty, how many more.
    private static func provenance(_ step: ExtensionPlan.Step) -> [String]? {
        let parts = (step.input.objectValue ?? [:]).keys.sorted().compactMap { field -> String? in
            guard let text = step.input[field]?.stringValue, ExtensionPlanRules.hasSlot(text) else { return nil }
            let names = ExtensionPlanRules.roots(text).joined(separator: ", ")
            let said: String
            switch step.sources?[field] {
            case "outside"?: said = String(localized: "outside content: \(field) from step \(names)", comment: "History: where a filled-in value comes from; a field, the steps' names")
            case "claimed"?: said = String(localized: "said by the extension to be the person's own: \(field) from step \(names)", comment: "History: where a filled-in value comes from; a field, the steps' names")
            case nil: said = String(localized: "filled in: \(field) from step \(names)", comment: "History: where a filled-in value comes from; a field, the steps' names")
            default: said = String(localized: "an answer asked of the person, or the clock: \(field) from step \(names)", comment: "History: where a filled-in value comes from; a field, the steps' names")
            }
            return ToolFormat.oneLine(said, 200)
        }
        return parts.isEmpty ? nil : ExtensionPlanWords.capped(parts, 20)
    }

    private func approvePlan(_ id: String, request: JSONValue, params: JSONValue, gateway: ExtensionActionGateway) async {
        func refuse(_ reason: String) async {
            await runtimes[id]?.client?.notify("sidefolk/plan.result", params: ["request": request, "ok": false, "reason": .string(reason)])
        }
        guard let rt = runtimes[id], let plan = params["plan"] else { return await refuse("unusable") }
        // One card at a time for a plan: what the person is reading is what is saved. Taken before anything is awaited, so a second ask can't pass the same check.
        guard !rt.planAsking else { return await refuse("busy") }
        guard (rt.pin.permissions ?? ExtensionPermissions()).isContained else { return await refuse("not_contained") }
        guard Date().timeIntervalSince(rt.lastPersonCall) <= ExtensionPlanRules.personWindow else { return await refuse("not_asked") }
        guard spend(id, "plan", limit: 10) else { return await refuse("busy") }
        runtimes[id]?.planAsking = true
        let evaluation: PlanEvaluation
        switch await evaluatePlan(id, plan: plan, gateway: gateway) {
        case .failure(let reason):
            runtimes[id]?.planAsking = false
            return await refuse(reason.rawValue)
        case .success(let found): evaluation = found
        }
        // One reading of the person's mode decides all of it: the card's words, the answer, what is marked and what the reply says.
        let answer = planAnswer(id, evaluation)
        let words = ExtensionPlanWords.card(for: evaluation, extensionName: name(rt), mode: evaluation.mode)
        let card = ExtensionPlanTool(extensionId: id, plan: ToolFormat.oneLine(evaluation.plan.title.isEmpty ? evaluation.plan.id : evaluation.plan.title, 80), when: evaluation.plan.when, body: words,
                                     answer: answer, intent: evaluation.intent, approveLabel: String(localized: "Approve"), approveNote: ExtensionPlanWords.approveNote(for: evaluation))
        // What Trust shows later is the whole plan as the card says it, not only what an edit added.
        var all = evaluation
        all.previous = nil
        let whole = evaluation.previous == nil ? words : ExtensionPlanWords.card(for: all, extensionName: name(rt), mode: evaluation.mode)
        let asker = asker(rt)
        // What nobody read is named on the approval's own row in History: the lines it let through.
        var rowInput: [String: JSONValue] = ["extension": .string(id), "plan": .string(evaluation.plan.id)]
        if answer == .autoSkipped || answer == .fullAccess { rowInput["lines"] = .array((ExtensionPlanWords.historyRecord(evaluation) ?? []).map { .string($0) }) }
        Task { [weak self] in
            let outcome = await gateway.askForPlan(card, input: .object(rowInput), extensionId: id, asker: asker)
            await self?.finishPlan(id, request: request, outcome: outcome, evaluation: evaluation, answer: answer, card: whole)
        }
    }

    /// Whether the person needs a card for this plan at all (D186–D188). Guard checks the mode again itself: this only says what the host found.
    private func planAnswer(_ id: String, _ e: PlanEvaluation) -> PlanAnswer? {
        if e.covered { return .covered }
        // Only a signed extension's plan can be answered for the person: another's program is untrusted (T44).
        guard runtimes[id]?.pin.origin?.firstParty == true else { return nil }
        // A plan that can't be recorded in full on one History row always shows its card, in every mode: nothing passes that History could not say.
        guard ExtensionPlanWords.historyRecord(e) != nil else { return nil }
        // Full access answers for the person's own click, once: not for a turn of Sidefolk's agent, and not for a click of a minute ago.
        if e.mode == .fullAccess, let click = runtimes[id]?.personClicks.first(where: { Date().timeIntervalSince($0.value) <= ExtensionPlanRules.clickWindow })?.key {
            runtimes[id]?.personClicks[click] = nil
            return .fullAccess
        }
        // In Auto, an edit that only adds what stays inside Sidefolk asks nothing; History still has the row.
        if Self.autoSkips(e) { return .autoSkipped }
        return nil
    }

    /// Whether a plan card is up for this extension now.
    func planIsBeingAsked(_ id: String) -> Bool { runtimes[id]?.planAsking == true }

    /// In Auto, an edit that only adds what stays inside Sidefolk asks nothing.
    private static func autoSkips(_ e: PlanEvaluation) -> Bool {
        // One predicate for the answer and for `plan.check`: an edit passes with no card only if what it adds can be recorded in full (`historyRecord`).
        e.mode == .auto && e.previous != nil && !e.widened && e.fresh.allSatisfy { ExtensionPlanRules.staysInside(e.lines[$0]) }
            && ExtensionPlanWords.historyRecord(e) != nil
    }

    private func finishPlan(_ id: String, request: JSONValue, outcome: ToolOutcome, evaluation: PlanEvaluation, answer: PlanAnswer?, card: String) async {
        runtimes[id]?.planAsking = false
        // An extension that was turned off while its card was up has nobody to answer, and an Allow now saves nothing for it.
        guard let rt = runtimes[id], rt.record.enabled else { return }
        guard outcome.isOK else {
            let reason = if case .unanswered = outcome.status { "unanswered" } else { "denied" }
            await runtimes[id]?.client?.notify("sidefolk/plan.result", params: ["request": request, "ok": false, "reason": .string(reason)])
            return
        }
        // The extension that was read is the one that is saved for: if it was replaced or changed meanwhile, what the person read isn't its plan.
        guard owner(rt) == evaluation.plan.owner else {
            await runtimes[id]?.client?.notify("sidefolk/plan.result", params: ["request": request, "ok": false, "reason": "changed"])
            return
        }
        // What the person read was an edit of the plan standing then: if they ended it or it changed while the card was up (or while an answer was on its way),
        // saving the whole candidate would bring back lines they took away. The program asks again and the whole plan is shown.
        // (A run in the meantime only changes when it last ran, which is not the person's to read.)
        func withoutUse(_ plan: ExtensionPlan?) -> ExtensionPlan? { plan.map { var copy = $0; copy.lastUsed = nil; return copy } }
        if let was = evaluation.previous, withoutUse(rt.preferences.plans[was.id]) != withoutUse(was) {
            await runtimes[id]?.client?.notify("sidefolk/plan.result", params: ["request": request, "ok": false, "reason": "changed"])
            return
        }
        var plan = evaluation.plan
        if card.count <= 20_000 { plan.card = card }
        // Nothing new was read, or what is new stays inside Sidefolk and was answered without a card: nothing was renewed. A plan that ends by itself ends
        // when it was going to, however often its program asks again. (A plan nobody read never gets here with a previous: it is shown whole.)
        if answer == .covered || answer == .autoSkipped, let was = evaluation.previous {
            plan.approvedAt = was.approvedAt
            // An end that was there stays; one that wasn't and now is, is narrower, and is taken.
            plan.expiresAt = was.expiresAt ?? plan.expiresAt
        }
        if answer == .fullAccess { plan.answeredUnread = true }
        // What Auto let through with no card was never read: it stands while Auto is on and asks a card first in any other mode.
        if answer == .autoSkipped { for i in evaluation.fresh { plan.steps[i].answeredInAuto = true } }
        // When it last ran is the host's record, not the candidate's: an edit or a new approval does not make a plan that ran yesterday idle.
        await updatePreferences(id) { prefs in
            var saved = plan
            saved.lastUsed = prefs.plans[plan.id]?.lastUsed
            prefs.plans[plan.id] = saved
        }
        events.changed(.extensions)
        await runtimes[id]?.client?.notify("sidefolk/plan.result", params: ["request": request, "ok": true, "plan": .string(plan.id),
                                                                             "standing": .array(evaluation.lines.map { .bool(evaluation.standsNow($0)) }),
                                                                             "silent": .bool((answer == .covered || answer == .autoSkipped) && evaluation.mode != .askEveryTime || answer == .fullAccess),
                                                                             "new": .number(Double(evaluation.fresh.count))])
    }

    /// `sidefolk/plan.check`: what `plan.approve` would find, with nothing shown, saved or run, so an editor can say it while the person builds (D186).
    private func checkPlan(_ id: String, request: JSONValue, params: JSONValue, gateway: ExtensionActionGateway) async {
        guard let plan = params["plan"] else { return await reply(id, request, ["ok": false, "reason": "unusable"]) }
        switch await evaluatePlan(id, plan: plan, gateway: gateway) {
        case .failure(let reason): await reply(id, request, ["ok": false, "reason": .string(reason.rawValue)])
        case .success(let e):
            let flow = await configuration.flowPolicy()
            let states = e.rows.map { row -> JSONValue in
                let line = e.lines[row], v = line.verdict
                var out: [String: JSONValue]
                if line.step.kind != nil { out = ["state": "listed"] }
                else if flow.mode == .askEveryTime { out = ["state": "asks", "why": "ask_every_time"] }
                else if !v.stands { out = ["state": .string(v.refused ? "refused" : "asks")] }
                else if e.askOnline, line.tool?.spec.capabilities.contains(.network) == true { out = ["state": "asks", "why": "ask_online"] }
                else { out = ["state": .string(v.fullAccessOnly && flow.mode != .fullAccess ? "stands_in_full_access" : "stands")] }
                if let why = v.why, line.step.kind == nil, out["why"] == nil { out["why"] = .string(why) }
                if let detail = v.detail, line.step.kind == nil { out["detail"] = .string(detail) }
                if let warning = v.warning { out["warning"] = .string(warning) }
                return .object(out)
            }
            let newRows = e.rows.indices.filter { e.fresh.contains(e.rows[$0]) }
            await reply(id, request, ["ok": true, "steps": .array(states), "new": .array(newRows.map { .number(Double($0)) }), "silent": .bool((e.covered || (runtimes[id]?.pin.origin?.firstParty == true && Self.autoSkips(e))) && flow.mode != .askEveryTime),
                                      "widened": .bool(e.widened)])
        }
    }

    private func reply(_ id: String, _ request: JSONValue, _ fields: [String: JSONValue]) async {
        var fields = fields
        fields["request"] = request
        await runtimes[id]?.client?.notify("sidefolk/plan.checked", params: .object(fields))
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
