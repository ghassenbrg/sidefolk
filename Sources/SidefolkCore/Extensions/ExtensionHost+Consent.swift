import Foundation

/// What an extension may have only once the person said yes in Sidefolk's own words (D106, D107): where they are, and reminders at a moment
/// of its choosing. Off until then, kept with the extension's preferences, ended when it goes.
extension ExtensionHost {
    public enum Consent: String, Sendable { case place, schedule }

    public func hasConsent(_ consent: Consent, extensionId id: String) -> Bool {
        guard let rt = runtimes[id] else { return false }
        switch consent {
        case .place: return rt.pin.permissions.map { $0.place != nil && rt.preferences.placeOn == true && rt.preferences.placeTerms == Self.terms(.place, $0) } ?? false
        case .schedule: return rt.pin.permissions.map { $0.schedule != nil && rt.preferences.scheduleOn == true && rt.preferences.scheduleTerms == Self.terms(.schedule, $0) } ?? false
        }
    }

    /// What the person said yes to. An update that changes the purpose, or adds the internet to what has their place, asks again.
    static func terms(_ consent: Consent, _ p: ExtensionPermissions) -> String {
        switch consent {
        case .place: "\(p.network)|\(p.place?.purpose ?? "")"
        case .schedule: p.schedule?.purpose ?? ""
        }
    }

    /// The purpose the install preview showed, in the person's language.
    public func consentPurpose(_ consent: Consent, extensionId id: String) -> String? {
        guard let rt = runtimes[id] else { return nil }
        switch consent {
        case .place: return rt.pin.permissions?.place.map { words(rt)?.placePurpose ?? $0.purpose }
        case .schedule: return rt.pin.permissions?.schedule.map { words(rt)?.schedulePurpose ?? $0.purpose }
        }
    }

    /// Reached only through `extensions.consent`, on the person's own click.
    func setConsent(_ consent: Consent, extensionId id: String, _ on: Bool) async throws {
        guard let rt = runtimes[id] else { throw ToolError.notFound(String(localized: "an extension called \(id)")) }
        switch consent {
        case .place:
            guard rt.pin.permissions?.place != nil else { throw UserFacingError("\(rt.pin.name) didn't ask for your place when you installed it.") }
            let terms = rt.pin.permissions.map { Self.terms(.place, $0) }
            await updatePreferences(id) {
                $0.placeOn = on
                $0.placeTerms = terms
            }
            publishRequestContext()
            await tellPlace(id)
            await askForPlan(id, reason: "place")
        case .schedule:
            guard rt.pin.permissions?.schedule != nil else { throw UserFacingError("\(rt.pin.name) didn't ask to schedule reminders when you installed it.") }
            let terms = rt.pin.permissions.map { Self.terms(.schedule, $0) }
            await updatePreferences(id) {
                $0.scheduleOn = on
                $0.scheduleTerms = terms
            }
            publishRequestContext()
            if on {
                await askForPlan(id, reason: "consent")
            } else {
                await occurrences?.cancel(id)
                occurrenceCounts[id]?.pending = 0
            }
        }
        publishRequestContext()
        events.changed(.extensions)
    }

    // MARK: Place

    /// What the program is told of the person's place: a town and its zone, the same two-decimal coordinates the weather uses.
    static func placeJSON(_ place: KnownPlace?) -> JSONValue {
        guard let place else { return .null }
        var out: [String: JSONValue] = ["city": .string(place.city), "latitude": .number(place.latitude), "longitude": .number(place.longitude),
                                        "updated_at": .string(ISO8601DateFormatter().string(from: place.updatedAt))]
        if let region = place.region { out["region"] = .string(region) }
        if let country = place.country { out["country"] = .string(country) }
        if let code = place.countryCode { out["country_code"] = .string(code) }
        if let zone = place.timeZone { out["time_zone"] = .string(zone) }
        return .object(out)
    }

    /// The place moved: the extensions allowed to know hear of it once. A place saved again where it was isn't a change, or a daily re-reading would look like one.
    public func placeChanged() async {
        let place = configuration.currentPlace()
        let now = place.map { "\($0.city)|\($0.latitude)|\($0.longitude)|\($0.timeZone ?? "")" }
        guard now != lastPlace else { return }
        lastPlace = now
        publishRequestContext()
        for id in runtimes.keys.sorted() where hasConsent(.place, extensionId: id) {
            await tellPlace(id)
            await askForPlan(id, reason: "place")
        }
    }

    /// A program that isn't running hears of it with its next request.
    private func tellPlace(_ id: String) async {
        guard let client = runtimes[id]?.client else { return }
        let place = hasConsent(.place, extensionId: id) ? Self.placeJSON(configuration.currentPlace()) : .null
        await client.notify("sidefolk/place.changed", params: ["place": place, "place_share": .string(hasConsent(.place, extensionId: id) ? "on" : "off")])
    }

    /// `sidefolk/place.search`: through the tool, so Guard and History see the internet being reached. It needs the permission but not the yes: nothing of the
    /// person's goes with the words typed. One in two seconds, each being a row in History.
    func searchPlace(_ id: String, params: JSONValue, now: Date = Date()) async {
        guard let rt = runtimes[id], rt.record.enabled, rt.pin.permissions?.place != nil, let client = rt.client, let run = configuration.runTool,
              let request = params["request"]?.stringValue, UUID(uuidString: request) != nil else { return }
        guard now.timeIntervalSince(rt.lastPlaceSearch) >= 2, let query = params["query"]?.stringValue.map({ ExtensionText.line($0, characters: 80) }), !query.isEmpty else {
            await client.notify("sidefolk/place.found", params: ["request": .string(request), "places": [], "problem": .string("busy")])
            return
        }
        runtimes[id]?.lastPlaceSearch = now
        let outcome = await run(ExtensionPlaceSearchTool.name, ["extension": .string(id), "query": .string(query)], .extension(id: id), 20)
        if case .ok(let result) = outcome.status, !result.isError, let places = try? JSONValue.parse(Data(result.text.utf8)) {
            await client.notify("sidefolk/place.found", params: ["request": .string(request), "places": places])
        } else {
            await client.notify("sidefolk/place.found", params: ["request": .string(request), "places": [], "problem": .string(outcome.problem?.message ?? "unavailable")])
        }
    }

    // MARK: Occurrences

    public func setOccurrences(_ scheduler: OccurrenceScheduler) async {
        occurrences = scheduler
        await scheduler.configure(mayTell: { [weak self] id in await self?.mayTellOccurrences(id) ?? false },
                                  onOpen: { [weak self] id, page, state in
                                      Task { await self?.openFromOccurrence(id, page: page, state: state) }
                                  })
    }

    /// Those that may have something scheduled, with the names their notices carry.
    public func scheduling() -> [(id: String, name: String)] {
        runtimes.compactMap { id, rt in rt.pin.permissions?.schedule == nil ? nil : (id, name(rt)) }
    }

    /// Still true at the moment of telling, however it stopped being: turned off, resting, failed its check on disk, the person took it back.
    private func mayTellOccurrences(_ id: String) -> Bool {
        guard let rt = runtimes[id], rt.record.enabled, rt.outdatedWasOn == nil, restingFor(id) == nil else { return false }
        return hasConsent(.schedule, extensionId: id)
    }

    private func openFromOccurrence(_ id: String, page: String, state: [String: JSONValue]?) {
        guard runtimes[id]?.manifest?.pages[page] != nil else { return }
        if let state { movePage("\(id)/\(page)", PageGo(set: state)) }
        events.publish(.extensionPage(id: "\(id)/\(page)"))
    }

    /// Wake, a clock change or any change of settings all arrive by one road: a new plan only when the zone or the day really moved. The timer itself
    /// is already re-armed, and what is pending needs no program.
    public func replanIfMoved(now: Date = Date()) async {
        let zone = TimeZone.current.identifier, day = Calendar.current.startOfDay(for: now)
        guard plannedFor.zone != zone || plannedFor.day != day else { return }
        plannedFor = (zone, day)
        await askForPlans(reason: "wake")
    }

    /// What macOS says about notifications from Sidefolk, for what goes with requests.
    public func setNotificationStatus(_ status: String) {
        guard status != notificationStatus else { return }
        notificationStatus = status
        publishRequestContext()
    }

    /// Plans on starting and when the day turns over, so a horizon of days keeps moving with nobody opening the page. The program's
    /// plan is what decides anything: asking twice costs a little work and changes nothing.
    public func startPlanning(every interval: TimeInterval = 6 * 3600) async {
        await refreshOccurrenceCounts()
        plannedFor = (TimeZone.current.identifier, Calendar.current.startOfDay(for: Date()))
        lastPlace = configuration.currentPlace().map { "\($0.city)|\($0.latitude)|\($0.longitude)|\($0.timeZone ?? "")" }
        planning?.cancel()
        planning = Task { [weak self] in
            await self?.askForPlans(reason: "start")
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(60))
                guard !Task.isCancelled else { return }
                await self?.replanDaily()
            }
        }
        placeWatch?.cancel()
        let stream = events.stream()
        placeWatch = Task { [weak self] in
            for await event in stream {
                if case .dataChanged(.settings) = event { await self?.placeChanged() }
            }
        }
    }

    private func replanDaily(now: Date = Date()) async {
        let day = Calendar.current.startOfDay(for: now)
        guard plannedFor.day != day else { return }
        plannedFor.day = day
        await askForPlans(reason: "daily")
    }

    func refreshOccurrenceCounts() async {
        guard let occurrences else { return }
        for id in runtimes.keys where runtimes[id]?.pin.permissions?.schedule != nil {
            occurrenceCounts[id] = await occurrences.status(id)
        }
        publishRequestContext()
    }

    /// `sidefolk/occurrences.replace`: the program's whole plan. At most one in ten seconds, the last winning, since each is a row in History.
    /// The program hears how it went (`sidefolk/occurrences.result`), so it needn't guess why nothing came.
    func programReplacesOccurrences(_ id: String, params: JSONValue, now: Date = Date()) async {
        guard let rt = runtimes[id] else { return }
        let held = rt.planWaiting != nil
        runtimes[id]?.planWaiting = params
        guard !held else { return }
        let wait = rt.lastPlan.addingTimeInterval(ExtensionAbilityLimits.planSeconds).timeIntervalSince(now)
        guard wait > 0 else {
            await flushPlan(id, at: now)
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            await self?.flushPlan(id, at: Date())
        }
    }

    private func flushPlan(_ id: String, at now: Date) async {
        guard let rt = runtimes[id], let params = rt.planWaiting else { return }
        runtimes[id]?.planWaiting = nil
        runtimes[id]?.lastPlan = now
        func told(_ ok: Bool, _ reason: String?) async {
            var result: [String: JSONValue] = ["ok": .bool(ok), "pending": .number(Double(occurrenceCounts[id]?.pending ?? 0)), "revision": .number(Double(occurrenceCounts[id]?.revision ?? 0))]
            if let reason { result["reason"] = .string(reason) }
            await runtimes[id]?.client?.notify("sidefolk/occurrences.result", params: .object(result))
        }
        guard rt.record.enabled, hasConsent(.schedule, extensionId: id), let run = configuration.runTool, let occurrences else {
            await told(false, "not_allowed")
            return
        }
        let list = params["occurrences"]?.arrayValue ?? [], revision = params["revision"]?.intValue ?? 0
        let pages = Set(rt.manifest?.pages.keys.map { $0 } ?? [])
        if await occurrences.isSame(id, revision: revision, occurrences: list.compactMap { ScheduledOccurrence.parse($0, pages: pages) }) {
            await refreshOccurrenceCounts()
            await told(true, nil)
            return
        }
        let outcome = await run(ExtensionOccurrencesTool.name, ["extension": .string(id), "revision": .number(Double(revision)), "occurrences": .array(list)], .extension(id: id), 10)
        await told(outcome.isOK, outcome.isOK ? nil : (outcome.problem?.message ?? "failed"))
    }

    /// `extensions.occurrences`, after Guard. Returns how many are pending, or nil when nothing changed.
    func applyOccurrences(_ id: String, revision: Int, occurrences list: [JSONValue]) async throws -> Int? {
        guard let rt = runtimes[id], rt.record.enabled, hasConsent(.schedule, extensionId: id), let occurrences else {
            throw UserFacingError("Reminders from this extension aren't allowed.")
        }
        guard list.count <= ScheduledOccurrence.maxPending * 2 else { throw UserFacingError("That's too many reminders at once.") }
        let pages = Set(rt.manifest?.pages.keys.map { $0 } ?? [])
        let kept = await occurrences.replace(id, name: name(rt), revision: revision, occurrences: list.compactMap { ScheduledOccurrence.parse($0, pages: pages) })
        await refreshOccurrenceCounts()
        return kept
    }

    /// Asks a program for its plan now, as a request so its process stays up until it answers. Silent for anything else: an extension
    /// that didn't declare this, or isn't allowed, is never started for it.
    func askForPlan(_ id: String, reason: String) async {
        guard let rt = runtimes[id], rt.record.enabled, rt.record.kind == .sidefolk, hasConsent(.schedule, extensionId: id) else { return }
        begin(id)
        defer { end(id) }
        // Nothing back, or the wrong shape, leaves the plan it has: a failed asking must never read as "nothing is planned".
        guard let client = try? await ensureRunning(id),
              let reply = try? await client.request("sidefolk/occurrences.plan", params: ["reason": .string(reason)], timeout: 60),
              reply.objectValue != nil, reply["occurrences"]?.arrayValue != nil else { return }
        await programReplacesOccurrences(id, params: reply)
    }

    /// Every extension allowed, for a reason of Sidefolk's: starting, waking, a new day.
    public func askForPlans(reason: String) async {
        for id in runtimes.keys.sorted() where hasConsent(.schedule, extensionId: id) { await askForPlan(id, reason: reason) }
    }
}

/// `extensions.consent` (D106, D107): where the person's yes lands. Their click alone: not a model, another agent or the extension itself.
struct ExtensionConsentTool: Tool {
    static let name = "extensions.consent"

    let host: ExtensionHost

    var spec: ToolSpec {
        ToolSpec(name: Self.name, title: String(localized: "Change what an extension may have", comment: "A tool: the person's yes or no to an extension's place or reminders"),
                 description: "Records the person's answer about an extension's place or reminders.",
                 inputSchema: Schema.object(["extension": Schema.string("The extension's id."), "what": Schema.string("place or schedule"), "on": Schema.boolean("Their answer.")],
                                            required: ["extension", "what", "on"]),
                 risk: .low, capabilities: [.system], category: .system, mutates: true, offeredToModel: false)
    }

    func summary(for input: JSONValue) -> String {
        let name = input.string("extension").flatMap { host.shelf.names[$0] } ?? input.string("extension") ?? ""
        let on = input["on"]?.boolValue ?? false
        switch input.string("what") {
        case "place": return on ? String(localized: "Share your place with \(name)") : String(localized: "Stop sharing your place with \(name)")
        default: return on ? String(localized: "Let \(name) schedule reminders") : String(localized: "Stop \(name)'s reminders")
        }
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope(extensionId: input.string("extension")) }

    func refusal(for input: JSONValue, context: ToolContext) -> String? {
        context.caller == .user ? nil : "This is for the person's own click."
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let id = input.string("extension"), let what = input.string("what").flatMap(ExtensionHost.Consent.init(rawValue:)), let on = input["on"]?.boolValue else {
            throw ToolError.invalidInput(String(localized: "There's no such choice."))
        }
        try await host.setConsent(what, extensionId: id, on)
        return ToolResult(text: "Changed.", card: ResultCard(kind: .info, title: summary(for: input)), untrusted: true)
    }
}

/// `extensions.place_search` (D106): the words an extension's search field was given, to Sidefolk's own place search. It reaches one service, named here, and
/// nothing of the person's goes with them. Only the extension reaches it, for itself; the answer goes back to its program alone.
struct ExtensionPlaceSearchTool: Tool {
    static let name = "extensions.place_search"

    let shelfName: @Sendable (String) -> String?

    var spec: ToolSpec {
        ToolSpec(name: Self.name, title: String(localized: "Look up a place", comment: "A tool: an extension looks a town up by name"),
                 description: "Finds towns by name for an extension.",
                 inputSchema: Schema.object(["extension": Schema.string("The extension's id."), "query": Schema.string("What was typed.")], required: ["extension", "query"]),
                 risk: .low, capabilities: [.network], category: .web, mutates: false, offeredToModel: false)
    }

    func summary(for input: JSONValue) -> String {
        let name = input.string("extension").flatMap(shelfName) ?? ""
        return String(localized: "\(name) looked up “\(ExtensionText.line(input.string("query") ?? "", characters: 60))”", comment: "History: an extension searched for a place by name")
    }

    func scope(for input: JSONValue) -> ToolScope {
        ToolScope(extensionId: input.string("extension"), reach: .service("Open-Meteo"))
    }

    func refusal(for input: JSONValue, context: ToolContext) -> String? {
        if case .extension(let own) = context.caller, own == input.string("extension") { return nil }
        return "Only an extension looks up places for itself."
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let places = try await PlaceFinder().search(input.string("query") ?? "")
        let json = JSONValue.array(places.map { ExtensionHost.placeJSON($0) }).jsonString
        return ToolResult(text: json, card: ResultCard(kind: .info, title: summary(for: input)), untrusted: true)
    }
}

/// `extensions.occurrences` (D107): an extension's plan of reminders, for itself. No model reaches it, and its words go only to the person.
struct ExtensionOccurrencesTool: Tool {
    static let name = "extensions.occurrences"

    let host: ExtensionHost

    var spec: ToolSpec {
        ToolSpec(name: Self.name, title: String(localized: "Plan an extension's reminders", comment: "A tool: an extension replaces the reminders it scheduled"),
                 description: "Replaces the reminders an extension scheduled.",
                 inputSchema: Schema.object(["extension": Schema.string("The extension's id."), "revision": Schema.integer("Its plan's number."),
                                             "occurrences": ["type": "array", "description": "The whole plan."]], required: ["extension", "revision", "occurrences"]),
                 risk: .low, capabilities: [.system], category: .system, mutates: true, offeredToModel: false)
    }

    func summary(for input: JSONValue) -> String {
        let name = input.string("extension").flatMap { host.shelf.names[$0] } ?? ""
        let count = input["occurrences"]?.arrayValue?.count ?? 0
        return String(localized: "\(name) planned \(count) reminders", comment: "History: an extension replaced the reminders it scheduled")
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope(extensionId: input.string("extension")) }

    func refusal(for input: JSONValue, context: ToolContext) -> String? {
        if case .extension(let own) = context.caller, own == input.string("extension") { return nil }
        return "Only an extension plans its own reminders."
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let id = input.string("extension"), let revision = input["revision"]?.intValue, let list = input["occurrences"]?.arrayValue else {
            throw ToolError.invalidInput(String(localized: "That plan can't be read."))
        }
        _ = try await host.applyOccurrences(id, revision: revision, occurrences: list)
        return ToolResult(text: "Planned.", card: ResultCard(kind: .info, title: summary(for: input)), untrusted: true)
    }
}
