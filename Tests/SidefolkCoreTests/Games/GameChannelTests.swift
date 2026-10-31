import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// The game channel (D75): `sidefolk/game.start|move|end` with its limits, the `games` manifest key, `games.open`, the
/// sentences that open a game, and the companion's own best of three.
struct GameChannelTests {
    /// A tiny game: "slow" answers late, "huge" answers too much, anything else counts the moves.
    static let fixture = #"""
    import json, sys, time
    def send(o):
        sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
    moves = 0
    ended = []
    for line in sys.stdin:
        m = json.loads(line)
        if "id" not in m: continue
        meth, p = m["method"], m.get("params") or {}
        if meth == "initialize": r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "g", "version": "1"}}
        elif meth == "tools/list": r = {"tools": [{"name": "noop", "description": "Does nothing.", "inputSchema": {"type": "object"}}]}
        elif meth == "sidefolk/game.start":
            r = {"session": "s-1", "board": {"parts": [{"type": "prompt", "text": "Ready in " + p.get("language", "?") + " at " + str(p.get("level"))},
                                                       {"type": "button", "label": "Go", "move": "go", "style": "primary"}],
                                             "companion": {"move": "think", "line": "thinking"}}}
        elif meth == "sidefolk/game.move":
            mv = p.get("move", {})
            if mv.get("button") == "slow": time.sleep(3)
            if mv.get("button") == "huge":
                r = {"board": {"parts": [{"type": "note", "text": "x" * 70000}]}}
            else:
                moves += 1
                r = {"board": {"parts": [{"type": "prompt", "text": "moves " + str(moves) + " ended " + ",".join(ended)}]}}
        elif meth == "sidefolk/game.end":
            ended.append(p.get("reason", "")); r = {}
        else:
            send({"jsonrpc": "2.0", "id": m["id"], "error": {"code": -32601, "message": "nope"}}); continue
        send({"jsonrpc": "2.0", "id": m["id"], "result": r})
    """#

    static func manifest(games: JSONValue) -> JSONValue {
        ExtFixtures.manifest(id: "dev.test.games", tools: ["noop": ["risk": "low"]], extra: ["sidefolk": ">=0.1", "games": games])
    }

    func install(_ h: HostEnv, games: JSONValue = ["quiz": ["title": "Quiz", "symbol": "questionmark.circle", "say": ["let's play quiz", "quiz me"],
                                                            "levels": ["easy", "hard"]]]) async throws -> ExtensionInfo {
        let folder = try ExtFixtures.tempDir("game-src").appendingPathComponent("fixture")
        let source = try ExtFixtures.makeExtension(at: folder, manifest: Self.manifest(games: games), files: ["server.py": Self.fixture])
        return try await h.host.install(from: source)
    }

    @Test(.enabled(if: ExtFixtures.python != nil, ExtFixtures.noPython))
    func aGameIsPlayedOverTheChannelWithinItsLimits() async throws {
        let h = try HostEnv()
        let info = try await install(h)
        let shelf = h.host.gameShelf.all
        #expect(shelf.map(\.id) == ["\(info.id)/quiz"] && shelf.first?.levels == ["easy", "hard"] && shelf.first?.title == "Quiz")

        let (session, board) = try await h.host.startGame(extensionId: info.id, game: "quiz", setup: GameSetup(level: "hard", language: "de"))
        #expect(session == "s-1" && board.cue == GameCue(move: .think, line: .thinking))
        guard case .prompt(let p) = board.parts[0] else { Issue.record("\(board.parts)"); return }
        #expect(p.text == "Ready in de at hard", "the game hears the person's language and level")

        let moved = try await h.host.moveGame(extensionId: info.id, game: "quiz", session: session, move: .button("go"))
        guard case .prompt(let m) = moved.parts[0] else { Issue.record("\(moved.parts)"); return }
        #expect(m.text == "moves 1 ended")

        // Another game's moves, or a session that isn't open, never reach it.
        await #expect(throws: UserFacingError.self) {
            try await h.host.moveGame(extensionId: info.id, game: "quiz", session: "s-2", move: .button("go"))
        }
        // At most 20 moves a second from Sidefolk.
        let now = Date()
        var refused = 0
        for i in 0..<25 {
            do { _ = try await h.host.moveGame(extensionId: info.id, game: "quiz", session: session, move: .button("go"), now: now.addingTimeInterval(Double(i) * 0.001)) }
            catch { refused += 1 }
        }
        #expect(refused >= 5, "\(refused)")

        // Too large: the board is refused, and the game carries on.
        await #expect(throws: UserFacingError.self) {
            try await h.host.moveGame(extensionId: info.id, game: "quiz", session: session, move: .button("huge"), now: now.addingTimeInterval(5))
        }
        // Too slow: two seconds is all a game gets.
        let started = Date()
        await #expect(throws: UserFacingError.self) {
            try await h.host.moveGame(extensionId: info.id, game: "quiz", session: session, move: .button("slow"), now: now.addingTimeInterval(10))
        }
        #expect(Date().timeIntervalSince(started) < 2.8)

        // The end is said once; after it, the session is gone.
        try await Task.sleep(for: .seconds(1.5))
        await h.host.endGame(extensionId: info.id, game: "quiz", session: session, reason: .closed)
        await #expect(throws: UserFacingError.self) {
            try await h.host.moveGame(extensionId: info.id, game: "quiz", session: session, move: .button("go"), now: now.addingTimeInterval(20))
        }
        let (again, _) = try await h.host.startGame(extensionId: info.id, game: "quiz", setup: GameSetup())
        let after = try await h.host.moveGame(extensionId: info.id, game: "quiz", session: again, move: .button("go"), now: now.addingTimeInterval(30))
        guard case .prompt(let e) = after.parts[0] else { Issue.record("\(after.parts)"); return }
        #expect(e.text.hasSuffix("ended closed"), "\(e.text)")

        try await h.host.setEnabled(false, id: info.id)
        #expect(h.host.gameShelf.all.isEmpty, "a switched-off extension's games leave the shelf")
        await h.host.shutdown()
    }

    @Test func gamesInTheManifestFollowTheRules() async throws {
        let h = try HostEnv()
        let folder = try ExtFixtures.tempDir("game-bad").appendingPathComponent("fixture")
        let bad: JSONValue = [
            "Quiz Game": ["title": "Quiz"],
            "quiz": ["title": "", "symbol": "Not A Symbol", "levels": ["easy", "easy"], "say": ["yes", "play {what:text}", "quiz me", "Quiz me!"]],
        ]
        _ = try ExtFixtures.makeExtension(at: folder, manifest: Self.manifest(games: bad), files: ["server.py": Self.fixture])
        let preview = await h.host.preview(folder: folder)
        let fields = Set(preview.report.errors.map(\.field))
        for field in ["games.Quiz Game", "games.quiz.title", "games.quiz.symbol", "games.quiz.levels", "games.quiz.say[0]", "games.quiz.say[1]",
                      "games.quiz.say[3]"] {
            #expect(fields.contains(field), "\(field) in \(fields)")
        }
        #expect(!fields.contains("games.quiz.say[2]"))
        let unknown = try ExtFixtures.makeExtension(at: try ExtFixtures.tempDir("game-key").appendingPathComponent("fixture"),
                                                    manifest: Self.manifest(games: ["quiz": ["title": "Quiz", "widget": true]]),
                                                    files: ["server.py": Self.fixture])
        #expect(await h.host.preview(folder: unknown).report.errors.contains { "\($0.field) \($0.message)".contains("widget") }, "unknown keys are refused, as everywhere")
    }

    // MARK: Opening a game

    @Test func sentencesAndTheToolOpenAGame() async throws {
        let quiz = GameInfo(extensionId: "dev.test.games", extensionName: "Games", game: "quiz", title: "Quiz", say: ["let's play quiz", "quiz me"])
        let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test", games: [quiz])
        let parsed = parser.parse("Let's play quiz!", now: TimeTest.wednesday10)
        #expect(parsed?.intent == .game(extensionId: "dev.test.games", game: "quiz") && parsed?.hint == "Play Quiz · no AI")
        #expect(parser.parse("quiz me about space", now: TimeTest.wednesday10)?.intent != .game(extensionId: "dev.test.games", game: "quiz"))
        let twice = IntentParser(when: TimeTest.parser(), home: "/Users/test",
                                 games: [quiz, GameInfo(extensionId: "dev.other", extensionName: "Other", game: "q", title: "Q", say: ["quiz me"])])
        #expect(twice.parse("quiz me", now: TimeTest.wednesday10) == nil, "two extensions claim it: the AI decides")

        let env = try TestEnv()
        let shelf = GameShelf()
        shelf.set([quiz])
        env.registry.register(GamesOpenTool(events: env.events, shelf: shelf))
        #expect(env.registry.tool(named: "games.open")?.spec.description.contains("dev.test.games/quiz (Quiz)") == true)
        #expect(env.registry.tool(named: "games.open")?.spec.description.contains("sidefolk/rock_paper_scissors") == true)

        func open(_ input: JSONValue, caller: Caller) async -> (ToolOutcome, GameRequest?) {
            let stream = env.events.stream()
            let out = await env.executor.execute(name: "games.open", input: input, caller: caller)
            let heard = await withTaskGroup(of: GameRequest?.self) { group in
                group.addTask {
                    for await event in stream { if case .game(let r) = event { return r } }
                    return nil
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(out.isOK ? 5 : 0.2))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            return (out, heard)
        }
        let (mine, asked) = await open(["extension": "dev.test.games", "game": "quiz"], caller: .user)
        #expect(mine.isOK && asked?.info.id == "dev.test.games/quiz" && asked?.focus == true && mine.activity.decision == .auto)
        let (ai, offered) = await open(["extension": "sidefolk", "game": "rock_paper_scissors"], caller: .agent(runId: "r1"))
        #expect(ai.isOK && offered?.info == .handsMatch && offered?.focus == false, "opened by the AI, the panel waits for a click")
        let (none, nothing) = await open(["extension": "dev.test.games", "game": "chess"], caller: .user)
        #expect(!none.isOK && nothing == nil)

        // "rock paper scissors" alone is the match now; a hand is still a quick throw.
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-games-\(UUID().uuidString)", isDirectory: true)
        let runner = LocalIntentRunner(runtime: await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(),
                                                                      platform: NullPlatform(), clock: ManualClock(TestEnv.referenceDate)))
        let stream = runner.runtime.events.stream()
        _ = await runner.run(.chance(ChanceIntent(.rockPaperScissors)))
        let match = await withTaskGroup(of: GameRequest?.self) { group in
            group.addTask {
                for await event in stream { if case .game(let r) = event { return r } }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        #expect(match?.info == .handsMatch && match?.focus == true)
    }

    // MARK: The companion's own match

    final class Script: Sendable {
        let values: Mutex<[Int]>
        init(_ values: [Int]) { self.values = Mutex(values) }
        func next(_ range: ClosedRange<Int>) -> Int { values.withLock { $0.isEmpty ? range.lowerBound : $0.removeFirst() } }
    }

    @Test func theBestOfThreeIsDrawnInCoreAndKeepsTheScore() async throws {
        let env = try TestEnv()
        let kv = KVStore(env.db)
        // Drawn in order: its hand for round 1 (scissors); for round 2 its hand (paper), no bluff (1); for round 3 its
        // hand (paper), a bluff (0) naming rock (0).
        let match = HandsMatch(score: HandsScore(kv: kv), companionName: "Mochi", random: Script([2, 1, 1, 1, 0, 0]).next)
        let start = try await match.start(GameSetup())
        #expect(start.answers?.tiles.map(\.art) == [.rock, .paper, .scissors] && start.answers?.locked == false)
        #expect(start.score?.rounds == 2 && start.score?.companionPicked == true && start.cue?.line == .hello && start.primary == nil)

        let one = try await match.move(.answer(0)) // rock against scissors
        #expect(one.parts.contains(.reveal(.hands(you: .rock, companion: .scissors))))
        #expect(one.score?.you == 1 && one.answers?.tiles[0].state == .right && one.answers?.tiles[2].companion == true && one.answers?.locked == true)
        #expect(one.answers?.tiles[2].state == GameBoard.Answers.State.none, "the companion's tile shows its face, not a loss colour")
        #expect(try await match.move(.answer(1)).score?.you == 1, "no second throw before the next round")
        #expect(one.primary?.move == "next" && !one.over)

        let two = try await match.move(.button("next"))
        #expect(two.said == nil && two.answers?.locked == false && two.score?.companionPicked == true)
        let lost = try await match.move(.answer(0)) // rock against paper
        #expect(lost.score?.companion == 1 && lost.cue?.line == .tease && lost.answers?.tiles[0].state == .wrong)
        let three = try await match.move(.button("next"))
        #expect(three.said == "I'm going rock…" && three.cue?.move == .tease)
        let end = try await match.move(.answer(2)) // scissors against paper
        #expect(end.over && end.score?.you == 2 && end.result?.figure == "2 – 1" && end.result?.line == "You win the match!")
        #expect(end.result?.tone == .good && end.cue?.line == .youWin && end.primary?.move == "again")
        #expect(await HandsScore(kv: kv).record(person: .rock, companion: .rock) == HandsScore.Score(person: 2, companion: 1, draws: 1),
                "every throw adds to the score kept since D44")
        let rematch = try await match.move(.button("again"))
        #expect(rematch.score?.you == 0 && !rematch.over)

        let record = GameRecord.entry(.handsMatch, last: end, companionName: "Mochi", at: Date())
        #expect(record.summary == "Played Rock, Paper, Scissors with Mochi · You 2 · Mochi 1" && record.tool == "games.play")
    }

    /// The founder found the companion "always" answering rock with rock: its throw must be sealed before the person's
    /// pick and never read it (D75).
    @Test func theCompanionsThrowIsSealedBeforeYoursAndNeverReadsIt() async throws {
        // The same draws and three different picks: its hand is the same each time, fixed before the move came.
        for pick in 0..<3 {
            let match = HandsMatch(score: HandsScore(), companionName: "Mochi", random: Script([1]).next)
            _ = try await match.start(GameSetup())
            #expect(match.sealedHand == .paper, "sealed when the round begins")
            let board = try await match.move(.answer(pick))
            #expect(board.reveal == .hands(you: Hand.allCases[pick], companion: .paper))
            #expect(match.sealedHand == nil, "spent once both show")
        }
        // The system's generator over many rounds, whatever the person plays first: each hand about a third of the time.
        var counts: [Hand: Int] = [:]
        var mirrored = 0
        for _ in 0..<3000 {
            let match = HandsMatch(score: HandsScore(), companionName: "Mochi")
            _ = try await match.start(GameSetup())
            guard case .hands(let you, let it)? = try await match.move(.answer(0)).reveal else { Issue.record("no reveal"); return }
            counts[it, default: 0] += 1
            if it == you { mirrored += 1 }
        }
        for hand in Hand.allCases { #expect((850...1150).contains(counts[hand] ?? 0), "\(hand): \(counts[hand] ?? 0) of 3000") }
        #expect((850...1150).contains(mirrored), "rock answered with rock \(mirrored) of 3000 times")
    }

    /// Each side of the reveal is only ever its own hand: sealed while the fists pump, then its own throw to the end.
    @Test func eachSideOfTheRevealShowsItsOwnHand() {
        for you in Hand.allCases {
            for it in Hand.allCases {
                for step in 0...100 {
                    let p = Double(step) / 100
                    let side = HandsReveal(you: you, companion: it, at: p)
                    if p < HandsReveal.opens {
                        #expect(side.you == nil && side.companion == nil && side.verdict == nil, "sealed while pumping, at \(p)")
                    } else {
                        #expect(side.you == you && side.companion == it, "\(you) against \(it) at \(p)")
                        #expect(side.verdict == (p < HandsReveal.acts ? nil : GameVerdict(you: you, companion: it)), "the verdict comes last")
                    }
                }
            }
        }
    }

    /// Nothing gives the outcome away before the reveal ends: the build-up has no judged tile, no revealed pick, no end
    /// card, no cue and no words; the verdict comes after (D75).
    @Test func theVerdictWaitsForTheReveal() async throws {
        let match = HandsMatch(score: HandsScore(), companionName: "Mochi", random: Script([1]).next)
        let pick = try await match.start(GameSetup())
        let thrown = try await match.move(.answer(0))
        #expect(GameSuspense.showsVerdict(thrown), "the game's own board carries the verdict")
        let (build, seconds) = try #require(GameSuspense.buildUp(from: pick, to: thrown, picked: 0))
        #expect(!GameSuspense.showsVerdict(build) && seconds == GameSuspense.revealSeconds)
        #expect(build.reveal == thrown.reveal && build.score == pick.score, "the reveal plays; the score stays as it was")
        #expect(build.answers?.tiles.map(\.state) == [.picked, .none, .none] && build.primary == nil)
        #expect(!build.parts.contains { if case .prompt(let p) = $0 { p.text == thrown.parts.compactMap { if case .prompt(let q) = $0 { q.text } else { nil } }.first } else { false } },
                "the verdict's sentence waits")

        // Trivia: a beat with the pick pressed and the companion's card still sealed.
        let question = try GameBoardTests.board("""
            {"parts": [{"type": "score", "you": 1, "companion": 1, "companion_picked": true}, {"type": "prompt", "text": "Q?"},
                       {"type": "answers", "items": [{"label": "A"}, {"label": "B"}]}, {"type": "button", "label": "Hint", "move": "hint"}]}
            """)
        let answered = try GameBoardTests.board("""
            {"parts": [{"type": "score", "you": 2, "companion": 1}, {"type": "prompt", "text": "Q?"},
                       {"type": "answers", "locked": true, "items": [{"label": "A", "state": "right"}, {"label": "B", "companion": true, "state": "faded"}]},
                       {"type": "note", "text": "A fact."}, {"type": "button", "label": "Next", "move": "next", "style": "primary"}],
             "companion": {"move": "sulk"}}
            """)
        let (beat, wait) = try #require(GameSuspense.buildUp(from: question, to: answered, picked: 0))
        #expect(!GameSuspense.showsVerdict(beat) && wait == GameSuspense.beatSeconds)
        #expect(beat.score?.you == 1 && beat.score?.companionPicked == true && beat.answers?.tiles[0].state == .picked && beat.buttons.isEmpty)
        #expect(GameSuspense.buildUp(from: answered, to: question, picked: nil) == nil, "a new question gives nothing away")
    }

    /// One meaning, one colour role, with a symbol: a win is success, a loss the calm loss tone, a draw neutral (D75).
    @Test func verdictsMapToOneColourEach() {
        #expect(GameVerdict(you: .paper, companion: .rock).role == .success)
        #expect(GameVerdict(you: .rock, companion: .paper).role == .lost)
        #expect(GameVerdict(you: .rock, companion: .rock).role == .neutral)
        #expect(GameVerdict(Toss.coins([true], call: true))?.role == .success)
        #expect(GameVerdict(Toss.coins([false], call: true))?.role == .lost)
        #expect(GameVerdict(Toss.coins([true])) == nil && GameVerdict(Toss.dice(sides: 20, rolls: [20], modifier: 0)) == nil,
                "nothing at stake: drawn neutral")
        #expect(GameVerdict(tile: .right, locked: true)?.role == .success && GameVerdict(tile: .wrong, locked: true)?.role == .lost)
        #expect(GameVerdict(tile: .picked, locked: true)?.role == .neutral && GameVerdict(tile: .picked, locked: false) == nil)
        #expect(GameVerdict(tone: .good) == .win && GameVerdict(tone: .bad) == .loss && GameVerdict(tone: .neutral) == .draw)
        #expect(Set(GameVerdict.allCases.map(\.symbol)).count == 3, "a symbol of its own each, never colour alone")
    }

    @Test func aCalledCoinSaysWhetherTheCallWasRight() async throws {
        let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")
        func chance(_ text: String) -> ChanceIntent? {
            if case .chance(let c)? = parser.parse(text, now: TimeTest.wednesday10)?.intent { return c }
            return nil
        }
        #expect(chance("flip a coin, I call tails") == ChanceIntent(.coin, call: false))
        #expect(chance("heads or tails? heads") == ChanceIntent(.coin, call: true))
        #expect(chance("toss a coin: I say heads") == ChanceIntent(.coin, call: true))
        #expect(chance("flip 3 coins, heads") == ChanceIntent(.coin, count: 3), "a call is for one coin")
        #expect(chance("flip a coin, heads up") == nil)

        #expect(Toss.coins([true], call: true).called == true && Toss.coins([false], call: true).called == false)
        #expect(Toss.coins([true]).called == nil && Toss.coins([true, false], call: true).called == nil)
        #expect(Toss.coins([false], call: true).forModel == "tails; the user called heads and was wrong")
    }
}
