import Foundation
import Synchronization
@testable import SidefolkCore

/// Canned HTTP answers, in order; records every request. Never touches the network.
final class FakeTransport: HTTPTransport {
    enum Reply: Sendable {
        case response(HTTPResponse)
        case failure(URLError)
    }

    private let state: Mutex<(replies: [Reply], requests: [HTTPRequest])>

    init(_ replies: [Reply]) { state = Mutex((replies, [])) }

    var requests: [HTTPRequest] { state.withLock { $0.requests } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let reply = state.withLock { s -> Reply? in
            s.requests.append(request)
            return s.replies.isEmpty ? nil : s.replies.removeFirst()
        }
        switch reply {
        case .response(let r)?: return r
        case .failure(let e)?: throw e
        case nil: throw URLError(.resourceUnavailable)
        }
    }

    static func json(_ status: Int, _ body: String, headers: [String: String] = [:]) -> Reply {
        .response(HTTPResponse(status: status, headers: headers, body: Data(body.utf8)))
    }
}

/// Records retry waits instead of sleeping.
final class DelayRecorder: Sendable {
    private let delays = Mutex<[TimeInterval]>([])
    var recorded: [TimeInterval] { delays.withLock { $0 } }
    var policy: RetryPolicy { RetryPolicy(sleep: { [self] d in delays.withLock { $0.append(d) } }) }
}

final class SettingsBox: Sendable {
    private let value: Mutex<AppSettings>
    init(_ settings: AppSettings) { value = Mutex(settings) }
    var current: AppSettings { value.withLock { $0 } }
    func update(_ change: (inout AppSettings) -> Void) { value.withLock { change(&$0) } }
}

/// Counts runs; returns a card so the loop has something to show.
final class CallCounter: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func bump() { count.withLock { $0 += 1 } }
}

func noteTool(name: String = "notes.create", risk: Risk = .low, capabilities: Set<Capability> = [], counter: CallCounter? = nil,
              untrusted: Bool = false, text: String = "Saved.") -> ProbeTool {
    ProbeTool(name: name, risk: risk, capabilities: capabilities, result: { input in
        counter?.bump()
        let title = input.string("x") ?? "note"
        return ToolResult(text: text, card: ResultCard(kind: .note, title: "Saved “\(title)”"), untrusted: untrusted)
    })
}

func brainTask(_ env: TestEnv, text: String = "Save tea", maxSteps: Int = 10, seconds: TimeInterval = 120) -> BrainTask {
    BrainTask(runId: "run-1", threadId: "thread-1", system: "System", messages: [ChatMessage(role: .user, text: text)],
              model: "test-model", maxSteps: maxSteps, deadline: env.clock.now.addingTimeInterval(seconds))
}

func toolbox(_ env: TestEnv, tainted: Bool = false, events: EventLog? = nil) -> BrainToolbox {
    BrainToolbox(runId: "run-1", specs: env.registry.specs, executor: env.executor, startTainted: tainted,
                 emit: { e in events?.append(e) })
}

final class EventLog: Sendable {
    private let events = Mutex<[AgentEvent]>([])
    func append(_ e: AgentEvent) { events.withLock { $0.append(e) } }
    var all: [AgentEvent] { events.withLock { $0 } }
}

func call(_ id: String, _ name: String = "notes_create", _ x: String = "tea") -> ToolCall {
    ToolCall(id: id, name: name, input: ["x": .string(x)])
}

func collect(_ stream: AsyncStream<AgentEvent>) async -> [AgentEvent] {
    var all: [AgentEvent] = []
    for await e in stream { all.append(e) }
    return all
}

extension AgentEvent {
    var failure: UserFacingError? { if case .failed(let e) = self { return e } else { return nil } }
    var reply: AgentReply? { if case .reply(let r) = self { return r } else { return nil } }
    var isThinking: Bool { if case .phase(.thinking) = self { return true } else { return false } }
}

extension TurnMessage {
    var plainText: String? {
        switch self {
        case .user(let text), .assistant(let text): text
        case .modelTurn, .toolResults: nil
        }
    }
}

/// 22 October 2025, 10:00 in Paris (08:00 UTC).
let parisMorning = ISO8601DateFormatter().date(from: "2025-10-22T08:00:00Z")!
let paris = TimeZone(identifier: "Europe/Paris")!
