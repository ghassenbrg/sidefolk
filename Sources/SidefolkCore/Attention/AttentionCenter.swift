import Foundation

/// Something that wants the user's attention.
public struct AttentionRequest: Sendable {
    public var level: AttentionLevel
    /// Where it comes from ("reminder", "watcher", "job", "session", "external:claude-code", "brief").
    public var source: String
    public var title: String
    public var body: String?
    public var actions: [AttentionAction]
    public var refKind: String?
    public var refId: String?
    public var historyTitle: String?

    public init(level: AttentionLevel, source: String, title: String, body: String? = nil,
                actions: [AttentionAction] = [], refKind: String? = nil, refId: String? = nil, historyTitle: String? = nil) {
        self.level = level
        self.source = source
        self.title = title
        self.body = body
        self.actions = actions
        self.refKind = refKind
        self.refId = refId
        self.historyTitle = historyTitle
    }
}

/// Decides when and how things reach the user, persists them, and routes the user's answer back
/// to whoever asked (a reminder's Done/Snooze, an agent's question).
public actor AttentionCenter {
    public typealias ActionHandler = @Sendable (AttentionItem, String) async -> Void

    private let store: AttentionStore
    private let events: EventBus
    private let clock: any Clock
    private var env = AttentionEnvironment()
    private var handlers: [String: ActionHandler] = [:]
    private var waiting: [String: CheckedContinuation<String?, Never>] = [:]
    private var held: [String: AttentionItem] = [:]
    /// Attention-level and gentle presentations of the last window, for the rate limits. A slot is
    /// taken in the same synchronous step as the decision, before any `await`, so concurrent posts
    /// can't all decide against the same, older list.
    private var recent: [(source: String, at: Date)] = []
    /// Questions shown, counted apart: their own budget, and they don't use up what notices may do, or a program could keep anyone else's from coming up.
    private var asked: [(source: String, at: Date)] = []
    private var gentle: [(source: String, at: Date)] = []
    /// Away because the input-idle signal said so at the last decision (lock and sleep come through `update`).
    private var idleAway = false
    /// Items an answer is being handled for; a second answer (double click, bubble plus notification) is dropped.
    private var answering: Set<String> = []
    private var timers: [String: Task<Void, Never>] = [:]
    private var renudges: [String: Task<Void, Never>] = [:]

    public init(store: AttentionStore, events: EventBus, clock: any Clock = SystemClock()) {
        self.store = store
        self.events = events
        self.clock = clock
    }

    private var signals: (@Sendable () -> (secondsSinceKey: TimeInterval, secondsSinceInput: TimeInterval))?

    /// Input idle times read at decision time (typing guard, away), so nothing polls.
    public func setSignalProvider(_ provider: @escaping @Sendable () -> (secondsSinceKey: TimeInterval, secondsSinceInput: TimeInterval)) {
        signals = provider
    }

    /// Routes action answers for items whose `refKind` (or source prefix) matches `kind`.
    public func onAction(kind: String, _ handler: @escaping ActionHandler) { handlers[kind] = handler }

    /// What decisions see: the app's view (lock, sleep, quiet, full screen) plus the idle signal.
    public var environment: AttentionEnvironment {
        var e = env
        e.away = e.away || idleAway
        return e
    }

    public func update(_ change: @Sendable (inout AttentionEnvironment) -> Void) {
        let before = env
        change(&env)
        guard env != before else { return }
        if env.isQuiet != before.isQuiet || env.isFocused != before.isFocused {
            events.publish(.happened(Happening(name: "attention.changed", title: env.isQuiet ? "quiet" : env.isFocused ? "focus" : "open")))
        }
        let returned = before.away && !env.away && !idleAway
        let calmer = (before.isQuiet && !env.isQuiet) || (before.isFocused && !env.isFocused)
        // After Focus or Quiet, what waited comes as one card (D84), as it does after being away.
        let focusEnded = before.isFocused && !env.isFocused && !env.isQuiet
        let quietEnded = before.isQuiet && !env.isQuiet && !env.isFocused
        if returned || calmer {
            let summary: HeldSummary? = returned ? .away : focusEnded ? .focus : quietEnded ? .quiet : nil
            Task { await reconsiderHeld(summary: summary) }
        }
    }

    /// Posts and presents (or holds) an item; returns it as it was stored (`kept` when its source is Only in Today,
    /// `acknowledged` when it is Off).
    @discardableResult
    public func post(_ request: AttentionRequest) async -> AttentionItem {
        if request.refKind == "reminder" { events.publish(.happened(Happening(name: "reminder.fired", title: request.title))) }
        let item = makeItem(request)
        return await deliver(item)
    }

    /// Posts and waits for the user to pick an action (or the timeout). Returns the action id.
    public func ask(_ request: AttentionRequest, timeout: TimeInterval) async -> String? {
        let item = makeItem(request)
        let id = item.id
        let timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            await self?.expire(id: id)
        }
        // The waiter is in place before the item can be shown, so an instant answer is never lost.
        // A caller that gave up takes its question with it: nobody is left waiting on the answer.
        let answer = await withTaskCancellationHandler {
            await withCheckedContinuation { c in
                waiting[id] = c
                Task { await self.deliver(item) }
            }
        } onCancel: {
            Task { await self.expire(id: id) }
        }
        timer.cancel()
        return answer
    }

    /// The user chose `actionId` (or dismissed with nil) on an item, here or in a notification. A
    /// second answer to the same item does nothing, even while the first is still being handled.
    public func respond(id: String, actionId: String?) async {
        guard answering.insert(id).inserted else { return }
        defer { answering.remove(id) }
        guard var item = try? await store.item(id: id), item.state != .acknowledged else { return }
        item.state = .acknowledged
        item.acknowledgedAt = clock.now
        try? await store.save(item)
        finish(id)
        waiting.removeValue(forKey: id)?.resume(returning: actionId)
        if let actionId, let handler = handler(for: item) { await handler(item, actionId) }
        events.changed(.attention)
        await publishBacklog()
    }

    public func open() async -> [AttentionItem] { (try? await store.open()) ?? [] }

    /// What Only in Today kept off the desktop (D88) and is still waiting in Today.
    public func kept() async -> [AttentionItem] { (try? await store.kept()) ?? [] }

    /// Whether an item is waiting for its turn (quiet mode, full screen, away, typing or the rate limits).
    public func isHeld(_ id: String) -> Bool { held[id] != nil }

    /// How many items wait for their turn ("Mochi is holding 2 things", D84).
    public var heldCount: Int { held.count }

    /// Retires what is still open about one thing (a repeating reminder's last time) without answering it: no
    /// handler runs, the bubble and notification go away, and it no longer counts as waiting.
    public func withdraw(refKind: String, refId: String) async {
        let live = ((try? await store.open()) ?? []) + ((try? await store.kept()) ?? [])
        for item in live where item.refKind == refKind && item.refId == refId {
            await expire(id: item.id)
        }
    }

    /// After a restart: notices that were still waiting (held while away, quiet or typing) get their
    /// turn again, several as one summary. Questions from the last run are closed, since nobody is
    /// waiting for their answer any more; anything older than a day stays in the Now list only.
    public func restoreWaiting() async {
        let cutoff = clock.now.addingTimeInterval(-86_400)
        for item in (try? await store.open()) ?? [] {
            // Shown or not, nobody's left to hear the answer.
            if item.refKind == "ask" {
                await expire(id: item.id)
            } else if item.state == .pending, item.createdAt > cutoff, item.source != "summary" {
                held[item.id] = item
            }
        }
        await reconsiderHeld(summary: .away)
        await publishBacklog()
    }

    // MARK: Internals

    private func handler(for item: AttentionItem) -> ActionHandler? {
        if let kind = item.refKind, let h = handlers[kind] { return h }
        return handlers[item.source] ?? handlers[String(item.source.split(separator: ":").first ?? "")]
    }

    /// `critical` is kept only for the sources allowed to use it (AttentionPolicy.criticalSources).
    private func makeItem(_ request: AttentionRequest) -> AttentionItem {
        let level = request.level == .critical && !AttentionPolicy.criticalSources.contains(request.source) ? .attention : request.level
        var item = AttentionItem(level: level, source: request.source, title: request.title.clipped(160),
                                 body: request.body?.clipped(600), actions: request.actions, refKind: request.refKind,
                                 refId: request.refId, now: clock.now)
        item.historyTitle = request.historyTitle
        return item
    }

    @discardableResult
    private func deliver(_ item: AttentionItem) async -> AttentionItem {
        try? await store.save(item)
        return await consider(item) ?? item
    }

    /// The level a notice is shown at after its source's ceiling (D88), or nil when the source keeps it off the desktop:
    /// then it is settled here, kept for Today or told in History only, and nil is returned with the settled item.
    private func ceiling(_ item: AttentionItem) async -> (level: AttentionLevel?, settled: AttentionItem?) {
        let route = environment.interruptions.route(item)
        if case .deliver(let level) = route { return (level, nil) }
        var settled = item
        if route == .today {
            settled.state = .kept
        } else {
            settled.state = .acknowledged
            settled.acknowledgedAt = clock.now
        }
        try? await store.save(settled)
        let id = item.id
        held[id] = nil
        timers.removeValue(forKey: id)?.cancel()
        events.changed(.attention)
        await publishBacklog()
        return (nil, settled)
    }

    /// Returns the item as settled when its source kept it off the desktop.
    @discardableResult
    private func consider(_ item: AttentionItem) async -> AttentionItem? {
        let (capped, settled) = await ceiling(item)
        guard let level = capped else { return settled }
        let now = clock.now
        if let s = signals?() {
            env.lastKeyAt = now.addingTimeInterval(-s.secondsSinceKey)
            // Read fresh at every decision: being idle once must not hold everything until a lock/unlock.
            let wasIdle = idleAway
            idleAway = s.secondsSinceInput > 300
            if wasIdle, !idleAway, !env.away, !held.isEmpty { Task { await reconsiderHeld(summary: .away) } }
        }
        let punctual = item.refKind?.hasPrefix(OccurrenceScheduler.attentionKind) == true
        let decision = AttentionPolicy.decide(level: level, source: item.source, createdAt: item.createdAt, now: now,
                                              env: environment, recent: item.refKind == "ask" ? asked : recent, gentle: gentle, punctual: punctual,
                                              reachWhenAway: item.refKind == OccurrenceScheduler.systemAttentionKind, question: item.refKind == "ask")
        switch decision {
        case .present(let presentation):
            held[item.id] = nil
            reserve(item.source, presentation, now: now, question: item.refKind == "ask")
            await present(item, presentation, level: level)
        case .hold(let until):
            held[item.id] = item
            timers[item.id]?.cancel()
            if let until {
                let id = item.id
                let delay = max(0.05, until.timeIntervalSince(now))
                timers[item.id] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    await self?.retry(id: id)
                }
            }
            await publishBacklog()
        }
        return nil
    }

    private func retry(id: String) async {
        timers[id] = nil
        guard let item = held[id] else { return }
        await consider(item)
    }

    /// `level`: what it is shown at, after its source's ceiling; a card turned into a whisper is never nudged again.
    private func present(_ item: AttentionItem, _ presentation: AttentionPresentation, level: AttentionLevel? = nil) async {
        var shown = item
        shown.state = .shown
        shown.shownAt = clock.now
        let saved = shown
        try? await store.save(saved)
        events.publish(.attention(.present(saved, presentation)))

        // One re-nudge for things that need an answer.
        if (level ?? item.level) >= .attention, !item.actions.isEmpty, !item.renudged {
            let id = item.id
            renudges[id]?.cancel()
            renudges[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(AttentionPolicy.renudgeAfter))
                await self?.renudge(id: id)
            }
        }
        await publishBacklog()
    }

    private func renudge(id: String) async {
        renudges[id] = nil
        guard var item = try? await store.item(id: id), item.state == .shown, !item.renudged else { return }
        item.renudged = true
        try? await store.save(item)
        await consider(item)
    }

    /// Counts a presentation against the rate limits. Synchronous, so it lands in the same actor
    /// step as the decision that made it.
    private func reserve(_ source: String, _ presentation: AttentionPresentation, now: Date, question: Bool = false) {
        let window = AttentionPolicy.perSourceWindow
        asked.removeAll { now.timeIntervalSince($0.at) >= window }
        switch presentation {
        case .attention, .system:
            if question { asked.append((source, now)) } else { recent.append((source, now)) }
        case .gentle: gentle.append((source, now))
        case .ambient: break
        }
        recent.removeAll { now.timeIntervalSince($0.at) >= window }
        gentle.removeAll { now.timeIntervalSince($0.at) >= window }
    }

    private func expire(id: String) async {
        if var item = try? await store.item(id: id), item.state != .acknowledged {
            item.state = .expired
            try? await store.save(item)
            finish(id)
        }
        // An `ask` whose item never reached the store still gets its answer: none.
        waiting.removeValue(forKey: id)?.resume(returning: nil)
        await publishBacklog()
    }

    private func finish(_ id: String) {
        held[id] = nil
        timers.removeValue(forKey: id)?.cancel()
        renudges.removeValue(forKey: id)?.cancel()
        events.publish(.attention(.withdraw(id: id)))
    }

    /// Where the person comes back from, for the one card that says what waited.
    private enum HeldSummary { case away, focus, quiet }

    /// Lets held items through again; with `summary`, several of them come as one card.
    private func reconsiderHeld(summary: HeldSummary?) async {
        let items = held.values.sorted { $0.createdAt < $1.createdAt }
        guard !items.isEmpty else { return }
        if let summary, items.count > 1 {
            let title = switch summary {
            case .away: String(localized: "While you were away: \(items.count) things")
            case .focus: String(localized: "While you were focused: \(items.count) things",
                                comment: "One card after Focus ends: what waited during it")
            case .quiet: String(localized: "While Quiet was on: \(items.count) things", comment: "A card when quiet mode ends")
            }
            // Coming back to several things: one summary instead of a parade of bubbles. Each is settled in the
            // store, or a restart would hold it again and the next card would count it twice: a notice is told by
            // the card; something that still needs an answer counts as shown and waits in Needs you.
            for i in items {
                held[i.id] = nil
                timers.removeValue(forKey: i.id)?.cancel()
                guard var settled = try? await store.item(id: i.id), settled.state == .pending else { continue }
                if settled.level >= .attention, !settled.actions.isEmpty {
                    settled.state = .shown
                    settled.shownAt = clock.now
                } else {
                    settled.state = .acknowledged
                    settled.acknowledgedAt = clock.now
                }
                try? await store.save(settled)
            }
            let titles = items.prefix(4).map { "• \($0.title)" }.joined(separator: "\n")
            var card = AttentionItem(level: .attention, source: "summary",
                                        title: title,
                                        body: titles + (items.count > 4 ? "\n…" : ""),
                                        actions: [AttentionAction(id: "open", title: String(localized: "Show"), isPrimary: true)],
                                        // The Sidecard says which moment ended ("Focus ended").
                                        refKind: summary == .away ? nil : "\(summary)",
                                        now: clock.now)
            // It quotes their titles, so what stays out of History on its own stays out here too (D127).
            if items.contains(where: { $0.historyTitle != nil }) { card.historyTitle = title }
            let presentation = AttentionPresentation.attention(expandFor: AttentionPolicy.expandSeconds)
            reserve(card.source, presentation, now: clock.now)
            try? await store.save(card)
            await present(card, presentation)
            return
        }
        for i in items { await consider(i) }
    }

    private func publishBacklog() async {
        let count = ((try? await store.open()) ?? []).filter { $0.level >= .attention }.count
        events.publish(.attention(.backlog(count: count)))
    }
}
