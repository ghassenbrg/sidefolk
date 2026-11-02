import Foundation

/// Makes trivia packs with the person's AI for a game that asks (D95): one call through their Brain with the fixed
/// prompt and no tools, the answer read strictly (`TriviaPackParser`), packs kept for the day by topic, language and
/// level so asking again costs nothing, one call at a time and at most `dailyCalls` a day. It never sees the person's
/// other data: only the request's own fields go.
public actor TriviaMaker {
    public enum Failure: Error, Equatable, Sendable {
        /// The setting is off, or no AI is set up.
        case off
        /// Another pack is being made, or today's calls are used up.
        case busy
        case limit
        /// The AI answered with something that isn't a usable pack, or declined the topic.
        case unusable
        /// The call itself failed (offline, signed out, too slow): its words for the person.
        case failed(String)
    }

    /// One call: the system words and the request, answered with the model's text and the provider's name.
    public typealias Ask = @Sendable (_ system: String, _ prompt: String) async throws -> (text: String, provider: String)

    public static let dailyCalls = 20

    private let ask: Ask
    private let allowed: @Sendable () -> Bool
    private let clock: any Clock
    private var day = ""
    private var calls = 0
    private var packs: [String: TriviaPack] = [:]
    private var working = false

    /// - Parameter allowed: the person's setting with a provider set up (`GameSettings.aiTriviaOn`), read at each request.
    public init(ask: @escaping Ask, allowed: @escaping @Sendable () -> Bool, clock: any Clock = SystemClock()) {
        self.ask = ask
        self.allowed = allowed
        self.clock = clock
    }

    /// Calls made today, for the tests and the History line.
    public var callsToday: Int {
        roll()
        return calls
    }

    public func make(_ request: TriviaPackRequest) async -> Result<TriviaPack, Failure> {
        guard allowed() else { return .failure(.off) }
        roll()
        if let kept = packs[request.cacheKey] { return .success(kept) }
        guard !working else { return .failure(.busy) }
        guard calls < Self.dailyCalls else { return .failure(.limit) }
        working = true
        calls += 1
        defer { working = false }
        do {
            let (text, provider) = try await ask(TriviaPrompt.system, TriviaPrompt.user(request))
            let pack = try TriviaPackParser.parse(text, asked: request, madeBy: provider)
            packs[request.cacheKey] = pack
            return .success(pack)
        } catch is TriviaPackParser.Failure {
            return .failure(.unusable)
        } catch let error as UserFacingError {
            return .failure(.failed(error.message))
        } catch {
            return .failure(.failed(String(localized: "The AI didn't answer.", comment: "Trivia questions couldn't be made: the call failed")))
        }
    }

    /// A new day forgets yesterday's packs and calls.
    private func roll() {
        let today = Self.dayKey(clock.now)
        guard today != day else { return }
        day = today
        calls = 0
        packs = [:]
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
