import Foundation

/// The probes Sidefolk ships with.
public enum WatchProbes {
    public static func standard(fetcher: any WatchFetcher = URLSessionFetcher(), throttle: HostThrottle = HostThrottle(),
                                processes: any ProcessTable = LibprocTable()) -> [any WatcherProbe] {
        [
            UrlChangeProbe(fetcher: fetcher, throttle: throttle),
            SiteStatusProbe(fetcher: fetcher, throttle: throttle),
            FileAppearsProbe(),
            FileChangesProbe(),
            FolderNewFileProbe(),
            ProcessExitsProbe(table: processes),
            CommandProbe(),
        ]
    }
}

/// Runs watchers: what you asked Sidefolk to keep an eye on, checked on a schedule that costs
/// almost nothing. One task sleeps until the soonest check; folder and process events can wake it early.
///
/// Every change to a watcher goes through this actor, which keeps all watchers in memory and writes
/// each change straight to the database, so a restart picks up exactly where things were.
public actor WatcherEngine {
    static let maxConcurrentChecks = 4
    /// Event-driven checks on one watcher are at least this far apart.
    static let minEventGap: TimeInterval = 2

    let store: WatcherStore
    let attention: AttentionCenter
    let events: EventBus
    let clock: any Clock
    let opener: @Sendable (URL) async -> Void

    var probes: [String: any WatcherProbe] = [:]
    var watchers: [String: Watcher] = [:]
    var loadTask: Task<[Watcher], Never>?
    var loaded = false
    var started = false
    /// Bumped by `stop()`; results of checks that began earlier are dropped.
    var epoch = 0
    var ticking = false
    var timer: Task<Void, Never>?
    var timerGeneration = 0
    var running: Set<String> = []
    var inflight: [String: Task<ProbeResult, any Error>] = [:]
    var cooldownUntil: [String: Date] = [:]
    var openTargets: [String: String] = [:]
    var hub: WatchEventHub?

    /// - Parameters:
    ///   - opener: opens a web address or a file for the "Open" button (the app's `PlatformBridge`).
    ///   - probes: defaults to the built-in kinds; pass fakes in tests.
    public init(store: WatcherStore, attention: AttentionCenter, events: EventBus, clock: any Clock = SystemClock(),
                opener: @escaping @Sendable (URL) async -> Void = { _ in }, probes: [any WatcherProbe]? = nil) {
        self.store = store
        self.attention = attention
        self.events = events
        self.clock = clock
        self.opener = opener
        for probe in probes ?? WatchProbes.standard() { self.probes[probe.kind] = probe }
    }

    // MARK: Lifecycle

    /// Teaches the engine a new kind of watcher (an extension's). Watchers of that kind that were
    /// parked because the kind was unknown start working again.
    public func register(_ probe: any WatcherProbe) async {
        await ensureLoaded()
        probes[probe.kind] = probe
        for var w in watchers.values where w.state == .error && w.kind == probe.kind && w.nextCheckAt == nil {
            w.state = .active
            w.lastError = nil
            w.nextCheckAt = clock.now
            watchers[w.id] = w
            await persist(w)
            refreshEvents(w)
        }
        arm()
    }

    /// Call at launch: loads watchers, listens for their events and starts the schedule. Anything that
    /// came due while the app was closed is checked right away.
    public func start() async {
        await ensureLoaded()
        await connectAttention()
        started = true
        hub = WatchEventHub { [weak self] ids in
            guard let self else { return }
            Task { await self.handleEvents(ids) }
        }
        for w in watchers.values { refreshEvents(w) }
        arm()
    }

    /// Routes the buttons on watcher notices (Open, Keep watching, Stop) back here.
    func connectAttention() async {
        await attention.onAction(kind: "watcher") { [weak self] item, action in await self?.handleAction(item, action) }
    }

    /// Call when the app quits: nothing runs afterwards and checks in flight are abandoned.
    public func stop() {
        started = false
        epoch += 1
        timerGeneration += 1
        timer?.cancel()
        timer = nil
        for task in inflight.values { task.cancel() }
        inflight.removeAll()
        hub?.stopAll()
        hub = nil
    }

    /// Call after the Mac wakes or the clock or time zone changes, so the next check is timed from the real time.
    public func rearm() { arm() }

    // MARK: Reading

    public func list() async -> [Watcher] {
        await ensureLoaded()
        return watchers.values.sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    public func watcher(id: String) async -> Watcher? {
        await ensureLoaded()
        return watchers[id]
    }

    // MARK: Changing

    /// Starts watching. Fills in defaults, raises too-short intervals to the kind's floor and
    /// refuses what is not allowed; the error message is written for the user.
    @discardableResult
    public func add(_ watcher: Watcher) async throws -> Watcher {
        await ensureLoaded()
        guard let probe = probes[watcher.kind] else { throw WatchError.unknownKind(watcher.kind) }
        let now = clock.now
        var w = watcher
        w.title = w.title.displaySafe.clipped(100)
        if w.title.isEmpty { w.title = w.kind.replacingOccurrences(of: "_", with: " ") }
        if w.intervalS <= 0 { w.intervalS = probe.defaultInterval }
        w.intervalS = min(max(w.intervalS, probe.minimumInterval), WatchLimits.maxInterval)
        // Only the user's own watchers may be critical; everything else stays at "attention" or below.
        if w.level > .attention, w.source != "user" { w.level = .attention }
        w = try probe.prepare(w)
        try checkRoom(for: w)
        w.state = .active
        w.nextCheckAt = now
        w.lastCheckedAt = nil
        w.lastState = nil
        w.lastError = nil
        w.errorCount = 0
        w.fireCount = 0
        if w.expiresAt == nil { w.expiresAt = now.addingTimeInterval(defaultExpiry(w.mode)) }
        w.createdAt = now
        w.updatedAt = now
        watchers[w.id] = w
        await persist(w)
        refreshEvents(w)
        arm()
        return w
    }

    /// Stops watching and forgets the watcher. Returns it (so an undo can bring it back).
    @discardableResult
    public func remove(_ id: String) async -> Watcher? {
        await ensureLoaded()
        guard let w = watchers.removeValue(forKey: id) else { return nil }
        inflight.removeValue(forKey: id)?.cancel()
        cooldownUntil[id] = nil
        openTargets[id] = nil
        hub?.remove(id)
        do { try await store.delete(id: id) } catch { Log.shared.warning("watch", "could not delete a watcher", ["error": "\(error)"]) }
        events.changed(.watchers)
        arm()
        return w
    }

    @discardableResult
    public func pause(_ id: String) async throws -> Watcher {
        await ensureLoaded()
        guard var w = watchers[id] else { throw WatchError.notFound("that watcher") }
        guard w.state == .active else { return w }
        inflight.removeValue(forKey: id)?.cancel()
        w.state = .paused
        w.nextCheckAt = nil
        w.updatedAt = clock.now
        watchers[id] = w
        hub?.remove(id)
        await persist(w)
        arm()
        return w
    }

    /// Starts a paused, finished, expired or stuck watcher again, with a fresh lifetime.
    @discardableResult
    public func resume(_ id: String) async throws -> Watcher {
        await ensureLoaded()
        guard var w = watchers[id] else { throw WatchError.notFound("that watcher") }
        guard w.state != .active else { return w }
        guard probes[w.kind] != nil else { throw WatchError.unknownKind(w.kind) }
        try checkRoom(for: w)
        let now = clock.now
        w.state = .active
        w.errorCount = 0
        w.lastError = nil
        w.nextCheckAt = now
        w.expiresAt = max(w.expiresAt ?? now, now.addingTimeInterval(defaultExpiry(w.mode)))
        w.updatedAt = now
        cooldownUntil[id] = nil
        watchers[id] = w
        await persist(w)
        refreshEvents(w)
        arm()
        return w
    }

    /// Looks right now, however the schedule stands, and returns the watcher as it is afterwards.
    @discardableResult
    public func checkNow(_ id: String) async -> Watcher? {
        await ensureLoaded()
        guard watchers[id] != nil else { return nil }
        await WatchContext.$isManualCheck.withValue(true) { await runCheck(id) }
        arm()
        return watchers[id]
    }

    // MARK: Limits

    func defaultExpiry(_ mode: Watcher.Mode) -> TimeInterval {
        mode == .once ? WatchLimits.onceExpiry : WatchLimits.repeatExpiry
    }

    /// At most 50 watchers going, 10 from any one external agent, 5 command watchers (docs/SECURITY.md T24).
    func checkRoom(for w: Watcher) throws {
        let others = watchers.values.filter { $0.state == .active && $0.id != w.id }
        if others.count >= WatchLimits.maxActive {
            throw WatchError.limit("I'm already watching \(WatchLimits.maxActive) things. Stop one before starting another.")
        }
        if WatchSource.isExternal(w.source), others.filter({ $0.source == w.source }).count >= WatchLimits.maxActivePerExternalClient {
            throw WatchError.limit("That app already has \(WatchLimits.maxActivePerExternalClient) watchers going. Stop one first.")
        }
        if w.kind == WatchKind.command, others.filter({ $0.kind == WatchKind.command }).count >= WatchLimits.maxActiveCommands {
            throw WatchError.limit("\(WatchLimits.maxActiveCommands) command watchers are already running. Stop one first.")
        }
    }

    // MARK: Loading and saving

    func ensureLoaded() async {
        if loaded { return }
        if loadTask == nil { loadTask = Task { [store] in (try? await store.all(limit: 1000)) ?? [] } }
        let all = await loadTask?.value ?? []
        guard !loaded else { return }
        loaded = true
        for w in all where watchers[w.id] == nil { watchers[w.id] = w }
    }

    func persist(_ w: Watcher) async {
        do { try await store.save(w) } catch {
            Log.shared.error("watch", "could not save a watcher", ["error": "\(error)"])
        }
        events.changed(.watchers)
    }

    // MARK: Scheduling

    /// When the next thing needs doing: a check coming due, or a watcher reaching its expiry.
    func soonest() -> Date? {
        let now = clock.now
        var best: Date?
        for w in watchers.values where w.state == .active && !running.contains(w.id) {
            let next = min(w.nextCheckAt ?? now, w.expiresAt ?? .distantFuture)
            best = best.map { min($0, next) } ?? next
        }
        return best
    }

    /// (Re)sets the single timer. While a round of checks is running, the round re-arms when it ends.
    func arm() {
        timer?.cancel()
        timer = nil
        timerGeneration += 1
        guard started, !ticking, let next = soonest() else { return }
        let generation = timerGeneration
        let delay = max(0, next.timeIntervalSince(clock.now))
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.timerFired(generation)
        }
    }

    func timerFired(_ generation: Int) async {
        guard generation == timerGeneration, started else { return }
        timer = nil
        ticking = true
        await tick()
        ticking = false
        arm()
    }

    /// Runs every check that is due now, a few at a time. The timer calls this; tests call it directly.
    func tick() async {
        await ensureLoaded()
        let now = clock.now
        let due = watchers.values.filter { w in
            guard w.state == .active, !running.contains(w.id) else { return false }
            return (w.nextCheckAt ?? now) <= now || (w.expiresAt.map { $0 <= now } ?? false)
        }.sorted { ($0.nextCheckAt ?? .distantPast) < ($1.nextCheckAt ?? .distantPast) }.map(\.id)
        guard !due.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var waiting = due[...]
            for _ in 0..<min(Self.maxConcurrentChecks, due.count) {
                if let id = waiting.popFirst() { group.addTask { await self.runCheck(id) } }
            }
            while await group.next() != nil {
                if let id = waiting.popFirst() { group.addTask { await self.runCheck(id) } }
            }
        }
    }

    // MARK: Events

    func refreshEvents(_ w: Watcher) {
        guard let hub else { return }
        if w.state == .active, let probe = probes[w.kind] { hub.set(probe.eventTargets(for: w), for: w.id) } else { hub.remove(w.id) }
    }

    /// Something happened in a watched folder or to a watched process: check soon, but not in a rapid
    /// loop and not while a repeat watcher is cooling down.
    func handleEvents(_ ids: Set<String>) {
        guard started else { return }
        let now = clock.now
        var changed = false
        for id in ids {
            guard var w = watchers[id], w.state == .active, !running.contains(id) else { continue }
            if let until = cooldownUntil[id], until > now { continue }
            let earliest = (w.lastCheckedAt ?? .distantPast).addingTimeInterval(Self.minEventGap)
            let target = max(now, earliest)
            if (w.nextCheckAt ?? now) > target {
                w.nextCheckAt = target // in memory only; the check that follows saves the real state
                watchers[id] = w
                changed = true
            }
        }
        if changed { arm() }
    }
}
