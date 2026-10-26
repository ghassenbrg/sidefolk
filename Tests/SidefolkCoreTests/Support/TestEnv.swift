import Foundation
@testable import SidefolkCore

/// An isolated Sidefolk core for tests: in-memory database, temp home folder, manual clock.
/// Never points at the user's real files or agent configs.
struct TestEnv {
    let db: AppDatabase
    let events = EventBus()
    let clock: ManualClock
    let registry = ToolRegistry()
    let permissions: PermissionStore
    let broker: ApprovalBroker
    let activity: ActivityStore
    let executor: ToolExecutor
    let home: URL

    /// - Parameter minute: how long a minute of an unanswered approval lasts, so "10 minutes" can pass in a test.
    init(now: Date = TestEnv.referenceDate, minute: TimeInterval = 60) throws {
        db = try AppDatabase.inMemory()
        clock = ManualClock(now)
        permissions = PermissionStore(db)
        broker = ApprovalBroker(events: events)
        activity = ActivityStore(db)
        executor = ToolExecutor(registry: registry, permissions: permissions, broker: broker, activity: activity,
                                events: events, clock: clock, minute: minute)
        home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    /// Wednesday 22 October 2025, 10:00 in the current time zone.
    static var referenceDate: Date {
        var c = DateComponents()
        c.year = 2025; c.month = 10; c.day = 22; c.hour = 10; c.minute = 0
        return Calendar.current.date(from: c)!
    }

    /// Answers the next approval request with `decision` as soon as it appears.
    func autoAnswer(_ decision: ApprovalDecision) -> Task<ApprovalRequest?, Never> {
        let stream = events.stream()
        let broker = self.broker
        return Task {
            for await e in stream {
                if case .approvalRequested(let r) = e {
                    await broker.resolve(id: r.id, decision: decision)
                    return r
                }
            }
            return nil
        }
    }
}

/// A configurable tool for exercising Guard and the executor.
struct ProbeTool: Tool {
    var spec: ToolSpec
    var scopeFor: @Sendable (JSONValue) -> ToolScope = { _ in .none }
    var result: @Sendable (JSONValue) async throws -> ToolResult = { _ in ToolResult(text: "ok") }

    init(name: String = "test.probe", risk: Risk, capabilities: Set<Capability> = [], mutates: Bool = true,
         required: [String] = [], scope: @escaping @Sendable (JSONValue) -> ToolScope = { _ in .none },
         result: @escaping @Sendable (JSONValue) async throws -> ToolResult = { _ in ToolResult(text: "ok") }) {
        spec = ToolSpec(name: name, title: "Probe", description: "Test tool",
                        inputSchema: Schema.object(["x": Schema.string("x")], required: required),
                        risk: risk, capabilities: capabilities, category: .system, mutates: mutates)
        scopeFor = scope
        self.result = result
    }

    func summary(for input: JSONValue) -> String { "Probe \(input.string("x") ?? "")" }
    func scope(for input: JSONValue) -> ToolScope { scopeFor(input) }
    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult { try await result(input) }
}
