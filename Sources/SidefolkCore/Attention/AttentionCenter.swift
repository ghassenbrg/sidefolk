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
    private var recent: [(source: String, at: Date)] = []
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

    public var environment: AttentionEnvironment { env }

    public func update(_ change: @Sendable (inout AttentionEnvironment) -> Void) {
        let before = env
        change(&env)
        guard env != before else { return }
        let returned = before.away && !env.away
        let calmer = (before.quiet && !env.quiet) || (before.fullscreen && !env.fullscreen)
        if returned || calmer { reconsiderHeld(summarise: returned) }
    }

    /// Posts and presents (or holds) an item; returns it.
    @discardableResult
    public func post(_ request: AttentionRequest) async -> AttentionItem {
        let item = AttentionItem(level: request.level, source: request.source, title: request.title.clipped(160),
                                 body: request.body?.clipped(600), actions: request.actions, refKind: request.refKind,
                                 refId: request.refId, now: clock.now)
        try? await store.save(item)
        consider(item)
        return item
    }

    /// Posts and waits for the user to pick an action (or the timeout). Returns the action id.
    public func ask(_ request: AttentionRequest, timeout: TimeInterval) async -> String? {
        let item = await post(request)
        let id = item.id
        let timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            await self?.expire(id: id)
        }
        let answer = await withCheckedContinuation { c in waiting[id] = c }
        timer.cancel()
        return answer
    }

    /// The user chose `actionId` (or dismissed with nil) on an item, here or in a notification.
    public func respond(id: String, actionId: String?) async {
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

    // MARK: Internals

    private func handler(for item: AttentionItem) -> ActionHandler? {
        if let kind = item.refKind, let h = handlers[kind] { return h }
        return handlers[item.source] ?? handlers[String(item.source.split(separator: ":").first ?? "")]
    }

    private func consider(_ item: AttentionItem) {
        let now = clock.now
        if let s = signals?() {
            env.lastKeyAt = now.addingTimeInterval(-s.secondsSinceKey)
            if s.secondsSinceInput > 300 { env.away = true }
        }
        let decision = AttentionPolicy.decide(level: item.level, source: item.source, createdAt: item.createdAt, now: now,
                                              env: env, recent: recent)
        switch decision {
        case .present(let presentation):
            held[item.id] = nil
            present(item, presentation)
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
            Task { await publishBacklog() }
        }
    }

    private func retry(id: String) {
        timers[id] = nil
        guard let item = held[id] else { return }
        consider(item)
    }

    private func present(_ item: AttentionItem, _ presentation: AttentionPresentation) {
        var shown = item
        shown.state = .shown
        shown.shownAt = clock.now
        let store = self.store
        let saved = shown
        Task { try? await store.save(saved) }
        if case .attention = presentation { recent.append((item.source, clock.now)) }
        if case .system = presentation { recent.append((item.source, clock.now)) }
        recent = recent.filter { clock.now.timeIntervalSince($0.at) < AttentionPolicy.perSourceWindow }
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
        Task { await publishBacklog() }
    }

    private func renudge(id: String) async {
        renudges[id] = nil
        guard var item = try? await store.item(id: id), item.state == .shown, !item.renudged else { return }
        item.renudged = true
        try? await store.save(item)
        consider(item)
    }

    private func expire(id: String) async {
        guard var item = try? await store.item(id: id), item.state != .acknowledged else { return }
        item.state = .expired
        try? await store.save(item)
        finish(id)
        waiting.removeValue(forKey: id)?.resume(returning: nil)
        await publishBacklog()
    }

    private func finish(_ id: String) {
        held[id] = nil
        timers.removeValue(forKey: id)?.cancel()
        renudges.removeValue(forKey: id)?.cancel()
        events.publish(.attention(.withdraw(id: id)))
    }

    private func reconsiderHeld(summarise: Bool) {
        let items = held.values.sorted { $0.createdAt < $1.createdAt }
        guard !items.isEmpty else { return }
        if summarise, items.count > 1 {
            // Coming back to several things: one summary instead of a parade of bubbles.
            for i in items { held[i.id] = nil }
            let titles = items.prefix(4).map { "• \($0.title)" }.joined(separator: "\n")
            let summary = AttentionItem(level: .attention, source: "summary",
                                        title: "While you were away: \(items.count) things",
                                        body: titles + (items.count > 4 ? "\n…" : ""),
                                        actions: [AttentionAction(id: "open", title: "Show", isPrimary: true)], now: clock.now)
            let store = self.store
            Task { try? await store.save(summary) }
            present(summary, .attention(expandFor: AttentionPolicy.expandSeconds))
            return
        }
        for i in items { consider(i) }
    }

    private func publishBacklog() async {
        let count = ((try? await store.open()) ?? []).filter { $0.level >= .attention }.count
        events.publish(.attention(.backlog(count: count)))
    }
}
