import Foundation
@testable import SidefolkCore
import Testing

/// The app's own game sentences (D93): steering sentences and a game's name with its slots, in several of the ten
/// languages, and what stays with the AI or another extension.
struct GameCommandsTests {
    static let levels = ["easy", "fair", "hard"]
    static let trivia = GameInfo(extensionId: "dev.sidefolk.playtime", extensionName: "Playtime", game: "trivia", title: "Trivia", levels: levels,
                                 say: ["let's play trivia", "play trivia", "trivia", "quiz me", "jouons au quiz", "juguemos a trivia",
                                       "lass uns ein quiz spielen", "クイズしよう", "퀴즈 하자", "来玩问答", "لنلعب مسابقة"], look: .quiz)
    static let ttt = GameInfo(extensionId: "dev.sidefolk.playtime", extensionName: "Playtime", game: "tictactoe", title: "Tic-tac-toe", levels: levels,
                              say: ["let's play tic-tac-toe", "tic tac toe", "jouons au morpion", "lass uns tic-tac-toe spielen", "まるばつゲームしよう",
                                    "틱택토 하자", "来玩井字棋", "لنلعب إكس أو"], look: .grid)
    static let numbers = GameInfo(extensionId: "dev.sidefolk.playtime", extensionName: "Playtime", game: "higher_lower", title: "Higher or Lower",
                                  say: ["let's play higher or lower", "higher or lower", "guess my number"], look: .numbers)
    static let sudoku = GameInfo(extensionId: "dev.sidefolk.playtime", extensionName: "Playtime", game: "sudoku", title: "Sudoku", levels: levels,
                                 say: ["sudoku", "let's play sudoku", "数独をしよう", "来玩数独"], look: .sudoku)
    static let daily = GameInfo(extensionId: "dev.sidefolk.playtime", extensionName: "Playtime", game: "daily_word", title: "Daily Word",
                                say: ["daily word", "word of the day", "wort des tages", "今日のことば"], look: .words)
    static let copy = GameInfo(extensionId: "dev.sidefolk.playtime", extensionName: "Playtime", game: "copy_me", title: "Copy Me", levels: levels,
                               say: ["let's play copy me", "copy me"], look: .dance)
    static let all = [trivia, ttt, numbers, sudoku, daily, copy]

    let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test", companionNames: ["sidefolk", "pip", "mochi"], games: GameCommandsTests.all)

    func command(_ text: String) -> GameCommand? {
        guard case .gameCommand(let c)? = parser.parse(text, now: TimeTest.wednesday10)?.intent else { return nil }
        return c
    }

    func open(_ game: GameInfo, _ level: String? = nil, _ slots: GameSlots = GameSlots()) -> GameCommand {
        .open(extensionId: game.extensionId, game: game.game, level: level, slots: slots)
    }

    @Test func steeringSentencesInTenLanguages() {
        let cases: [(String, GameCommand)] = [
            ("rematch", .again(nil)), ("Play again!", .again(nil)), ("revanche", .again(nil)), ("Otra partida", .again(nil)),
            ("noch eine Runde", .again(nil)), ("giochiamo ancora", .again(nil)), ("jogar de novo", .again(nil)), ("もう一回やろう", .again(nil)),
            ("한판 더", .again(nil)), ("再来一局", .again(nil)), ("مباراة أخرى", .again(nil)),
            ("make it harder", .again(.harder)), ("too easy!", .again(.harder)), ("plus difficile", .again(.harder)),
            ("mas dificil", .again(.harder)), ("Mach es schwerer", .again(.harder)), ("更难", .again(.harder)), ("أصعب", .again(.harder)),
            ("make it easier", .again(.easier)), ("c'est trop dur", .again(.easier)), ("zu schwer", .again(.easier)),
            ("もっと簡単に", .again(.easier)), ("더 쉽게 해줘", .again(.easier)),
            ("resume the game", .resume), ("weiterspielen", .resume), ("继续游戏", .resume),
            ("a random game", .random), ("pick a game for me", .random), ("choisis un jeu", .random), ("랜덤 게임", .random),
            ("show my stats", .center), ("my scores", .center), ("Mochi, show my stats", .center), ("mes scores", .center),
            ("meine Punkte", .center), ("ゲームの成績", .center), ("مركز الألعاب", .center),
            ("pause the game", .pause), ("mets le jeu en pause", .pause), ("Spiel pausieren", .pause), ("暂停游戏", .pause),
            ("turn game sounds off", .sounds(false)), ("mute the game", .sounds(false)), ("Spielgeräusche aus", .sounds(false)),
            ("게임 소리 꺼줘", .sounds(false)), ("turn game sounds on", .sounds(true)), ("active les sons du jeu", .sounds(true)),
        ]
        for (text, expected) in cases { #expect(command(text) == expected, "\(text)") }
        #expect(parser.parse("back to the games", now: TimeTest.wednesday10)?.intent == .gamesMenu)
        #expect(parser.parse("zurück zu den Spielen", now: TimeTest.wednesday10)?.intent == .gamesMenu)
    }

    @Test func aGameWithItsSlots() {
        let space = GameSlots(topic: "space", count: 10)
        let cases: [(String, GameCommand)] = [
            ("play trivia on easy", open(Self.trivia, "easy")),
            ("trivia about space, hard, 10 questions", open(Self.trivia, "hard", space)),
            ("let's play trivia about space with 10 questions on hard", open(Self.trivia, "hard", space)),
            ("play tic-tac-toe on hard", open(Self.ttt, "hard")),
            ("tic tac toe, easy", open(Self.ttt, "easy")),
            ("let's play a game of tic tac toe against you, Mochi", open(Self.ttt)),
            ("jouons au morpion difficile", open(Self.ttt, "hard")),
            ("lass uns tic-tac-toe auf schwer spielen", open(Self.ttt, "hard")),
            ("まるばつゲームを難しいでしよう", open(Self.ttt, "hard")),
            ("어려운 틱택토 하자", open(Self.ttt, "hard")),
            ("来玩简单的井字棋", open(Self.ttt, "easy")),
            ("لنلعب إكس أو على مستوى صعب", open(Self.ttt, "hard")),
            ("jouons au quiz sur l'espace", open(Self.trivia, nil, GameSlots(topic: "l'espace"))),
            ("lass uns ein quiz über Tiere spielen", open(Self.trivia, nil, GameSlots(topic: "tiere"))),
            ("quiz me about the roman empire, 5 questions", open(Self.trivia, nil, GameSlots(topic: "roman empire", count: 5))),
            ("guess a number between 1 and 1000", open(Self.numbers, nil, GameSlots(min: 1, max: 1000, mode: .mine))),
            ("you guess my number up to 500", open(Self.numbers, nil, GameSlots(min: 1, max: 500, mode: .yours))),
            ("devine mon nombre jusqu'à 200", open(Self.numbers, nil, GameSlots(min: 1, max: 200, mode: .yours))),
            ("rate eine Zahl zwischen 1 und 5000", open(Self.numbers, nil, GameSlots(min: 1, max: 5000, mode: .mine))),
            ("猜数字 1到1000", open(Self.numbers, nil, GameSlots(min: 1, max: 1000, mode: .mine))),
            ("خمن رقمي حتى ٥٠٠", open(Self.numbers, nil, GameSlots(min: 1, max: 500, mode: .yours))),
            ("play higher or lower up to 1000", open(Self.numbers, nil, GameSlots(min: 1, max: 1000))),
            ("today's word", open(Self.daily)),
            ("daily sudoku", open(Self.sudoku)),
            ("sudoku hard", open(Self.sudoku, "hard")),
            ("数独を難しいでしよう", open(Self.sudoku, "hard")),
        ]
        for (text, expected) in cases { #expect(command(text) == expected, "\(text)") }
        #expect(parser.parse("trivia about space, hard, 10 questions", now: TimeTest.wednesday10)?.hint
            == "Play Trivia · Hard · about space · 10 questions · no AI")
    }

    @Test func whatStaysWithTheAIOrAnotherExtension() {
        for text in ["copy", "memory", "play some music", "play this on the TV", "start the timer", "hard", "again", "nochmal",
                     "sudoku 10 questions", "tic-tac-toe about space", "guess a number between 1000 and 1", "trivia about " + String(repeating: "a", count: 60),
                     "tell me about trivia", "play tic-tac-toe on hard and easy", "how are my stats at work"] {
            if case .gameCommand? = parser.parse(text, now: TimeTest.wednesday10)?.intent { Issue.record("\(text) was claimed") }
        }
        // A game's own sentence still opens it as before (D75).
        #expect(parser.parse("let's play tic-tac-toe", now: TimeTest.wednesday10)?.intent == .game(extensionId: "dev.sidefolk.playtime", game: "tictactoe"))
        // A game without levels takes no level word.
        #expect(command("higher or lower on hard") == nil)
    }

    @Test func levelsStepAndMatch() {
        #expect(GameLevels.step(.harder, from: nil, in: Self.levels) == "hard")
        #expect(GameLevels.step(.easier, from: "fair", in: Self.levels) == "easy")
        #expect(GameLevels.step(.harder, from: "hard", in: Self.levels) == nil)
        #expect(GameLevels.step(.harder, from: nil, in: []) == nil)
        #expect(GameLevels.match("hard", in: ["beginner", "pro"]) == "pro")
        #expect(GameLevels.match("fair", in: ["a", "b", "c", "d"]) == "c")
        #expect(GameLevels.match("hard", in: []) == nil)
    }

    @Test func slotsAreChecked() {
        #expect(GameSlots(["topic": "space", "count": 10, "min": 1, "max": 1000, "mode": "yours"])
            == GameSlots(topic: "space", count: 10, min: 1, max: 1000, mode: .yours))
        #expect(GameSlots(["count": 500, "min": 10, "max": 5, "mode": "both"]) == GameSlots())
        #expect(GameSlots(["max": 50]) == GameSlots(min: 1, max: 50))
        #expect(GameSlots(["topic": .string(String(repeating: "x", count: 41)), "max": 2_000_000]) == GameSlots())
    }

    // MARK: The tools

    @Test func gamesOpenDoesWhatTheCommandsDo() async throws {
        let env = try TestEnv()
        let settings = await SettingsStore(db: env.db, events: env.events)
        let shelf = GameShelf()
        shelf.set(Self.all)
        env.registry.register([GamesOpenTool(events: env.events, shelf: shelf, settings: settings, activity: env.activity),
                               GamesSettingsTool(settings: settings, shelf: shelf)])

        func run(_ input: JSONValue, caller: Caller = .user) async -> (ToolOutcome, AppEvent?) {
            let stream = env.events.stream()
            let out = await env.executor.execute(name: "games.open", input: input, caller: caller)
            let heard = await withTaskGroup(of: AppEvent?.self) { group in
                group.addTask {
                    for await event in stream {
                        switch event { case .game, .gamesMenu, .gameCenter: return event; default: continue }
                    }
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
        func request(_ event: AppEvent?) -> GameRequest? { if case .game(let r)? = event { r } else { nil } }
        func card(_ out: ToolOutcome) -> String? { if case .ok(let r) = out.status { r.card?.title } else { nil } }

        // Nothing played yet: "rematch" shows the menu rather than failing.
        let (first, menu) = await run(["game": "again"])
        guard case .gamesMenu? = menu else { Issue.record("expected the menu, got \(String(describing: menu))"); return }
        #expect(first.isOK)

        // A level the person asks for becomes theirs; the slots go with the request.
        let (hard, asked) = await run(["extension": "dev.sidefolk.playtime", "game": "trivia", "level": "hard", "topic": "space", "count": 10])
        #expect(hard.isOK && request(asked)?.level == "hard" && request(asked)?.slots == GameSlots(topic: "space", count: 10))
        #expect(settings.current.games.levels["dev.sidefolk.playtime/trivia"] == "hard")
        #expect(card(hard) == "Play Trivia · Hard")
        let (_, later) = await run(["extension": "dev.sidefolk.playtime", "game": "trivia"])
        #expect(request(later)?.level == "hard" && request(later)?.fresh == false, "opened again from the menu, at the level chosen")

        // Easier from hard is fair, a new game; at the easiest it says so.
        let (_, easier) = await run(["game": "again", "level": "easier"])
        #expect(request(easier)?.level == "fair" && request(easier)?.fresh == true && request(easier)?.info.game == "trivia")
        _ = await run(["game": "last", "level": "easier"])
        let (floor, none) = await run(["game": "last", "level": "easier"])
        #expect(!floor.isOK && none == nil && floor.problem?.message.contains("easiest") == true, "\(String(describing: floor.problem?.message))")
        let (noLevels, _) = await run(["extension": "dev.sidefolk.playtime", "game": "higher_lower", "level": "harder"])
        #expect(!noLevels.isOK)

        // The AI's level isn't remembered as the person's.
        _ = await run(["extension": "dev.sidefolk.playtime", "game": "sudoku", "level": "hard"], caller: .agent(runId: "r1"))
        #expect(settings.current.games.levels["dev.sidefolk.playtime/sudoku"] == nil)

        // Resume is the last game, not a new one; random is another game; center is the Game Center.
        let (_, resumed) = await run(["game": "last"])
        #expect(request(resumed)?.info.game == "sudoku" && request(resumed)?.fresh == false)
        let (_, random) = await run(["game": "random"])
        #expect(request(random) != nil && request(random)?.info.game != "sudoku")
        let (_, center) = await run(["game": "center"])
        guard case .gameCenter? = center else { Issue.record("expected the Game Center"); return }

        // games.settings: sounds for every game (each game's speaker too), the tone, Sneaky, a level back to the game's.
        await settings.update { $0.games.speakers["dev.sidefolk.playtime/trivia"] = true }
        let quiet = await env.executor.execute(name: "games.settings", input: ["sounds": false, "tone": "gentle", "sneaky": true], caller: .user)
        #expect(quiet.isOK && card(quiet) == "Game sounds off · When it wins: Gentle · Sneaky on")
        let s = settings.current.games
        #expect(!s.sounds && s.speakers.isEmpty && s.tone == .gentle && s.sneaky)
        let back = await env.executor.execute(name: "games.settings", input: ["extension": "dev.sidefolk.playtime", "game": "trivia", "level": "default"],
                                              caller: .user)
        #expect(back.isOK && settings.current.games.levels["dev.sidefolk.playtime/trivia"] == nil)
        let wrong = await env.executor.execute(name: "games.settings", input: ["extension": "dev.sidefolk.playtime", "game": "trivia", "level": "nightmare"],
                                               caller: .user)
        #expect(!wrong.isOK)
    }
}
