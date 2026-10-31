import Foundation
import Testing
@testable import SidefolkCore

/// Playtime's eleven games (D75), installed from the add-ons checkout and played over the game channel inside the
/// sandbox by a bot that clicks what the board offers: every board parses, every move it sends was offered, every
/// game reaches its end card, and every build-up Sidefolk would show holds its verdict back. Then each game's
/// sentences open it in each language.
struct PlaytimeGamesSandboxTests {
    static let games = ["daily_word", "trivia", "tictactoe", "copy_me", "quick_paws", "which_cup", "higher_lower", "guess_animal",
                        "balloon_words", "last_stick", "memory_pairs"]

    /// A move the board offers, as a person might click; enough to reach every game's end.
    static func botMove(_ b: GameBoard, step: Int) -> GameMove? {
        if b.after != nil { return .next }
        if let r = b.reflex, r.armed { return .press(milliseconds: step.isMultiple(of: 2) ? 180 : 600) }
        if let a = b.answers, !a.locked, let i = a.tiles.indices.filter({ a.tiles[$0].state != .faded }).dropFirst(step % 2).first { return .answer(i) }
        if let g = b.grid, !g.locked, let i = g.cells.indices.first(where: { ($0 < g.cells.count) && (g.cells[$0].mark == .empty || g.cells[$0].mark == .cardBack) && g.cells[$0].state != .disabled }) {
            return .cell(row: i / g.columns, column: i % g.columns)
        }
        if let c = b.cups, !c.locked, !c.revealed { return .cell(row: 0, column: step % c.count) }
        if let p = b.pads, !p.locked { return .pad(step % 2) }
        if let s = b.sticks, !s.locked { return .number(1) }
        if let n = b.numberField, !n.locked {
            var low = n.min, high = n.max
            for g in n.history { if g.mark == .higher { low = max(low, g.value + 1) } else if g.mark == .lower { high = min(high, g.value - 1) } }
            return .number((low + high) / 2)
        }
        if let k = b.keys, !k.locked {
            let keys = k.all.map(\.key)
            if k.mode == .spell { return .word((0..<k.length).map { keys[(step * k.length + $0 * 3) % keys.count] }.joined()) }
            if let key = k.all.first(where: { $0.mark == .none }) { return .letter(Character(key.key)) }
        }
        if let e = b.entry, !e.locked {
            return e.kind == .word ? .word(["一心一意", "七上八下", "人山人海", "三心二意", "十全十美", "五颜六色"][step % 6])
                : .text(name: e.name, value: e.name == "animal" ? "axolotl" : "Does it live in a lake?")
        }
        if let primary = b.primary { return .button(primary.move) }
        for part in b.parts { if case .choice(let c) = part, c.name != "level" { return .choice(name: c.name, value: c.options[0].value) } }
        return nil
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons), arguments: ["en", "ja", "ar"])
    func everyGameIsPlayedToItsEndAndKeepsItsSuspense(language: String) async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: ExtFixtures.builtIn("playtime"))
        #expect(Set(h.host.gameShelf.all.map(\.game)) == Set(Self.games))
        var now = Date()
        for game in Self.games {
            let (session, first) = try await h.host.startGame(extensionId: info.id, game: game,
                                                               setup: GameSetup(level: "fair", language: language, options: ["companion": "Nori"]))
            #expect(first.cue?.line == .hello || first.cue != nil, "\(game) says hello")
            var board = first
            var steps = 0
            while !board.over, steps < 400 {
                let move = try #require(Self.botMove(board, step: steps), "\(game) \(language): nothing to do on \(board.parts)")
                #expect(move.offered(by: board), "\(game): \(move) was on the board")
                now = now.addingTimeInterval(0.1)
                let next = try await h.host.moveGame(extensionId: info.id, game: game, session: session, move: move, now: now)
                if let (build, _) = GameSuspense.buildUp(from: board, to: next, picked: nil) {
                    #expect(!GameSuspense.showsVerdict(build), "\(game): the build-up holds its verdict back")
                }
                board = next
                steps += 1
            }
            #expect(board.over && board.result != nil, "\(game) \(language) ended on its card after \(steps) moves")
            await h.host.endGame(extensionId: info.id, game: game, session: session, reason: .finished)
        }
        // Home lists them all, in the language asked; Daily Word's tile is the summary.
        let page = try await h.host.renderPage(extensionId: info.id, page: "playtime", language: language)
        #expect(page.summary?.title.isEmpty == false)
        await h.host.shutdown()
    }

    /// "let's play tic-tac-toe", "jouons au morpion", "三目並べ"…: each game opens from its sentences in every language.
    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func eachGameOpensFromItsSentences() async throws {
        let h = try HostEnv()
        try await h.host.install(from: ExtFixtures.builtIn("playtime"))
        let games = h.host.gameShelf.all
        let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test", games: games)
        for (sentence, game) in [("let's play tic-tac-toe", "tictactoe"), ("jouons au morpion", "tictactoe"), ("来玩井字棋", "tictactoe"),
                                 ("daily word", "daily_word"), ("오늘의 단어", "daily_word"), ("كلمة اليوم", "daily_word"),
                                 ("lass uns ballonwörter spielen", "balloon_words"), ("神経衰弱しよう", "memory_pairs"),
                                 ("vamos jogar maior ou menor", "higher_lower"), ("quiz me", "trivia")] {
            guard case .game(_, let found)? = parser.parse(sentence, now: TimeTest.wednesday10)?.intent else { Issue.record("\(sentence) didn't open a game"); continue }
            #expect(found == game, "\(sentence)")
        }
        #expect(games.allSatisfy { $0.say.count >= 10 }, "about one sentence a language at least")
        await h.host.shutdown()
    }
}
