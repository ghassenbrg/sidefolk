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

    public init(level: AttentionLevel, source: String, title: String, body: String? = nil,
                actions: [AttentionAction] = [], refKind: String? = nil, refId: String? = nil) {
        self.level = level
        self.source = source
        self.title = title
        self.body = body
        self.actions = actions
        self.refKind = refKind
        self.refId = refId
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
        let returned = before.away && !env.away && !idleAway
        let calmer = (before.quiet && !env.quiet) || (before.fullscreen && !env.fullscreen)
        if returned || calmer { Task { await reconsiderHeld(summarise: returned) } }
    }

    /// Posts and presents (or holds) an item; returns it.
    @discardableResult
    public func post(_ request: AttentionRequest) async -> AttentionItem {
        let item = makeItem(request)
        await deliver(item)
        return item
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
        let answer = await withCheckedContinuation { c in
            waiting[id] = c
            Task { await self.deliver(item) }
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

    /// Whether an item is waiting for its turn (quiet mode, full screen, away, typing or the rate limits).
    public func isHeld(_ id: String) -> Bool { held[id] != nil }

    /// Retires what is still open about one thing (a repeating reminder's last time) without answering it: no
    /// handler runs, the bubble and notification go away, and it no longer counts as waiting.
    public func withdraw(refKind: String, refId: String) async {
        for item in (try? await store.open()) ?? [] where item.refKind == refKind && item.refId == refId {
            await expire(id: item.id)
        }
    }

    /// After a restart: notices that were still waiting (held while away, quiet or typing) get their
    /// turn again, several as one summary. Questions from the last run are closed, since nobody is
    /// waiting for their answer any more; anything older than a day stays in the Now list only.
    public func restoreWaiting() async {
        let cutoff = clock.now.addingTimeInterval(-86_400)
        for item in (try? await store.open()) ?? [] where item.state == .pending {
            if item.refKind == "ask" {
                await expire(id: item.id)
            } else if item.createdAt > cutoff, item.source != "summary" {
                held[item.id] = item
            }
        }
        await reconsiderHeld(summarise: true)
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
        return AttentionItem(level: level, source: request.source, title: request.title.clipped(160),
                             body: request.body?.clipped(600), actions: request.actions, refKind: request.refKind,
                             refId: request.refId, now: clock.now)
    }

    private func deliver(_ item: AttentionItem) async {
        try? await store.save(item)
        await consider(item)
    }

    private func consider(_ item: AttentionItem) async {
        let now = clock.now
        if let s = signals?() {
            env.lastKeyAt = now.addingTimeInterval(-s.secondsSinceKey)
            // Read fresh at every decision: being idle once must not hold everything until a lock/unlock.
            let wasIdle = idleAway
            idleAway = s.secondsSinceInput > 300
            if wasIdle, !idleAway, !env.away, !held.isEmpty { Task { await reconsiderHeld(summarise: true) } }
        }
        let decision = AttentionPolicy.decide(level: item.level, source: item.source, createdAt: item.createdAt, now: now,
                                              env: environment, recent: recent, gentle: gentle)
        switch decision {
        case .present(let presentation):
            held[item.id] = nil
            reserve(item.source, presentation, now: now)
            await present(item, presentation)
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
    }

    private func retry(id: String) async {
        timers[id] = nil
        guard let item = held[id] else { return }
        await consider(item)
    }

    private func present(_ item: AttentionItem, _ presentation: AttentionPresentation) async {
        var shown = item
        shown.state = .shown
        shown.shownAt = clock.now
        let saved = shown
        try? await store.save(saved)
        events.publish(.attention(.present(saved, presentation)))

        // One re-nudge for things that need an answer.
        if item.level >= .attention, !item.actions.isEmpty, !item.renudged {
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
    private func reserve(_ source: String, _ presentation: AttentionPresentation, now: Date) {
        let window = AttentionPolicy.perSourceWindow
        switch presentation {
        case .attention, .system: recent.append((source, now))
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

    private func reconsiderHeld(summarise: Bool) async {
        let items = held.values.sorted { $0.createdAt < $1.createdAt }
        guard !items.isEmpty else { return }
        if summarise, items.count > 1 {
            // Coming back to several things: one summary instead of a parade of bubbles.
            for i in items { held[i.id] = nil }
            let titles = items.prefix(4).map { "• \($0.title)" }.joined(separator: "\n")
            let summary = AttentionItem(level: .attention, source: "summary",
                                        title: String(localized: "While you were away: \(items.count) things"),
                                        body: titles + (items.count > 4 ? "\n…" : ""),
                                        actions: [AttentionAction(id: "open", title: String(localized: "Show"), isPrimary: true)],
                                        now: clock.now)
            let presentation = AttentionPresentation.attention(expandFor: AttentionPolicy.expandSeconds)
            reserve(summary.source, presentation, now: clock.now)
            try? await store.save(summary)
            await present(summary, presentation)
            return
        }
        for i in items { await consider(i) }
    }

    private func publishBacklog() async {
        let count = ((try? await store.open()) ?? []).filter { $0.level >= .attention }.count
        events.publish(.attention(.backlog(count: count)))
    }
}
