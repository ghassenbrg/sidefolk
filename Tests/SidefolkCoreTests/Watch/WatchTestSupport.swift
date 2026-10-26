import Foundation
import Synchronization
@testable import SidefolkCore

/// Plays back canned web responses and records what was asked. When the script runs out it repeats the last step.
final class FakeFetcher: WatchFetcher {
    enum Step: Sendable {
        case page(String, status: Int, headers: [String: String])
        case fail(any Error)
    }

    private struct State {
        var script: [Step] = []
        var requests: [FetchRequest] = []
    }

    private let state = Mutex(State())

    var requests: [FetchRequest] { state.withLock { $0.requests } }

    func say(_ html: String, status: Int = 200, headers: [String: String] = ["content-type": "text/html; charset=utf-8"]) {
        state.withLock { $0.script.append(.page(html, status: status, headers: headers)) }
    }

    func fail(_ error: any Error) { state.withLock { $0.script.append(.fail(error)) } }

    /// Replaces whatever is still queued.
    func reset() { state.withLock { $0.script.removeAll() } }

    func fetch(_ request: FetchRequest) async throws -> FetchResponse {
        let step: Step = state.withLock { s in
            s.requests.append(request)
            guard let first = s.script.first else { return .page("", status: 200, headers: [:]) }
            if s.script.count > 1 { s.script.removeFirst() }
            return first
        }
        switch step {
        case .fail(let error): throw error
        case .page(let html, let status, let headers):
            var lower: [String: String] = [:]
            for (k, v) in headers { lower[k.lowercased()] = v }
            return FetchResponse(status: status, headers: lower, body: Data(html.utf8), finalURL: request.url)
        }
    }
}

/// A probe whose behaviour the test writes.
struct ScriptedProbe: WatcherProbe {
    var kind = "fake"
    var defaultInterval: TimeInterval = 600
    var minimumInterval: TimeInterval = 60
    var repeatCooldown: TimeInterval = WatchLimits.defaultCooldown
    var script: @Sendable (Watcher, Date) async throws -> ProbeResult

    func check(_ watcher: Watcher, now: Date) async throws -> ProbeResult { try await script(watcher, now) }
}

/// Counts calls from any thread.
final class Counter: Sendable {
    private let value = Mutex(0)
    @discardableResult func next() -> Int { value.withLock { $0 += 1; return $0 } }
    var count: Int { value.withLock { $0 } }
}

/// A real folder to play in, with a canonical path (no links on the way, nothing hidden). It removes itself
/// when the test that made it is done.
final class Sandbox: Sendable {
    let root: String

    init() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sf-watch-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        root = FolderAccess.canonical(dir.path)!
    }

    func path(_ name: String) -> String { root + "/" + name }

    @discardableResult
    func write(_ name: String, _ text: String = "hello", age: TimeInterval = 3600) throws -> String {
        let p = path(name)
        try FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: URL(fileURLWithPath: p))
        try setAge(name, age)
        return p
    }

    func setAge(_ name: String, _ age: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: path(name))
    }

    func remove(_ name: String) throws { try FileManager.default.removeItem(atPath: path(name)) }
    func move(_ from: String, _ to: String) throws { try FileManager.default.moveItem(atPath: path(from), toPath: path(to)) }
    func cleanUp() { try? FileManager.default.removeItem(atPath: root) }
    deinit { cleanUp() }
}

extension Watcher {
    static func make(_ kind: String, config: JSONValue = .object([:]), condition: JSONValue = .object([:]), title: String = "Test",
                     interval: TimeInterval = 0, mode: Mode = .once, source: String = "user", now: Date = TestEnv.referenceDate) -> Watcher {
        Watcher(kind: kind, title: title, config: config, condition: condition, intervalS: interval, mode: mode, source: source, now: now)
    }
}

extension WatcherProbe {
    /// Prepares a watcher the way the engine would, then returns it.
    func made(_ w: Watcher) throws -> Watcher {
        var w = w
        if w.intervalS <= 0 { w.intervalS = defaultInterval }
        return try prepare(w)
    }

    /// One check, with the result fed back as the next check's memory.
    func step(_ w: inout Watcher, at now: Date = TestEnv.referenceDate) async throws -> ProbeResult {
        let result = try await check(w, now: now)
        w.lastState = result.state
        return result
    }
}

final class OpenedLog: Sendable {
    let urls = Mutex<[URL]>([])
}

/// An isolated engine over an in-memory database, a manual clock and fake probes.
struct WatchEnv {
    let base: TestEnv
    let store: WatcherStore
    let attention: AttentionCenter
    let attentionStore: AttentionStore
    let fetcher = FakeFetcher()
    let throttle = HostThrottle()
    let opened = OpenedLog()

    var clock: ManualClock { base.clock }

    init() throws {
        base = try TestEnv()
        store = WatcherStore(base.db)
        attentionStore = AttentionStore(base.db)
        attention = AttentionCenter(store: attentionStore, events: base.events, clock: base.clock)
    }

    func engine(probes: [any WatcherProbe]? = nil, clock: (any Clock)? = nil) -> WatcherEngine {
        let opened = self.opened
        return WatcherEngine(store: store, attention: attention, events: base.events, clock: clock ?? base.clock,
                             opener: { url in opened.urls.withLock { $0.append(url) } },
                             probes: probes ?? WatchProbes.standard(fetcher: fetcher, throttle: throttle))
    }

    var openedURLs: [URL] { opened.urls.withLock { $0 } }

    func notices() async -> [AttentionItem] { (try? await attentionStore.recent()) ?? [] }
}

/// A Mac whose numbers the test sets: counters move by what each sample adds.
final class FakeSampler: SystemSampling {
    struct State {
        var uptime: TimeInterval = 1000
        var cpu = CPUTicks(busy: 0, total: 0)
        var memory: (used: UInt64, total: UInt64)? = (8 << 30, 16 << 30)
        var battery: BatteryState? = BatteryState(percent: 84, charging: true, onPower: true)
        var disk: (free: Int64, total: Int64)? = (182_000_000_000, 500_000_000_000)
        var network: (received: UInt64, sent: UInt64) = (0, 0)
        /// Added at every CPU sample: a quarter of the ticks busy by default.
        var cpuStep = CPUTicks(busy: 25, total: 100)
        var networkStep: (received: UInt64, sent: UInt64) = (2_000_000, 100_000)
        var secondsPerSample: TimeInterval = 1
        var samples = 0
    }

    let state = Mutex(State())

    func set(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }
    var samples: Int { state.withLock { $0.samples } }

    func uptime() -> TimeInterval { state.withLock { $0.uptime } }

    func cpuTicks() -> CPUTicks? {
        state.withLock { s in
            s.samples += 1
            s.uptime += s.secondsPerSample
            s.cpu = CPUTicks(busy: s.cpu.busy + s.cpuStep.busy, total: s.cpu.total + s.cpuStep.total)
            return s.cpu
        }
    }

    func memory() -> (used: UInt64, total: UInt64)? { state.withLock { $0.memory } }
    func battery() -> BatteryState? { state.withLock { $0.battery } }
    func disk() -> (free: Int64, total: Int64)? { state.withLock { $0.disk } }

    func networkBytes() -> (received: UInt64, sent: UInt64)? {
        state.withLock { s in
            s.samples += 1
            s.uptime += s.secondsPerSample
            s.network = (s.network.received + s.networkStep.received, s.network.sent + s.networkStep.sent)
            return s.network
        }
    }
}

extension WatchEnv {
    /// An engine with the standard probes over the fake web and a fake Mac, and the watch tools registered.
    func reportEngine(_ sampler: FakeSampler) -> WatcherEngine {
        let engine = engine(probes: WatchProbes.standard(fetcher: fetcher, throttle: throttle, system: sampler, settle: 0))
        base.registry.register(WatchTools.make(engine: engine, parser: { WhenParser(calendar: .current) }))
        return engine
    }
}
