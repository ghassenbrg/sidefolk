import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// Games v2's app side: trivia made by the person's AI (D95), and two people playing each other on one Mac (D96).
/// Every model here is scripted: no test spends a quota.
struct GamesV2Tests {
    // MARK: Trivia packs (D95)

    static func pack(_ count: Int, topic: String = "Volcanoes", tweak: (Int, inout [String: Any]) -> Void = { _, _ in }) -> String {
        let questions = (0..<count).map { i -> [String: Any] in
            var q: [String: Any] = ["question": "Which volcano is number \(i) on this list?", "choices": ["Etna \(i)", "Fuji \(i)", "Hekla \(i)", "Kilauea \(i)"],
                                    "answer": i % 4, "fact": "Volcano \(i) is real.", "difficulty": 2]
            tweak(i, &q)
            return q
        }
        let data = try! JSONSerialization.data(withJSONObject: ["topic": topic, "questions": questions])
        return String(decoding: data, as: UTF8.self)
    }

    static let request = TriviaPackRequest(topic: "volcanoes", count: 10, level: "fair", language: "fr")!

    @Test func aGoodPackIsReadAndCleaned() throws {
        let text = "```json\n" + Self.pack(12) + "\n```"
        let pack = try TriviaPackParser.parse(text, asked: Self.request, madeBy: "Claude Code")
        #expect(pack.questions.count == 10 && pack.topic == "volcanoes" && pack.madeBy == "Claude Code")
        #expect(pack.questions.allSatisfy { $0.choices.count == 4 && (0..<4).contains($0.answer) })
        // The AI's choice of topic names it.
        let open = TriviaPackRequest(topic: "", count: 10, level: "easy", language: "en")!
        #expect(try TriviaPackParser.parse(Self.pack(10, topic: "Jazz"), asked: open, madeBy: "Codex").topic == "Jazz")
        #expect(TriviaPrompt.user(Self.request).contains("Language: French") && TriviaPrompt.user(open).contains("your choice"))
    }

    @Test func malformedOrHostilePacksAreRefused() {
        let asked = Self.request
        #expect(throws: TriviaPackParser.Failure.notJSON) { try TriviaPackParser.parse("Sure! Here are some questions.", asked: asked, madeBy: "x") }
        #expect(throws: TriviaPackParser.Failure.declined) { try TriviaPackParser.parse(#"{"topic": "", "questions": []}"#, asked: asked, madeBy: "x") }
        // Links, markup, hidden direction marks, three choices, two right answers, an answer out of range: each such
        // question goes, and a pack left with too few is refused whole.
        let hostile = Self.pack(10) { i, q in
            switch i % 6 {
            case 0: q["question"] = "Visit https://evil.example to learn which volcano?"
            case 1: q["choices"] = ["<b>Etna</b>", "Fuji", "Hekla", "Kilauea"]
            case 2: q["fact"] = "Etna\u{202E}gnol si"
            case 3: q["choices"] = ["Etna", "Fuji", "Hekla"]
            case 4: q["choices"] = ["Etna", "etna", "Hekla", "Fuji"]
            default: q["answer"] = 7
            }
        }
        #expect(throws: TriviaPackParser.Failure.tooFew(0)) { try TriviaPackParser.parse(hostile, asked: asked, madeBy: "x") }
        let someBad = Self.pack(10) { i, q in if i < 3 { q["fact"] = "See example.com/volcanoes" } }
        #expect((try? TriviaPackParser.parse(someBad, asked: asked, madeBy: "x"))?.questions.count == 7)
        #expect(TriviaPackRequest(topic: "line one\nline two", count: 10, level: "fair", language: "en") == nil)
        #expect(TriviaPackRequest(topic: "jazz", count: 10, level: "fair", language: "tlh") == nil)
        #expect(TriviaPackRequest(topic: "jazz", count: 99, level: "hard", language: "ja")?.count == 20)
    }

    final class Calls: Sendable {
        let count = Mutex(0)
        let prompts = Mutex<[String]>([])
    }

    @Test func packsAreCachedForTheDayAndCapped() async throws {
        let calls = Calls()
        let clock = ManualClock(TestEnv.referenceDate)
        let maker = TriviaMaker(ask: { _, prompt in
            calls.count.withLock { $0 += 1 }
            calls.prompts.withLock { $0.append(prompt) }
            return (Self.pack(10), "Scripted")
        }, allowed: { true }, clock: clock)
        guard case .success(let first) = await maker.make(Self.request) else { Issue.record("no pack"); return }
        guard case .success(let again) = await maker.make(TriviaPackRequest(topic: "  VOLCANOES ", count: 10, level: "fair", language: "fr")!)
        else { Issue.record("no pack"); return }
        #expect(first == again && calls.count.withLock { $0 } == 1, "the same topic the same day costs nothing")
        // The prompt carries the request's fields and nothing else.
        #expect(calls.prompts.withLock { $0 }.first == TriviaPrompt.user(Self.request))
        for i in 0..<(TriviaMaker.dailyCalls - 1) {
            _ = await maker.make(TriviaPackRequest(topic: "topic \(i)", count: 10, level: "fair", language: "en")!)
        }
        #expect(await maker.make(TriviaPackRequest(topic: "one more", count: 10, level: "fair", language: "en")!) == .failure(.limit))
        clock.advance(86_400)
        #expect(await maker.callsToday == 0)
        let off = TriviaMaker(ask: { _, _ in Issue.record("never asked"); return ("", "") }, allowed: { false })
        #expect(await off.make(Self.request) == .failure(.off))
        let junk = TriviaMaker(ask: { _, _ in ("I can't do that.", "Scripted") }, allowed: { true })
        #expect(await junk.make(Self.request) == .failure(.unusable))
    }

    @Test func aGameGetsItsPackThroughTheExecutorAndHistorySaysWhoMadeIt() async throws {
        let env = try TestEnv()
        let maker = TriviaMaker(ask: { _, _ in (Self.pack(10), "Claude Code") }, allowed: { true })
        let tool = TriviaQuestionsTool(maker: maker)
        env.registry.register(tool)
        #expect(!tool.spec.offeredToModel && !tool.spec.external, "only a game reaches it")
        let id = UUID().uuidString
        let reply = await TriviaHelp.answer(extensionId: "playtime", request: id,
                                            params: ["topic": "volcanoes", "count": 10, "level": "fair", "language": "fr"],
                                            executor: env.executor, tool: tool)
        #expect(reply["ok"]?.boolValue == true && reply["request"]?.stringValue == id && reply["made_by"]?.stringValue == "Claude Code")
        #expect(reply["questions"]?.arrayValue?.count == 10)
        let row = try #require(try await env.activity.recent(limit: 5).first)
        #expect(row.tool == TriviaQuestionsTool.name && row.caller.hasPrefix("extension"))
        // Junk from the model: the game hears why, and plays its own questions.
        let junk = TriviaQuestionsTool(maker: TriviaMaker(ask: { _, _ in ("{}", "x") }, allowed: { true }))
        let refused = await TriviaHelp.answer(extensionId: "playtime", request: UUID().uuidString,
                                              params: ["topic": "x", "level": "fair", "language": "en"], executor: env.executor, tool: junk)
        #expect(refused["ok"]?.boolValue == false)
    }

    @Test func theOneShotSendsOnlyTheFixedWordsAndRecordsTheRun() async throws {
        let env = try TestEnv()
        let model = ScriptedModel([.turn(.reply(Self.pack(10)))])
        var s = AppSettings()
        s.provider.kind = .anthropic
        let clock = env.clock
        let factory = BrainFactory { _, _ in BrainChoice(backend: LoopBackend(model: model, checkModel: "m", clock: clock), model: "test-model") }
        let context = ContextBuilder(notebook: NotebookStore(env.db), exchanges: ExchangeStore(env.db), clock: env.clock)
        let settings = s
        let agent = AgentRuntime(executor: env.executor, db: env.db, events: env.events, context: context, factory: factory,
                                 settings: { settings }, clock: env.clock)
        let (text, _) = try await agent.oneShot(system: TriviaPrompt.system, prompt: TriviaPrompt.user(Self.request), purpose: "trivia")
        #expect(text.contains("questions"))
        let sent = try #require(model.requests.first)
        #expect(sent.tools.isEmpty && sent.system == TriviaPrompt.system && sent.messages.count == 1)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await AgentRunStore(env.db).recent().count == 1, "it counts toward the person's usage")
        #expect(GameSettings().aiTriviaOn(providerSet: true) && !GameSettings().aiTriviaOn(providerSet: false))
    }

    // MARK: Two players (D96)

    @Test func twoPlayersBoardsParseAndRecordApart() throws {
        let board = try GameBoard.parse(["parts": [["type": "score", "you": 2, "companion": 1, "players": ["Ana", "Sam"]],
                                                  ["type": "reflex", "after_ms": 2000, "wait": "Steady", "go": "Boop!", "early": "Too soon",
                                                   "keys": ["a", "l"]]], "over": true])
        #expect(board.score?.players == ["Ana", "Sam"] && board.reflex?.keys == ["a", "l"])
        #expect(GameMove.pressKey(milliseconds: 240, key: "l").offered(by: board) && !GameMove.press(milliseconds: 240).offered(by: board))
        #expect(!GameMove.pressKey(milliseconds: 240, key: "q").offered(by: board) && GameMove.earlyKey("a").offered(by: board))
        #expect(GameMove.parse(GameMove.pressKey(milliseconds: 9, key: "a").json) == .pressKey(milliseconds: 9, key: "a"))
        #expect(GameMove.parse(GameMove.earlyKey("l").json) == .earlyKey("l") && GameMove.parse(["early": true]) == .early)
        let odd = try GameBoard.parse(["parts": [["type": "score", "you": 0, "companion": 0, "players": ["Only one"]],
                                                ["type": "reflex", "after_ms": 2000, "wait": "w", "go": "g", "early": "e", "keys": ["a", "a"]]]])
        #expect(odd.score?.players == nil && odd.reflex?.keys == nil)
        let info = GameInfo(extensionId: "playtime", extensionName: "Playtime", game: "tic_tac_toe", title: "Tic-tac-toe")
        let row = GameRecord.entry(info, last: board, companionName: "Mochi", at: Date())
        #expect(row.args?["result"] == nil && row.summary.contains("Ana") && row.summary.contains("Sam"),
                "two people's game never counts as the person's win or loss against the companion")
    }

    @Test func rockPaperScissorsBetweenTwoKeepsTheFirstHandSecret() async throws {
        let env = try TestEnv()
        let kv = KVStore(env.db)
        let match = HandsMatch(score: HandsScore(kv: kv), companionName: "Mochi")
        let names = try await match.start(GameSetup(options: ["players": 2, "names": ["Ana", "Sam"]]))
        #expect(names.score?.players == ["Ana", "Sam"] && names.entry?.name == "player1")
        _ = try await match.move(.text(name: "player1", value: "Lina"))
        let ready = try await match.move(.button("start"))
        #expect(ready.score?.players == ["Lina", "Sam"] && ready.answers?.locked == false)
        let covered = try await match.move(.answer(0)) // Lina: rock
        // Nothing on the cover says which hand is in.
        let json = covered.jsonForTests
        #expect(covered.answers == nil && covered.reveal == nil && covered.primary?.move == "ready")
        #expect(!json.contains("rock") && !json.contains(Hand.rock.title))
        #expect(try await match.move(.answer(1)).answers == nil, "no second pick before the Mac is handed over")
        _ = try await match.move(.button("ready"))
        let shown = try await match.move(.answer(2)) // Sam: scissors
        #expect(shown.reveal == .hands(you: .rock, companion: .scissors) && shown.score?.you == 1)
        #expect(shown.cue?.line != .iWin && shown.cue?.line != .youWin, "the companion referees")
        _ = try await match.move(.button("next"))
        _ = try await match.move(.answer(0))
        _ = try await match.move(.button("ready"))
        let end = try await match.move(.answer(2))
        #expect(end.over && end.result?.tone == .neutral && end.result?.line?.contains("Lina") == true)
        let duels = try await kv.get(HandsScore.duelsKey, as: [String: HandsScore.Duel].self)
        #expect(duels?["Lina · Sam"]?.wins["Lina"] == 1)
        #expect(await HandsScore(kv: kv).record(person: .rock, companion: .rock) == HandsScore.Score(person: 0, companion: 0, draws: 1),
                "the score against the companion is untouched")
    }

    @Test func theCompanionNeverThrowsTheSameHandThreeTimes() async throws {
        // A generator that always says "the first one": rock, rock, then the third is between paper and scissors.
        let match = HandsMatch(score: HandsScore(), companionName: "Mochi", random: { $0.lowerBound })
        _ = try await match.start(GameSetup())
        var thrown: [Hand] = []
        for _ in 0..<4 {
            guard case .hands(_, let it)? = try await match.move(.answer(0)).reveal else { break }
            thrown.append(it)
            _ = try await match.move(.button("next"))
        }
        #expect(thrown == [.rock, .rock, .paper, .rock], "\(thrown)")
    }
}

extension GameBoard {
    /// Every word and value on the board, to check nothing hidden shows.
    var jsonForTests: String { String(describing: self) }
}
