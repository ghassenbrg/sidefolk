import Foundation
import Synchronization

/// Per-run limits on top of `BrainTask.maxSteps` and `deadline` (docs/SECURITY.md T5).
public struct LoopLimits: Sendable, Hashable {
    /// Tool calls one request may make in total.
    public var maxToolCalls: Int
    /// How often the same call (tool + arguments) may run; asking once more stops the run.
    public var maxIdenticalCalls: Int
    public var maxOutputTokens: Int

    public init(maxToolCalls: Int = 25, maxIdenticalCalls: Int = 2, maxOutputTokens: Int = 8192) {
        self.maxToolCalls = maxToolCalls
        self.maxIdenticalCalls = maxIdenticalCalls
        self.maxOutputTokens = maxOutputTokens
    }

    public static let standard = LoopLimits()
}

/// What a run cost, for `AgentRun` records.
public struct BrainUsage: Sendable, Hashable {
    /// Model calls.
    public var steps = 0
    public var inputTokens = 0
    public var outputTokens = 0
    public var toolCalls = 0
    /// Set when a limit ended the run: "steps", "deadline", "repeat", "tools".
    public var limit: String?
    public init() {}
}

/// A backend that can say what a finished run cost. The runtime asks once per run; Claude Code's
/// backend can adopt it too.
public protocol BrainUsageReporting: Sendable {
    func takeUsage(runId: String) -> BrainUsage?
}

/// Drives a `TurnModel` through the tool loop: ask the model, run the tools it calls through the
/// toolbox (and so through Guard), hand back the results, repeat until it answers or a limit hits.
public struct LoopBackend: BrainBackend, BrainUsageReporting {
    public let model: any TurnModel
    /// The model `check()` verifies.
    public let checkModel: String
    public let limits: LoopLimits
    private let clock: any Clock
    private let ledger = UsageLedger()

    public init(model: any TurnModel, checkModel: String, limits: LoopLimits = .standard, clock: any Clock = SystemClock()) {
        self.model = model
        self.checkModel = checkModel
        self.limits = limits
        self.clock = clock
    }

    public var providerName: String { model.providerName }

    public func check() async -> Result<String, UserFacingError> { await model.check(model: checkModel) }

    public func takeUsage(runId: String) -> BrainUsage? { ledger.take(runId) }

    public func run(_ task: BrainTask, toolbox: BrainToolbox, emit: @escaping @Sendable (AgentEvent) -> Void) async throws -> AgentReply {
        var usage = BrainUsage()
        defer { ledger.put(task.runId, usage) }
        var transcript: [TurnMessage] = task.messages.map { $0.role == .user ? .user($0.text) : .assistant($0.text) }
        var outcomes: [ToolOutcome] = []
        var seen: [String: Int] = [:]
        let model = self.model

        while true {
            try Task.checkCancellation()
            if usage.steps >= task.maxSteps {
                usage.limit = "steps"
                return Self.stopped(.steps, outcomes: outcomes, limits: limits)
            }
            // Time spent waiting for the person's answers isn't the run's (D37).
            let remaining = (toolbox.deadline(from: task.deadline) ?? .distantFuture).timeIntervalSince(clock.now)
            if remaining <= 0 {
                usage.limit = "deadline"
                return try Self.timedOut(outcomes, limits: limits)
            }

            emit(.phase(.thinking))
            let request = TurnRequest(model: task.model, system: task.system, messages: transcript, tools: toolbox.specs,
                                      maxOutputTokens: limits.maxOutputTokens, timeBudget: remaining)
            let turn: ModelTurn
            do {
                turn = try await withTimeout(remaining) { try await model.respond(to: request) }
            } catch is TimeoutError {
                usage.limit = "deadline"
                return try Self.timedOut(outcomes, limits: limits)
            } catch let error as UserFacingError {
                // Work already done must not be reported as "nothing changed".
                guard outcomes.contains(where: \.isOK) else { throw error }
                return Self.interrupted(by: error, outcomes: outcomes)
            }
            usage.steps += 1
            usage.inputTokens += turn.usage.input
            usage.outputTokens += turn.usage.output

            // A turn cut off by the output limit may hold a truncated tool call; never run it.
            let calls = turn.stop == .maxTokens ? [] : turn.toolCalls
            if calls.isEmpty { return Self.answer(turn, outcomes: outcomes) }

            transcript.append(.modelTurn(turn))
            var results: [ToolResultMessage] = []
            var stop: StopReason?
            for call in calls {
                if stop != nil {
                    results.append(ToolResultMessage(callId: call.id, name: call.name, content: "Not run: the request stopped.", isError: true))
                    continue
                }
                try Task.checkCancellation()
                if usage.toolCalls >= limits.maxToolCalls {
                    stop = .tools
                    results.append(ToolResultMessage(callId: call.id, name: call.name, content: "Not run: too many actions.", isError: true))
                    continue
                }
                if let bad = call.invalidArguments {
                    let content = "Failed: the arguments were not a JSON object (\(bad)). Send them again as a JSON object."
                    results.append(ToolResultMessage(callId: call.id, name: call.name, content: content, isError: true))
                    continue
                }
                let key = "\(call.name) \(call.input.jsonString)"
                let count = seen[key, default: 0]
                if count >= limits.maxIdenticalCalls {
                    stop = .repeated
                    results.append(ToolResultMessage(callId: call.id, name: call.name, content: "Not run: this exact call already ran.", isError: true))
                    continue
                }
                seen[key] = count + 1
                let outcome = await toolbox.call(call.name, input: call.input)
                usage.toolCalls += 1
                outcomes.append(outcome)
                results.append(ToolResultMessage(callId: call.id, name: call.name, content: outcome.promptText, isError: !outcome.isOK))
            }
            transcript.append(.toolResults(results))
            if let stop {
                usage.limit = stop.rawValue
                return Self.stopped(stop, outcomes: outcomes, limits: limits)
            }
        }
    }

    // MARK: Replies
    //
    // What the person reads when the model said nothing of its own, in the app's language (D28).

    enum StopReason: String { case steps, deadline, repeated = "repeat", tools }

    static func answer(_ turn: ModelTurn, outcomes: [ToolOutcome]) -> AgentReply {
        let cards = Self.cards(outcomes)
        var text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            switch turn.stop {
            case .refusal: text = String(localized: "I can't help with that one.")
            case .maxTokens: text = String(localized: "My answer got cut off before I could finish. Try asking for less at once.")
            default:
                text = outcomes.contains(where: \.isOK) ? (cards.isEmpty ? String(localized: "Done.") : "")
                    : String(localized: "I don't have an answer for that.")
            }
        }
        return AgentReply(text: text, cards: cards)
    }

    static func stopped(_ reason: StopReason, outcomes: [ToolOutcome], limits: LoopLimits) -> AgentReply {
        let lead = switch reason {
        case .steps: String(localized: "I ran out of steps before finishing.")
        case .deadline: String(localized: "That was taking too long, so I stopped.")
        case .repeated: String(localized: "I stopped because I kept repeating the same step.")
        case .tools: String(localized: "I stopped after \(limits.maxToolCalls) actions, my limit for one request.")
        }
        let done = progress(outcomes)
        return AgentReply(text: done.isEmpty ? String(localized: "\(lead) Nothing was changed.", comment: "Why I stopped, then this sentence")
                              : String(localized: "\(lead) \(done)", comment: "Why I stopped, then what was done: two sentences"),
                          cards: cards(outcomes))
    }

    static func timedOut(_ outcomes: [ToolOutcome], limits: LoopLimits) throws(UserFacingError) -> AgentReply {
        guard outcomes.contains(where: \.isOK) else {
            throw UserFacingError("That took too long, so I stopped. Nothing was changed.", recovery: "Try again, or ask for something smaller.",
                                  detail: "deadline")
        }
        return stopped(.deadline, outcomes: outcomes, limits: limits)
    }

    static func interrupted(by error: UserFacingError, outcomes: [ToolOutcome]) -> AgentReply {
        // Something was done, so the ending that says nothing changed goes, in either language.
        var problem = error.message
        for ending in [" " + String(localized: "Nothing was changed."), " Nothing was changed."] {
            problem = problem.replacingOccurrences(of: ending, with: "")
        }
        return AgentReply(text: String(localized: "\(progress(outcomes)) Then something went wrong: \(problem)",
                                       comment: "What was done (“Done so far: …”), then the error"),
                          cards: cards(outcomes))
    }

    /// "Done so far: Saved “Tea ideas”; Reminder at 9:00." from the successful calls.
    static func progress(_ outcomes: [ToolOutcome]) -> String {
        var lines: [String] = []
        for o in outcomes where o.isOK {
            let line = o.activity.card?.title ?? o.activity.summary
            if !line.isEmpty, !lines.contains(line) { lines.append(line) }
        }
        guard !lines.isEmpty else { return "" }
        let shown = lines.prefix(4).joined(separator: "; ")
        return lines.count > 4 ? String(localized: "Done so far: \(String(localized: "\(shown) and \(lines.count - 4) more")).")
            : String(localized: "Done so far: \(shown).")
    }

    static func cards(_ outcomes: [ToolOutcome]) -> [ResultCard] {
        var cards: [ResultCard] = []
        for o in outcomes {
            if case .ok(let r) = o.status, let card = r.card, !cards.contains(card) { cards.append(card) }
        }
        return cards
    }
}

final class UsageLedger: Sendable {
    private let entries = Mutex<[String: BrainUsage]>([:])
    func put(_ runId: String, _ usage: BrainUsage) { entries.withLock { $0[runId] = usage } }
    func take(_ runId: String) -> BrainUsage? { entries.withLock { $0.removeValue(forKey: runId) } }
}
