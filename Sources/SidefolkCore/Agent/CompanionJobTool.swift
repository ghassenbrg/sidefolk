import Foundation
import Synchronization

/// Where the companion's brain is, once the app has made it: the runtime is assembled first.
public final class CompanionAgentSlot: Sendable {
    private let agent = Mutex<AgentRuntime?>(nil)

    public init() {}
    public func use(_ runtime: AgentRuntime) { agent.withLock { $0 = runtime } }
    var current: AgentRuntime? { agent.withLock { $0 } }
}

/// `companion.job`: hands the companion a whole job, written out, to do with its tools (D128). It runs as any request to it does, in a conversation of its own, under the person's
/// own trust settings, so each thing it does passes Guard as Sidefolk's agent and shows in History. Never offered to the model: it can't start one of itself.
struct CompanionJobTool: Tool {
    static let name = "companion.job"
    /// As long as a job may take before whoever asked stops waiting: the turn itself keeps to the agent's own limits.
    static let seconds: TimeInterval = 300

    let agent: CompanionAgentSlot

    var spec: ToolSpec {
        ToolSpec(
            name: Self.name, title: String(localized: "Let your companion do a job", comment: "A tool: hands the companion a whole job to do with its tools"),
            description: "Hands the companion a job, in words, to do with its own tools under the person's trust settings. It returns what the companion answers.",
            inputSchema: Schema.object(["job": Schema.string("The job, in plain words.")], required: ["job"]),
            risk: .medium, capabilities: [.system], category: .agents, mutates: true, external: false, timeout: Self.seconds, offeredToModel: false)
    }

    /// As long as a card shows in full, with room for its words around it: what it can't show can't be asked for.
    static let longest = 200

    func summary(for input: JSONValue) -> String {
        String(localized: "Let your companion: \(ToolFormat.oneLine(ExtensionText.clean(input.string("job") ?? ""), Self.longest))", comment: "A tool's row: “Let your companion: tidy my Downloads”")
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope() }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let job = input.string("job")?.trimmingCharacters(in: .whitespacesAndNewlines), !job.isEmpty else { throw ToolError.invalidInput("Say what the job is.") }
        guard job.count <= Self.longest, ExtensionPlanRules.plain(job) else { throw ToolError.invalidInput("A job is at most \(Self.longest) plain characters, so a card can show all of it.") }
        guard let agent = agent.current else { throw ToolError.unavailable("The companion can't take a job right now.") }
        // Only words the person read on a plan count as clean; anything else may have come from outside.
        let handle = await agent.submit(AgentRequest(text: job, job: AgentRequest.Job(read: context.onPlan)))
        return try await withTaskCancellationHandler {
            var answer: String?
            for await event in handle.events {
                switch event {
                case .reply(let reply): answer = reply.text
                case .failed(let problem): throw ToolError.unavailable(problem.message)
                default: break
                }
            }
            guard let answer else { throw ToolError.unavailable("The companion didn't answer.") }
            // What it read on the way may be in its words.
            return ToolResult(text: answer, untrusted: true)
        } onCancel: {
            Task { await agent.cancel(runId: handle.runId) }
        }
    }
}
