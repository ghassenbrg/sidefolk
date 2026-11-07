import Foundation

/// The one-time code on an agent's plan card (D239, SECURITY T69). The card is on the person's desktop and holds the code; the person types it into the agent's
/// chat and the agent gives it to `plans.approve_with_code`, which settles that card as a click on Approve would. The agent never sees the code until the person
/// gives it, and it is good for one card, one use and a short time.
struct AgentCode: Sendable {
    /// Six digits, from the system's random numbers.
    let digits: String
    /// The agent the card named: the connection's own name for itself (`ExtensionHost.agentName`).
    let client: String
    /// The card's words, code included: the card is found by saying exactly this, and a card with other words (another plan) is not it.
    let body: String
    let plan: String
    /// The second plan one code approves with it, by title (D241).
    var also: String?
    let expires: Date
    var wrong = 0
    var locked = false

    static let life: TimeInterval = 120
    static let triesPerCard = 3
    static let triesPerMinute = 6

    static func fresh() -> String { String(format: "%06d", Int.random(in: 0..<1_000_000)) }

    /// `482 913`, as the card shows it.
    static func spoken(_ digits: String) -> String { digits.prefix(3) + " " + digits.suffix(3) }

    /// What the person typed, with the spaces and hyphens a code in two halves invites taken out.
    static func typed(_ text: String) -> String { String(String.UnicodeScalarView(text.unicodeScalars.filter { $0 != " " && $0 != "-" })) }

    /// Equal bytes, taking as long whichever byte differs first.
    static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var different: UInt8 = 0
        for index in x.indices { different |= x[index] ^ y[index] }
        return different == 0
    }
}

enum CodeAnswer: Equatable {
    case approved(plan: String)
    case wrong(left: Int)
    case locked
    case nothingPending
    case tooMany
}

extension ExtensionHost {
    /// The agent's name as the card says it: the connection's word for itself, hidden characters shown, no quote that could end it early.
    static func agentName(_ raw: String) -> String { ExtensionPlanWords.unquoted(raw.hiddenShown.clipped(60)) }

    /// An agent gives the code the person read on a card. Found by the agent's name and the code together: a code for another agent's card, another plan's card or one
    /// that has ended is none. Three wrong tries lock a card (it is then a click only), and an agent can try six times a minute.
    func confirmWithCode(client raw: String, code typed: String) async -> CodeAnswer {
        let client = Self.agentName(raw), now = Date()
        // Only the last minute is kept, for every name: a name that stopped trying leaves nothing behind.
        codeTries = codeTries.compactMapValues { tries in
            let recent = tries.filter { now.timeIntervalSince($0) < 60 }
            return recent.isEmpty ? nil : recent
        }
        codeLimited = codeLimited.filter { now.timeIntervalSince($0.value) < 60 }
        let recent = codeTries[client] ?? []
        guard recent.count < AgentCode.triesPerMinute else {
            // One row for the minute it happened in, not one for every try after it.
            if codeLimited[client] == nil {
                codeLimited[client] = now
                await configuration.actions?.recordPlanCodeTry(client: client, outcome: .tooMany)
            }
            return .tooMany
        }
        codeTries[client] = recent + [now]
        let entered = AgentCode.typed(String(typed.prefix(32)))
        let waiting = runtimes.compactMap { id, rt -> (id: String, code: AgentCode)? in
            guard let code = rt.agentCode, code.client == client, !code.locked, code.expires > now else { return nil }
            return (id, code)
        }
        guard !waiting.isEmpty else {
            await configuration.actions?.recordPlanCodeTry(client: client, outcome: .nothingPending)
            return .nothingPending
        }
        // Every card of this agent's is compared, whichever the code is for, so how long it takes says nothing about which.
        var match: (id: String, code: AgentCode)?
        for candidate in waiting where AgentCode.same(entered, candidate.code.digits) && match == nil { match = candidate }
        guard let match else {
            var left = AgentCode.triesPerCard
            for candidate in waiting {
                runtimes[candidate.id]?.agentCode?.wrong += 1
                let wrong = runtimes[candidate.id]?.agentCode?.wrong ?? AgentCode.triesPerCard
                if wrong >= AgentCode.triesPerCard { runtimes[candidate.id]?.agentCode?.locked = true }
                left = min(left, AgentCode.triesPerCard - wrong)
            }
            let answer: CodeAnswer = left <= 0 ? .locked : .wrong(left: left)
            await configuration.actions?.recordPlanCodeTry(client: client, outcome: answer)
            return answer
        }
        // One use: taken before anything is awaited, so a second call can't use it again.
        runtimes[match.id]?.agentCode = nil
        guard let gateway = configuration.actions, await gateway.settleCard(extensionId: match.id, text: match.code.body) else {
            return .nothingPending
        }
        await gateway.recordPlanCode(extensionId: match.id, plan: match.code.plan, also: match.code.also, client: client)
        return .approved(plan: match.code.plan)
    }
}

/// `plans.approve_with_code`: what another AI agent gives the code the person read on their desktop card. Only the person has the code, so only the person's
/// word can come this way; the agent still can't approve for itself, and the person's click on the card works as it always did.
public struct PlanCodeTool: Tool {
    public static let name = "plans.approve_with_code"

    let host: ExtensionHost

    public var spec: ToolSpec {
        ToolSpec(name: Self.name, title: String(localized: "Approve with a code", comment: "A tool for other AI agents: approves a flow with the code from its card"),
                 description: """
                     Approve the flow you asked the person to turn on, with the short code that the card on their desktop shows. Only the person can see it. If they choose to approve \
                     from this chat, they type the code to you: pass it here exactly. Never guess a code and never ask for one before you have asked for the flow: three wrong tries lock \
                     the card, and then only their click on the desktop approves it. A code works once, for one card, for about two minutes.
                     """,
                 inputSchema: Schema.object(["code": Schema.string("The six digits the person gave you.")], required: ["code"]),
                 risk: .low, capabilities: [.extensions], category: .extensions, mutates: true, external: true, offeredToModel: false)
    }

    public func summary(for input: JSONValue) -> String { String(localized: "Approve a flow with the code from its card", comment: "History: another AI agent gave the code from a flow's card") }

    /// The code is never in a row: this tool writes its own, without it.
    public func leavesNoRow(for input: JSONValue, caller: Caller) -> Bool { true }

    public func refusal(for input: JSONValue, context: ToolContext) -> String? {
        if case .external = context.caller { return nil }
        return "Only another AI agent connected to Sidefolk can use this, with a code the person gave it."
    }

    public func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard case .external(let client) = context.caller, let code = input.string("code") else { throw ToolError.invalidInput("Give the code the person read on their card.") }
        switch await host.confirmWithCode(client: client, code: code) {
        case .approved: return ToolResult(text: "Approved by the person's code. Look at the flow's own state to see that it is on.")
        case .wrong(let left): return ToolResult(text: "That code isn't right. \(left) \(left == 1 ? "try" : "tries") left on this card. Ask the person to read it again from their desktop; don't guess.", isError: true)
        case .locked: return ToolResult(text: "Too many wrong tries: this card now needs the person's click on their desktop.", isError: true)
        case .nothingPending: return ToolResult(text: "No card of yours is waiting for a code: it may have been answered, or its two minutes may have passed. Ask for the flow again if you still need it.", isError: true)
        case .tooMany: return ToolResult(text: "Too many tries in a minute. Wait before trying again.", isError: true)
        }
    }
}
