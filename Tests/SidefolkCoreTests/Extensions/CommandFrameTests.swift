import Foundation
@testable import SidefolkCore
import Testing

/// Commands with slots (D100): everything the app's own game sentences do (`IntentGameCommands`, D93) said through what any
/// extension can declare, with no game names in the mechanism: this file is the proof that the sentences can move.
/// The words are the app's own tables, handed over as an extension's manifest and `strings/` would hold them.
struct CommandFrameTests {
    static let phrases: [String: [String]] = [
        "level": ["{level:level}"],
        "count": ["{count:integer:1-50} questions", "{count:integer:1-50} question", "{count:integer:1-50} rounds", "{count:integer:1-50} qs",
                  "{count:integer:1-50} questions", "{count:integer:1-50} manches", "{count:integer:1-50} preguntas", "{count:integer:1-50} fragen",
                  "{count:integer:1-50} domande", "{count:integer:1-50} perguntas", "{count:integer:1-50}問", "{count:integer:1-50}문제",
                  "{count:integer:1-50}道题", "{count:integer:1-50} أسئلة"],
        "range": ["between {min:integer} and {max:integer}", "from {min:integer} to {max:integer}", "{min:integer} to {max:integer}",
                  "entre {min:integer} et {max:integer}", "entre {min:integer} y {max:integer}", "zwischen {min:integer} und {max:integer}",
                  "tra {min:integer} e {max:integer}", "entre {min:integer} e {max:integer}", "{min:integer}から{max:integer}まで",
                  "{min:integer}부터 {max:integer}까지", "{min:integer}到{max:integer}", "بين {min:integer} و {max:integer}",
                  "up to {max:integer}", "at most {max:integer}", "jusqu'à {max:integer}", "hasta {max:integer}", "bis {max:integer}", "fino a {max:integer}",
                  "até {max:integer}", "{max:integer}まで", "{max:integer}까지", "{max:integer}以内", "حتى {max:integer}"],
        "topic": ["about {topic:text:40}", "on the topic of {topic:text:40}", "sur {topic:text:40}", "sobre {topic:text:40}", "über {topic:text:40}",
                  "su {topic:text:40}", "sul {topic:text:40}", "{topic:text:40}について", "{topic:text:40}에 대한", "关于{topic:text:40}的", "عن {topic:text:40}"],
    ]

    static let manifestLike: CommandVocabulary = {
        var v = CommandVocabulary()
        var levels: [String: [String]] = [:]
        for (word, value) in GameSlotWords.levels { levels[value, default: []].append(word) }
        v.choices = ["level": levels]
        v.parts = phrases.mapValues { [ExtensionManifest.PartMeta(say: $0)] }
        v.parts["friend"] = [ExtensionManifest.PartMeta(say: GameSlotWords.twoPlayers, input: ["players": 2])]
        v.carry = CommandCarry([ExtensionManifest.CarryMeta(words: Array(GameSlotWords.fillers), lead: Array(GameSlotWords.playWords) + GameSlotWords.playJoined,
                                                            inside: GameSlotWords.joined, endings: GameSlotWords.particles)])
        return v
    }()

    static func open(_ game: String, names: [String], with: [String], extra: [String: JSONValue] = [:]) -> ExtensionManifest.Command {
        var input: [String: JSONValue] = ["game": .string(game)]
        input.merge(extra) { own, _ in own }
        return ExtensionManifest.Command(say: [], names: names, with: with, input: input)
    }

    static let tool = ToolCommands([
        ExtensionManifest.Command(say: ["rematch", "play again", "revanche", "otra partida", "noch eine runde", "もう一回やろう", "한 판 더", "再来一局", "مباراة أخرى"], input: ["do": "again"]),
        ExtensionManifest.Command(say: ["make it harder", "too easy", "plus difficile", "más difícil", "mach es schwerer", "更难", "أصعب"], input: ["do": "harder"]),
        ExtensionManifest.Command(say: ["show my stats", "my scores"], input: ["do": "stats"]),
        ExtensionManifest.Command(say: ["turn game sounds off", "게임 소리 꺼줘"], input: ["do": "quiet"]),
        open("trivia", names: ["trivia", "quiz", "quiz me", "jouons au quiz", "lass uns ein quiz spielen", "クイズしよう"], with: ["level", "count", "topic", "friend"]),
        open("tictactoe", names: ["tic tac toe", "tic-tac-toe", "jouons au morpion", "lass uns tic-tac-toe spielen", "まるばつゲーム", "틱택토 하자", "来玩井字棋", "لنلعب إكس أو"],
             with: ["level", "friend"]),
        open("higher_lower", names: ["higher or lower"], with: ["range"]),
        open("higher_lower", names: ["guess a number", "deviner un nombre", "rate eine zahl", "猜数字"], with: ["range"], extra: ["mode": "mine"]),
        open("higher_lower", names: ["you guess my number", "guess my number", "devine mon nombre", "خمن رقمي"], with: ["range"], extra: ["mode": "yours"]),
        open("sudoku", names: ["sudoku", "数独をしよう"], with: ["level"]),
        open("daily_word", names: ["daily word", "today's word", "word of the day"], with: []),
    ], vocabulary: manifestLike)!

    func input(_ text: String) -> [String: JSONValue]? { Self.tool.input(for: text)?.objectValue }

    @Test func aNameWithPartsInAnyOrderAndLanguage() {
        let cases: [(String, [String: JSONValue])] = [
            ("play trivia on easy", ["game": "trivia", "level": "easy"]),
            ("trivia about space, hard, 10 questions", ["game": "trivia", "level": "hard", "topic": "space", "count": 10]),
            ("let's play trivia about space with 10 questions on hard", ["game": "trivia", "level": "hard", "topic": "space", "count": 10]),
            ("quiz me about the roman empire, 5 questions", ["game": "trivia", "topic": "roman empire", "count": 5]),
            ("jouons au quiz sur l'espace", ["game": "trivia", "topic": "l'espace"]),
            ("lass uns ein quiz über Tiere spielen", ["game": "trivia", "topic": "Tiere"]),
            ("play tic-tac-toe on hard", ["game": "tictactoe", "level": "hard"]),
            ("tic tac toe, easy", ["game": "tictactoe", "level": "easy"]),
            ("let's play a game of tic tac toe against you", ["game": "tictactoe"]),
            ("play tic tac toe with a friend", ["game": "tictactoe", "players": 2]),
            ("jouons au morpion difficile", ["game": "tictactoe", "level": "hard"]),
            ("lass uns tic-tac-toe auf schwer spielen", ["game": "tictactoe", "level": "hard"]),
            ("まるばつゲームを難しいでしよう", ["game": "tictactoe", "level": "hard"]),
            ("어려운 틱택토 하자", ["game": "tictactoe", "level": "hard"]),
            ("来玩简单的井字棋", ["game": "tictactoe", "level": "easy"]),
            ("لنلعب إكس أو على مستوى صعب", ["game": "tictactoe", "level": "hard"]),
            ("guess a number between 1 and 1000", ["game": "higher_lower", "mode": "mine", "min": 1, "max": 1000]),
            ("you guess my number up to 500", ["game": "higher_lower", "mode": "yours", "max": 500]),
            ("devine mon nombre jusqu'à 200", ["game": "higher_lower", "mode": "yours", "max": 200]),
            ("rate eine Zahl zwischen 1 und 5000", ["game": "higher_lower", "mode": "mine", "min": 1, "max": 5000]),
            ("猜数字 1到1000", ["game": "higher_lower", "mode": "mine", "min": 1, "max": 1000]),
            ("خمن رقمي حتى ٥٠٠", ["game": "higher_lower", "mode": "yours", "max": 500]),
            ("play higher or lower up to 1000", ["game": "higher_lower", "max": 1000]),
            ("today's word", ["game": "daily_word"]),
            ("sudoku hard", ["game": "sudoku", "level": "hard"]),
            ("数独を難しいでしよう", ["game": "sudoku", "level": "hard"]),
        ]
        for (text, expected) in cases { #expect(input(text) == expected, "\(text)") }
    }

    @Test func wholeSentencesTheExtensionHandlesInEveryScript() {
        let cases: [(String, JSONValue)] = [
            ("rematch", "again"), ("Revanche!", "again"), ("otra partida", "again"), ("noch eine runde", "again"), ("もう一回やろう", "again"),
            ("한판 더", "again"), ("再来一局", "again"), ("مباراة أخرى", "again"),
            ("make it harder", "harder"), ("Too easy!", "harder"), ("mas dificil", "harder"), ("更难", "harder"), ("أصعب", "harder"),
            ("show my stats", "stats"), ("게임 소리 꺼줘", "quiet"),
        ]
        for (text, expected) in cases { #expect(input(text)?["do"] == expected, "\(text)") }
    }

    @Test func whatStaysWithTheAIOrAnotherExtension() {
        for text in ["copy", "memory", "play some music", "play this on the TV", "start the timer", "hard", "again", "nochmal",
                     "sudoku 10 questions", "tic-tac-toe about space", "guess a number between 1000 and 1",
                     "trivia about " + String(repeating: "a", count: 60), "tell me about trivia", "play tic-tac-toe on hard and easy",
                     "how are my stats at work", "higher or lower on hard", "trivia 500 questions", "tic tac toe"] {
            #expect(input(text) == nil, "\(text)")
        }
        // A name alone needs a word saying it is meant, unless it is also a whole sentence of its own.
        #expect(input("play tic tac toe")?["game"] == "tictactoe")
    }

    @Test func anEnumGivesItsValueWhateverTheLanguageItWasSaidIn() throws {
        let choices = ["level": ["easy": ["easy", "facile"], "hard": ["hard", "difficile"]]]
        let sentence = try CommandSentence("play on {level:level}", choices: choices)
        #expect(sentence.match("play on difficile") == ["level": "hard"])
        #expect(sentence.match("play on HARD") == ["level": "hard"])
        #expect(sentence.match("play on medium") == nil)
    }

    @Test func boundsAreChecked() throws {
        let s = try CommandSentence("go {n:integer:1-50}")
        #expect(s.match("go 50") == ["n": 50])
        #expect(s.match("go 51") == nil)
        #expect(throws: CommandProblem.self) { try CommandSentence("go {n:word:1-50}") }
        let t = try CommandSentence("about {t:text:5}")
        #expect(t.match("about hello") == ["t": "hello"])
        #expect(t.match("about hello there") == nil)
    }

    @Test func approvalWordsInAnyLanguageAreNeverACommand() {
        for word in ["yes", "No", "approve", "deny", "allow", "always allow", "oui", "ja", "はい", "네", "是", "نعم", "non", "nein", "いいえ"] {
            #expect(throws: CommandProblem.self, "\(word)") { try CommandSentence(word) }
        }
    }
}
