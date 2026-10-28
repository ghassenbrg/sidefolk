import Foundation

public struct AgentRequest: Sendable {
    public var text: String
    public var attachment: AgentAttachment?
    /// The conversation to continue: one named here (an answer's Reply, Home › Conversations) continues
    /// for as long as its history is kept (D45); nil continues the current conversation while it was
    /// active in the last 10 minutes.
    public var threadId: String?
    public var thinkHarder: Bool
    /// Start a fresh conversation even if one is open.
    public var newThread: Bool
    /// Said aloud with the talk key: the first sentence of the answer will be spoken (D34).
    public var spoken: Bool

    public init(text: String, attachment: AgentAttachment? = nil, threadId: String? = nil, thinkHarder: Bool = false,
                newThread: Bool = false, spoken: Bool = false) {
        self.text = text
        self.attachment = attachment
        self.threadId = threadId
        self.thinkHarder = thinkHarder
        self.newThread = newThread
        self.spoken = spoken
    }
}

public struct AgentRunHandle: Sendable {
    public let runId: String
    public let threadId: String
    /// Ends after `.finished`.
    public let events: AsyncStream<AgentEvent>
}

public struct AgentLimits: Sendable, Hashable {
    public var maxSteps: Int
    public var runSeconds: TimeInterval
    /// A conversation stays open this long after its last activity.
    public var threadWindow: TimeInterval

    public init(maxSteps: Int = 10, runSeconds: TimeInterval = 120, threadWindow: TimeInterval = 600) {
        self.maxSteps = maxSteps
        self.runSeconds = runSeconds
        self.threadWindow = threadWindow
    }

    public static let standard = AgentLimits()
}

/// Exactly what a run started with, for the Privacy page ("what Sidefolk last sent").
public struct ContextPreview: Sendable, Equatable {
    public var provider: String
    public var model: String
    public var system: String
    public var messages: [ChatMessage]
    /// Model-facing tool names offered with the request.
    public var tools: [String]
    public var tainted: Bool
    public var at: Date
}

/// Handles the user's requests to the agent: picks the brain, builds the context, runs the backend
/// with a per-run toolbox, streams `AgentEvent`s (also published on the EventBus), stores the short
/// exchange history and an `AgentRun` record.
///
/// Requests on the same conversation run one at a time, in order: a new request waits for the one
/// in flight, so nothing the user asked for is dropped, and it sees that request's outcome in its
/// history. Stop is explicit: `cancel(runId:)` or `cancelAll()`.
public actor AgentRuntime {
    private let executor: ToolExecutor
    private let exchanges: ExchangeStore
    private let runs: AgentRunStore
    private let events: EventBus
    private let context: ContextBuilder
    private let factory: BrainFactory
    private let settings: @Sendable () -> AppSettings
    private let clock: any Clock
    private let limits: AgentLimits
    private let excludedTools: Set<String>

    private var threadActivity: [String: Date] = [:]
    private var currentThread: String?
    private var running: [String: Task<Void, Never>] = [:]
    /// The conversation of each run in flight, so deleting a conversation can stop its runs first.
    private var runThreads: [String: String] = [:]
    private var tails: [String: Task<Void, Never>] = [:]
    private var lastPreview: ContextPreview?
    private var lastPreviewThread: String?

    /// - Parameter excludedTools: registry tools the agent is never offered. None are excluded today:
    ///   every tool already passes Guard as `Caller.agent`, which is what keeps it in bounds.
    public init(executor: ToolExecutor, db: AppDatabase, events: EventBus, context: ContextBuilder, factory: BrainFactory,
                settings: @escaping @Sendable () -> AppSettings, clock: any Clock = SystemClock(), limits: AgentLimits = .standard,
                excludedTools: Set<String> = []) {
        self.executor = executor
        exchanges = ExchangeStore(db)
        runs = AgentRunStore(db)
        self.events = events
        self.context = context
        self.factory = factory
        self.settings = settings
        self.clock = clock
        self.limits = limits
        self.excludedTools = excludedTools
    }

    public func handle(_ request: AgentRequest) async -> AsyncStream<AgentEvent> { await submit(request).events }

    public func submit(_ request: AgentRequest) async -> AgentRunHandle {
        let kept = await isKept(request)
        let now = clock.now
        let threadId = resolveThread(request, now: now, kept: kept)
        let runId = Identifier.make(now: now)
        let (stream, continuation) = AsyncStream.makeStream(of: AgentEvent.self, bufferingPolicy: .unbounded)
        let previous = tails[threadId]
        let task = Task {
            await self.execute(runId: runId, threadId: threadId, request: request, after: previous, continuation: continuation)
        }
        running[runId] = task
        runThreads[runId] = threadId
        tails[threadId] = task
        return AgentRunHandle(runId: runId, threadId: threadId, events: stream)
    }

    /// Stops a run. A run still waiting behind another one on its conversation stops when it gets its turn.
    public func cancel(runId: String) { running[runId]?.cancel() }

    public func cancelAll() { for task in running.values { task.cancel() } }

    /// The open conversation, if it was active within the thread window.
    public var activeThreadId: String? {
        guard let id = currentThread, isActive(id, now: clock.now) else { return nil }
        return id
    }

    /// The next request starts a fresh conversation; earlier ones stay in the history (D45).
    public func endThread() { currentThread = nil }

    /// Forgets one conversation: its runs stop, its exchanges are deleted, and it is never continued.
    /// Activity keeps its own record of what was done, as it does for everything (D45).
    public func deleteConversation(_ threadId: String) async throws {
        for (run, thread) in runThreads where thread == threadId { running[run]?.cancel() }
        // A stopped run still writes its last note; the deletion comes after it.
        await tails[threadId]?.value
        if currentThread == threadId { currentThread = nil }
        threadActivity[threadId] = nil
        if lastPreviewThread == threadId { lastPreview = nil }
        try await exchanges.delete(threadId: threadId)
        events.changed(.conversations)
    }

    /// Forgets every conversation, including the one in progress.
    public func deleteAllConversations() async throws {
        cancelAll()
        for tail in Array(tails.values) { await tail.value }
        currentThread = nil
        threadActivity = [:]
        lastPreview = nil
        try await exchanges.deleteAll()
        events.changed(.conversations)
    }

    public func lastSent() -> ContextPreview? { lastPreview }

    /// What a request would send right now, without running it.
    public func preview(_ request: AgentRequest) async -> ContextPreview {
        let current = settings()
        let choice = try? factory.make(current.provider, thinkHarder: request.thinkHarder)
        let kept = await isKept(request)
        let now = clock.now
        let threadId: String? = if request.newThread {
            nil
        } else if let wanted = request.threadId {
            kept || isActive(wanted, now: now) ? wanted : nil
        } else {
            currentThread.flatMap { isActive($0, now: now) ? $0 : nil }
        }
        let built = await context.build(text: request.text, attachment: request.attachment, threadId: threadId,
                                        thinkHarder: request.thinkHarder, spoken: request.spoken, settings: current, tools: offeredTools())
        return ContextPreview(provider: choice?.backend.providerName ?? current.provider.kind.displayName,
                              model: choice.map { $0.model.isEmpty ? "default" : $0.model } ?? "", system: built.system,
                              messages: built.messages, tools: offeredTools().map(\.modelName), tainted: built.tainted, at: clock.now)
    }

    /// Settings › AI status: the free check (binary, sign-in, key, model list), never a prompt.
    public func checkProvider(_ provider: ProviderSettings? = nil) async -> Result<String, UserFacingError> {
        do {
            let choice = try factory.make(provider ?? settings().provider, thinkHarder: false)
            return await choice.backend.check()
        } catch {
            return .failure(error)
        }
    }

    /// Settings › AI "Test", only on the user's click: the free check, then one tiny request without
    /// tools, which counts toward the user's usage. Nothing is stored.
    public func testProvider(_ provider: ProviderSettings? = nil) async -> Result<String, UserFacingError> {
        let provider = provider ?? settings().provider
        if case .failure(let error) = await checkProvider(provider) { return .failure(error) }
        let choice: BrainChoice
        do { choice = try factory.make(provider, thinkHarder: false) } catch { return .failure(error) }
        let start = clock.now
        let runId = "test-" + Identifier.make(now: start)
        let task = BrainTask(runId: runId, threadId: runId, system: "You check that a connection works. Answer with one word.",
                             messages: [ChatMessage(role: .user, text: "Reply with the word ok.")], model: choice.model,
                             effort: choice.effort, maxSteps: 1, deadline: start.addingTimeInterval(60))
        let toolbox = BrainToolbox(runId: runId, specs: [], executor: executor, emit: { _ in })
        defer { _ = (choice.backend as? any BrainUsageReporting)?.takeUsage(runId: runId) }
        do {
            let reply = try await choice.backend.run(task, toolbox: toolbox, emit: { _ in })
            await toolbox.close()
            let seconds = clock.now.timeIntervalSince(start).formatted(.number.precision(.fractionLength(1)).locale(Wording.locale))
            let answer = reply.text.clipped(30)
            let provider = choice.backend.providerName
            return .success(choice.model.isEmpty
                ? String(localized: "\(provider) answered “\(answer)” in \(seconds) s using its default model.")
                : String(localized: "\(provider) answered “\(answer)” in \(seconds) s using \(choice.model)."))
        } catch {
            await toolbox.close()
            return .failure(Self.userFacing(error, changed: false, provider: choice.backend.providerName))
        }
    }

    /// Deletes conversation history older than `historyDays`. Call it at launch and once a day.
    @discardableResult
    public func purgeHistory() async -> Int {
        let days = max(1, settings().historyDays)
        return (try? await exchanges.purge(olderThan: clock.now.addingTimeInterval(-Double(days) * 86_400))) ?? 0
    }

    // MARK: Running

    private func execute(runId: String, threadId: String, request: AgentRequest, after previous: Task<Void, Never>?,
                         continuation: AsyncStream<AgentEvent>.Continuation) async {
        let bus = events
        let emit: @Sendable (AgentEvent) -> Void = { event in
            continuation.yield(event)
            bus.publish(.agent(threadId: threadId, event))
        }
        func end() {
            emit(.finished(runId: runId))
            continuation.finish()
            if let mine = running.removeValue(forKey: runId), tails[threadId] == mine { tails[threadId] = nil }
            runThreads[runId] = nil
            threadActivity[threadId] = clock.now
            events.changed(.conversations)
        }

        await previous?.value
        if Task.isCancelled {
            emit(.failed(Self.userFacing(CancellationError(), changed: false)))
            return end()
        }

        if request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, request.attachment?.text.isEmpty ?? true {
            emit(.failed(UserFacingError("There's nothing for me to work on yet.", recovery: "Type a request, or drop something on me.")))
            return end()
        }

        let current = settings()
        let choice: BrainChoice
        do {
            choice = try factory.make(current.provider, thinkHarder: request.thinkHarder)
        } catch {
            emit(.failed(error))
            return end()
        }

        let specs = offeredTools()
        let built = await context.build(text: request.text, attachment: request.attachment, threadId: threadId,
                                        thinkHarder: request.thinkHarder, spoken: request.spoken, settings: current, tools: specs)
        let provider = choice.backend.providerName
        let model = choice.model.isEmpty ? "default" : choice.model
        let start = clock.now
        lastPreview = ContextPreview(provider: provider, model: model, system: built.system, messages: built.messages,
                                     tools: specs.map(\.modelName), tainted: built.tainted, at: start)
        lastPreviewThread = threadId

        let exchanges = self.exchanges, runs = self.runs
        var record = AgentRun(id: runId, threadId: threadId, provider: provider, model: model, now: start)
        let opened = record
        await persist { try await runs.save(opened) }
        emit(.started(runId: runId, provider: provider, model: model))
        let asked = Exchange(threadId: threadId, role: .user, content: request.text.trimmingCharacters(in: .whitespacesAndNewlines),
                             meta: ExchangeMeta.user(attachment: request.attachment, tainted: built.tainted, spoken: request.spoken), now: start)
        await persist { try await exchanges.append(asked) }
        events.changed(.conversations)

        let toolbox = BrainToolbox(runId: runId, specs: specs, executor: executor, startTainted: built.tainted,
                                   mentions: Self.mentions(in: request), emit: emit)
        let task = BrainTask(runId: runId, threadId: threadId, system: built.system, messages: built.messages, model: choice.model,
                             effort: choice.effort, maxSteps: limits.maxSteps, deadline: start.addingTimeInterval(limits.runSeconds))
        var outcome = "ok"
        var errorText: String?
        do {
            // The backend runs on its own task so the toolbox can end it: when nobody answered a card
            // and the person's setting says to stop the task (D37).
            let backend = choice.backend
            let work = Task { try await backend.run(task, toolbox: toolbox, emit: emit) }
            toolbox.onStop { work.cancel() }
            var reply = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            reply.tainted = toolbox.isTainted
            emit(.reply(reply))
            let answered = Exchange(threadId: threadId, role: .assistant, content: reply.text,
                                    meta: ExchangeMeta.assistant(runId: runId, cards: reply.cards, tainted: toolbox.isTainted),
                                    now: later(than: asked))
            await persist { try await exchanges.append(answered) }
        } catch {
            let unanswered = toolbox.stoppedUnanswered && error is CancellationError
            let failure = Self.userFacing(unanswered ? Self.unansweredStop : error, changed: changedSomething(toolbox), provider: provider)
            outcome = unanswered ? "unanswered" : error is CancellationError ? "cancelled" : "failed"
            errorText = Redactor.redact(failure.detail ?? failure.message).clipped(300)
            emit(.failed(failure))
            let note = Exchange(threadId: threadId, role: .event, content: failure.message,
                                meta: ["runId": .string(runId), "outcome": .string(outcome)], now: later(than: asked))
            await persist { try await exchanges.append(note) }
        }
        await toolbox.close()

        let usage = (choice.backend as? any BrainUsageReporting)?.takeUsage(runId: runId)
        if outcome == "ok", let limit = usage?.limit { outcome = "limit:\(limit)" }
        record.endedAt = clock.now
        record.steps = usage?.steps ?? 0
        record.inputTokens = usage?.inputTokens ?? 0
        record.outputTokens = usage?.outputTokens ?? 0
        record.outcome = outcome
        record.error = errorText
        let closed = record
        await persist { try await runs.save(closed) }
        events.changed(.runs)
        Log.shared.info("brain", "run \(outcome)", ["run": runId, "provider": provider, "model": model,
                                                     "steps": String(record.steps), "tools": String(usage?.toolCalls ?? 0)])
        end()
    }

    /// Records must land even for a cancelled run, and GRDB's async access throws once its task is cancelled.
    private nonisolated func persist(_ work: @escaping @Sendable () async throws -> Void) async {
        await Task.detached { try? await work() }.value
    }

    /// Links the user typed: the request itself and an attachment they wrote, never dropped content.
    static func mentions(in request: AgentRequest) -> UserMentions {
        var typed = request.text
        if let a = request.attachment, !a.untrusted { typed += "\n" + a.text }
        return UserMentions(text: typed)
    }

    private func offeredTools() -> [ToolSpec] {
        executor.registry.specs.filter { !excludedTools.contains($0.name) }
    }

    /// A conversation the request names that is quiet now but whose history is still kept: it continues (D45).
    private func isKept(_ request: AgentRequest) async -> Bool {
        guard !request.newThread, let wanted = request.threadId, !isActive(wanted, now: clock.now) else { return false }
        return (try? await exchanges.contains(threadId: wanted)) ?? false
    }

    private func resolveThread(_ request: AgentRequest, now: Date, kept: Bool) -> String {
        threadActivity = threadActivity.filter { now.timeIntervalSince($0.value) < limits.threadWindow || tails[$0.key] != nil }
        let id: String
        if request.newThread {
            id = Identifier.make(now: now)
        } else if let wanted = request.threadId, kept || isActive(wanted, now: now) {
            id = wanted
        } else if request.threadId == nil, let current = currentThread, isActive(current, now: now) {
            id = current
        } else {
            id = Identifier.make(now: now)
        }
        threadActivity[id] = now
        currentThread = id
        return id
    }

    private func isActive(_ threadId: String, now: Date) -> Bool {
        guard let last = threadActivity[threadId] else { return false }
        return now.timeIntervalSince(last) < limits.threadWindow
    }

    /// Exchanges sort by time; the reply must land after the request even with a frozen test clock.
    private func later(than exchange: Exchange) -> Date {
        max(clock.now, exchange.createdAt.addingTimeInterval(0.001))
    }

    private func changedSomething(_ toolbox: BrainToolbox) -> Bool {
        toolbox.outcomes.contains { $0.isOK && (executor.registry.tool(named: $0.activity.tool)?.spec.mutates ?? true) }
    }

    /// How a run ends when nobody answered a card and the person's setting says to stop (D37).
    static var unansweredStop: UserFacingError {
        UserFacingError("I stopped: you didn't answer in time. Nothing was changed.",
                        recovery: "The step I asked about is in Now, where you can still run it.", detail: "unanswered")
    }

    /// Every failure the user sees is worded for them; raw errors stay in `detail` for diagnostics.
    static func userFacing(_ error: Error, changed: Bool, provider: String = String(localized: "the AI service")) -> UserFacingError {
        var e: UserFacingError
        switch error {
        case let u as UserFacingError: e = u
        case is CancellationError: e = UserFacingError("Stopped. Nothing was changed.")
        case is TimeoutError:
            e = UserFacingError("That took too long, so I stopped. Nothing was changed.", recovery: "Try again, or ask for something smaller.")
        case is URLError: e = ProviderHTTP.networkError(error, provider: provider, local: false)
        default:
            e = UserFacingError("Something went wrong while I was thinking. Nothing was changed.", recovery: "Try again in a moment.",
                                detail: String(describing: error))
        }
        if changed {
            e.changedNothing = false
            // The sentence ends many messages; drop it in whichever language the message is in (the
            // glossary keeps its translation identical everywhere, and CatalogTests checks that).
            e.message = Wording.sentences([
                Wording.droppingNothingChanged(from: e.message),
                String(localized: "Some of it was already done; Activity shows what."),
            ])
        }
        return e
    }
}
