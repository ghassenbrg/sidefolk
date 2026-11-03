import Foundation
import Synchronization

/// Where the companion's brain is, once the app has made it: the runtime is assembled first.
public final class CompanionAgentSlot: Sendable {
    private let agent = Mutex<AgentRuntime?>(nil)

    public init() {}
    public func use(_ runtime: AgentRuntime) { agent.withLock { $0 = runtime } }
    var current: AgentRuntime? { agent.withLock { $0 } }
}

/// `companion.job`: hands the companion a whole job, written out, to do with its tools (D121). It runs as any request to it does, in a conversation of its own, under the person's
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

    func summary(for input: JSONValue) -> String {
        String(localized: "Let your companion: \(ToolFormat.oneLine(input.string("job") ?? "", 200))", comment: "A tool's row: “Let your companion: tidy my Downloads”")
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope() }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let job = input.string("job")?.trimmingCharacters(in: .whitespacesAndNewlines), !job.isEmpty else { throw ToolError.invalidInput("Say what the job is.") }
        guard let agent = agent.current else { throw ToolError.unavailable("The companion can't take a job right now.") }
        var answer: String?
        // Its own conversation: whatever the person was saying in Ask stays as it was.
        for await event in await agent.handle(AgentRequest(text: job, threadId: "job-\(Identifier.make())")) {
            switch event {
            case .reply(let reply): answer = reply.text
            case .failed(let problem): throw ToolError.unavailable(problem.message)
            default: break
            }
        }
        guard let answer else { throw ToolError.unavailable("The companion didn't answer.") }
        // What it read on the way may be in its words.
        return ToolResult(text: answer, untrusted: true)
    }
}
