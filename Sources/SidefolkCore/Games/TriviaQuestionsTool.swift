import Foundation
import Synchronization

/// `games.trivia_questions` (D95): a game's request for trivia questions made by the person's AI, run through the
/// executor like every action so Guard weighs it and History shows it ("Trivia questions made by Claude Code"). It is
/// never offered to a model or to other agents: only a game that asks reaches it, as `Caller.extension`. The pack
/// itself goes back to the game as data (`ExtensionHost`), not as text a model reads.
public struct TriviaQuestionsTool: Tool {
    public static let name = "games.trivia_questions"

    let maker: TriviaMaker
    /// What each request came to, by its id, until the host takes it.
    private let results = Results()

    final class Results: Sendable {
        let kept = Mutex<[String: Result<TriviaPack, TriviaMaker.Failure>]>([:])
    }

    public init(maker: TriviaMaker) {
        self.maker = maker
    }

    public var spec: ToolSpec {
        ToolSpec(name: Self.name, title: String(localized: "Make trivia questions", comment: "A tool: trivia questions made by the person's AI for a game"),
                 description: "Makes trivia questions about a topic with the user's AI for a game in the Play panel.",
                 inputSchema: Schema.object([
                     "request": Schema.string("The game's id for this request."),
                     "topic": Schema.string("The subject, or empty for the AI's choice."),
                     "count": Schema.integer("How many questions.", minimum: 10, maximum: 20),
                     "level": Schema.string("easy, fair or hard."),
                     "language": Schema.string("The person's language."),
                 ], required: ["request", "level", "language"]),
                 risk: .low, capabilities: [.system], category: .system, mutates: false, offeredToModel: false)
    }

    public func summary(for input: JSONValue) -> String {
        let topic = input.string("topic") ?? ""
        return topic.isEmpty ? String(localized: "Make trivia questions on a topic of the AI's choice", comment: "History: a game asked the AI for trivia questions")
            : String(localized: "Make trivia questions about \(ExtensionText.line(topic, characters: 60))",
                     comment: "History: a game asked the AI for trivia questions about the topic the person named")
    }

    public func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let id = input.string("request"),
              let request = TriviaPackRequest(topic: input.string("topic") ?? "", count: input["count"]?.intValue ?? 10,
                                              level: input.string("level") ?? "", language: input.string("language") ?? "") else {
            throw ToolError.invalidInput("That isn't a trivia request Sidefolk can make.")
        }
        let result = await maker.make(request)
        results.kept.withLock { $0[id] = result }
        switch result {
        case .success(let pack):
            let made = String(localized: "Trivia questions made by \(pack.madeBy)",
                              comment: "History: trivia questions the person's AI made, then the AI's name; they are not checked")
            return ToolResult(text: "\(pack.questions.count) questions about \(pack.topic).",
                              card: ResultCard(kind: .info, title: made, subtitle: pack.topic))
        case .failure(let failure):
            throw UserFacingError(verbatim: Self.words(failure))
        }
    }

    /// What a request came to, once: the host passes it to the game that asked.
    public func take(_ id: String) -> Result<TriviaPack, TriviaMaker.Failure>? {
        results.kept.withLock { $0.removeValue(forKey: id) }
    }

    static func words(_ failure: TriviaMaker.Failure) -> String {
        switch failure {
        case .off: String(localized: "Making trivia questions with AI is off.", comment: "Trivia: the person's setting is off, or no AI is set up")
        case .busy: String(localized: "Trivia questions are already being made.", comment: "Trivia: one request at a time")
        case .limit: String(localized: "That's enough new trivia questions for today.", comment: "Trivia: the day's AI requests are used up")
        case .unusable: String(localized: "The AI's questions weren't usable.", comment: "Trivia: the AI's answer was refused by Sidefolk's checks")
        case .failed(let why): why
        }
    }
}

/// The host's side of `sidefolk/trivia.request` (D95): the game's fields through `games.trivia_questions` as the
/// extension, then the pack (or why there is none) as the `sidefolk/trivia.pack` notice's data.
public enum TriviaHelp {
    public static func answer(extensionId: String, request: String, params: JSONValue, executor: ToolExecutor,
                              tool: TriviaQuestionsTool) async -> JSONValue {
        let input: JSONValue = ["request": .string(request), "topic": .string(params["topic"]?.stringValue ?? ""),
                                "count": .number(Double(params["count"]?.intValue ?? 10)), "level": .string(params["level"]?.stringValue ?? ""),
                                "language": .string(params["language"]?.stringValue ?? "")]
        let outcome = await executor.execute(name: TriviaQuestionsTool.name, input: input, caller: .extension(id: extensionId), timeout: 120)
        switch tool.take(request) {
        case .success(let pack)?:
            let questions: [JSONValue] = pack.questions.map { q in
                var item: [String: JSONValue] = ["question": .string(q.text), "choices": .array(q.choices.map(JSONValue.string)),
                                                 "answer": .number(Double(q.answer)), "difficulty": .number(Double(q.difficulty))]
                if let fact = q.fact { item["fact"] = .string(fact) }
                return .object(item)
            }
            return ["request": .string(request), "ok": true, "topic": .string(pack.topic), "made_by": .string(pack.madeBy),
                    "questions": .array(questions)]
        case .failure(let failure)?:
            return ["request": .string(request), "ok": false, "reason": .string(reason(failure))]
        case nil:
            // Guard refused it, or it never ran: the game falls back to its own questions.
            return ["request": .string(request), "ok": false, "reason": .string(outcome.isOK ? "failed" : "denied")]
        }
    }

    /// A short code the game words in the person's language.
    static func reason(_ failure: TriviaMaker.Failure) -> String {
        switch failure {
        case .off: "off"
        case .busy: "busy"
        case .limit: "limit"
        case .unusable: "unusable"
        case .failed: "failed"
        }
    }
}
