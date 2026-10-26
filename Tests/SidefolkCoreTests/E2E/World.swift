import Foundation
import Synchronization
@testable import SidefolkCore

/// A whole Sidefolk core for multi-feature scenarios: the real runtime, loop, Guard, approvals, scheduler,
/// watcher engine and tools, over fakes for everything outside the process (the web, the Mac's numbers, Apple
/// Notes, the clipboard and browser). A scripted model plays the AI. "Now" is Wednesday 22 October 2025,
/// 10:00 UTC, and the calendar is UTC, so times read the same on every machine.
struct World {
    let env: TestEnv
    let notebook: NotebookStore
    let platform = RecordingPlatform()
    /// What `web.fetch` reads.
    let web = ScriptedFetcher()
    /// What watchers and reports read (pages, weather).
    let watchWeb = FakeFetcher()
    let sampler = FakeSampler()
    let notes: FakeAppleEvents
    let attention: AttentionCenter
    let settingsStore: SettingsStore
    let scheduler: ReminderScheduler
    let engine: WatcherEngine
    let settings: SettingsBox
    let model: ScriptedModel
    let runtime: AgentRuntime

    var clock: ManualClock { env.clock }
    var executor: ToolExecutor { env.executor }
    static let calendar = TimeTest.utc

    /// - Parameters:
    ///   - minute: how long a minute of an unanswered card lasts, so "skip after 10 minutes" can pass in a test.
    ///   - extraTools: registered before the runtime offers its tools (an extension host's, say).
    init(_ steps: [ScriptedModel.Step], mode: GuardMode = .askOncePerKind, unanswered: UnansweredRule = UnansweredRule(),
         minute: TimeInterval = 60, notes fixture: NotesFixture = .sample(), env given: TestEnv? = nil) async throws {
        env = try given ?? TestEnv(now: TimeTest.wednesday10, minute: minute)
        try await env.permissions.setPolicy(GuardPolicy(mode: mode, unanswered: unanswered))
        notebook = NotebookStore(env.db)
        notes = FakeAppleEvents(fixture)
        attention = AttentionCenter(store: AttentionStore(env.db), events: env.events, clock: env.clock)
        settingsStore = await SettingsStore(db: env.db, events: env.events)
        scheduler = ReminderScheduler(store: ReminderStore(env.db), attention: attention, events: env.events, settings: settingsStore,
                                      clock: env.clock, calendar: Self.calendar)
        engine = WatcherEngine(store: WatcherStore(env.db), attention: attention, events: env.events, clock: env.clock,
                               probes: WatchProbes.standard(fetcher: watchWeb, throttle: HostThrottle(), system: sampler, settle: 0))
        let calendar = Self.calendar
        env.registry.register(BuiltinTools.make(notebook: notebook, platform: platform, events: env.events, fetcher: web))
        env.registry.register(ReminderTools.make(scheduler: scheduler, parser: { TimeTest.parser(calendar) }))
        env.registry.register(WatchTools.make(engine: engine, parser: { TimeTest.parser(calendar) }))
        env.registry.register(MacAppTools.make(runner: notes, notebook: notebook, events: env.events, ledger: AppleNotesLedger(db: env.db),
                                               clock: env.clock))

        var s = AppSettings()
        s.provider.kind = .anthropic
        settings = SettingsBox(s)
        let model = ScriptedModel(steps)
        self.model = model
        let clock = env.clock
        let factory = BrainFactory { _, _ in BrainChoice(backend: LoopBackend(model: model, checkModel: "m", clock: clock), model: "test-model") }
        let context = ContextBuilder(notebook: notebook, exchanges: ExchangeStore(env.db), clock: clock, timeZone: calendar.timeZone)
        let box = settings
        runtime = AgentRuntime(executor: env.executor, db: env.db, events: env.events, context: context, factory: factory,
                               settings: { box.current }, clock: clock)
    }

    /// Sends a request as the Ask panel does and waits for the run to end.
    func ask(_ text: String, spoken: Bool = false, newThread: Bool = true) async -> [AgentEvent] {
        let handle = await runtime.submit(AgentRequest(text: text, newThread: newThread, spoken: spoken))
        return await collect(handle.events)
    }

    func activity() async throws -> [ActivityEntry] { try await env.activity.recent() }
}

/// Answers every card the same way as it appears, and remembers the cards, like a person at the screen.
final class Person: Sendable {
    private let cards = Shared<[ApprovalRequest]>([])
    private let task: Task<Void, Never>

    init(_ env: TestEnv, answer: ApprovalDecision = .allowOnce) {
        let stream = env.events.stream()
        let broker = env.broker
        let cards = self.cards
        task = Task {
            for await event in stream {
                if case .approvalRequested(let r) = event {
                    cards.change { $0.append(r) }
                    await broker.resolve(id: r.id, decision: answer)
                }
            }
        }
    }

    var seen: [ApprovalRequest] { cards.value }

    func leave() { task.cancel() }
}

/// Moves the clock while a card waits, as if the person were away that long, and remembers the card.
final class Away: Sendable {
    private let card = Shared<ApprovalRequest?>(nil)
    private let task: Task<Void, Never>

    init(_ env: TestEnv, for seconds: TimeInterval) {
        let stream = env.events.stream()
        let clock = env.clock
        let card = self.card
        task = Task {
            for await e in stream {
                if case .approvalRequested(let r) = e {
                    card.change { $0 = r }
                    clock.advance(seconds)
                    return
                }
            }
        }
    }

    var missed: ApprovalRequest? { card.value }

    func back() { task.cancel() }
}

/// A value several tasks read and change.
final class Shared<T: Sendable>: Sendable {
    private let state: Mutex<T>
    init(_ value: T) { state = Mutex(value) }
    var value: T { state.withLock { $0 } }
    func change(_ edit: (inout T) -> Void) { state.withLock { edit(&$0) } }
}

extension Array where Element == AgentEvent {
    var replyText: String? { compactMap(\.reply).first?.text }
}
