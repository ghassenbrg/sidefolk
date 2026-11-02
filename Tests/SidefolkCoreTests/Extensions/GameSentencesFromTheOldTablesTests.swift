import Foundation
@testable import SidefolkCore
import Testing

/// Every sentence the app's own tables answered before the games left it (D101), kept here as those tables were, answered by Playtime's pack through the real parser; and with no
/// pack, by nothing. Skipped with no add-ons checkout at hand.
struct GameSentencesFromTheOldTablesTests {
    /// "show me the games": the app's `IntentGamesMenu.gamesMenuSentences`, whole.
    static let menu: Set<String> = [
        "games", "the games", "all the games", "all games", "play", "let's play", "lets play", "let's play a game", "let's play something",
        "play a game", "play something", "i want to play", "i want to play something", "i want to play a game", "i'd like to play",
        "show me the games", "show me all the games", "show me your games", "show the games", "show games", "show me games",
        "open the games", "open games", "game menu", "the game menu", "list the games", "list your games",
        "what games do you have", "what games are there", "what games can we play", "what games can i play", "what are the games",
        "what are all the games", "what are your games", "which games do you have", "which games are there", "what can we play",
        "back to the games", "back to games", "go back to the games", "back to the game menu", "back to the game list",
        "retour aux jeux", "reviens aux jeux", "volver a los juegos", "vuelve a los juegos", "zurück zu den spielen", "zurück zur spieleliste",
        "torna ai giochi", "tornare ai giochi", "voltar aos jogos", "volta aos jogos", "ゲーム一覧に戻って", "ゲーム一覧に戻る", "게임 목록으로",
        "게임 목록으로 돌아가", "回到游戏列表", "返回游戏列表", "العودة إلى الألعاب", "ارجع إلى الألعاب",
        "jeux", "les jeux", "jouer", "on joue", "jouons", "jouons à quelque chose", "on joue à un jeu", "je veux jouer",
        "je veux jouer à quelque chose", "montre-moi les jeux", "montre moi les jeux", "montre les jeux", "quels jeux as-tu",
        "quels sont les jeux", "à quoi on peut jouer", "à quoi peut-on jouer",
        "juegos", "los juegos", "jugar", "juguemos", "vamos a jugar", "juguemos a algo", "quiero jugar", "quiero jugar a algo",
        "muéstrame los juegos", "enséñame los juegos", "qué juegos tienes", "¿qué juegos tienes", "cuáles son los juegos",
        "a qué podemos jugar", "¿a qué podemos jugar",
        "spiele", "die spiele", "spielen", "lass uns spielen", "lass uns etwas spielen", "ich will spielen", "ich möchte spielen",
        "ich will etwas spielen", "zeig mir die spiele", "zeig mir alle spiele", "zeig die spiele", "welche spiele hast du",
        "welche spiele gibt es", "was können wir spielen",
        "giochi", "i giochi", "giocare", "giochiamo", "giochiamo a qualcosa", "voglio giocare", "voglio giocare a qualcosa",
        "mostrami i giochi", "fammi vedere i giochi", "che giochi hai", "quali giochi hai", "quali sono i giochi", "a cosa possiamo giocare",
        "jogos", "os jogos", "jogar", "vamos jogar", "vamos jogar alguma coisa", "quero jogar", "quero jogar alguma coisa",
        "me mostra os jogos", "mostre os jogos", "mostre-me os jogos", "quais jogos você tem", "que jogos você tem", "quais são os jogos",
        "o que podemos jogar",
        "ゲーム", "ゲーム一覧", "ゲームを見せて", "ゲームを全部見せて", "どんなゲームがある", "どんなゲームがあるの", "ゲームは何がある",
        "遊ぼう", "あそぼう", "何か遊ぼう", "なにか遊ぼう", "遊びたい", "ゲームしよう", "ゲームがしたい", "ゲームしたい",
        "게임", "게임 목록", "게임 보여줘", "게임 보여 줘", "게임 다 보여줘", "어떤 게임 있어", "무슨 게임 있어", "게임 뭐 있어",
        "놀자", "게임하자", "게임 하자", "뭐 하고 놀까", "놀고 싶어", "게임하고 싶어", "게임 하고 싶어",
        "游戏", "游戏列表", "给我看看游戏", "看看游戏", "有什么游戏", "有哪些游戏", "你有什么游戏", "玩", "来玩吧", "我们玩吧", "玩游戏",
        "我想玩", "我想玩游戏", "玩点什么",
        "ألعاب", "الألعاب", "العب", "لنلعب", "هيا نلعب", "لنلعب شيئًا", "لنلعب شيئا", "أريد أن ألعب", "أريد أن ألعب شيئًا", "أرني الألعاب",
        "اعرض الألعاب", "ما الألعاب التي لديك", "ما هي الألعاب", "ماذا يمكننا أن نلعب",
    ]

    /// Who guesses: the app's `GameSlotWords.modes`, whole.
    static let modes: [(String, String)] = [
        ("guess a number", "mine"), ("guess your number", "mine"), ("i guess your number", "mine"), ("let me guess your number", "mine"),
        ("i'll guess your number", "mine"), ("think of a number", "mine"), ("you think of a number", "mine"),
        ("deviner un nombre", "mine"), ("devine un nombre", "mine"), ("je devine ton nombre", "mine"), ("pense à un nombre", "mine"),
        ("adivina un número", "mine"), ("adivinar un número", "mine"), ("yo adivino tu número", "mine"), ("piensa en un número", "mine"),
        ("rate eine zahl", "mine"), ("zahl raten", "mine"), ("ich rate deine zahl", "mine"), ("denk dir eine zahl aus", "mine"),
        ("indovina un numero", "mine"), ("indovinare un numero", "mine"), ("indovino il tuo numero", "mine"), ("pensa a un numero", "mine"),
        ("adivinhe um número", "mine"), ("adivinha um número", "mine"), ("adivinhar um número", "mine"), ("eu adivinho seu número", "mine"),
        ("pense em um número", "mine"),
        ("数当て", "mine"), ("数あて", "mine"), ("数字当て", "mine"), ("あなたの数字を当てる", "mine"), ("数字を考えて", "mine"),
        ("숫자 맞히기", "mine"), ("숫자 맞추기", "mine"), ("네 숫자 맞힐게", "mine"), ("숫자 하나 생각해", "mine"),
        ("猜数字", "mine"), ("我猜你的数字", "mine"), ("你想一个数字", "mine"),
        ("خمن رقما", "mine"), ("خمن رقمًا", "mine"), ("تخمين رقم", "mine"), ("سأخمن رقمك", "mine"), ("فكر في رقم", "mine"),
        ("you guess my number", "yours"), ("guess my number", "yours"), ("try to guess my number", "yours"), ("i'll think of a number", "yours"),
        ("i think of a number", "yours"), ("i'll pick a number", "yours"),
        ("devine mon nombre", "yours"), ("tu devines mon nombre", "yours"), ("je pense à un nombre", "yours"),
        ("adivina mi número", "yours"), ("tú adivinas mi número", "yours"), ("pienso un número", "yours"), ("yo pienso un número", "yours"),
        ("rate meine zahl", "yours"), ("du rätst meine zahl", "yours"), ("ich denke mir eine zahl aus", "yours"),
        ("indovina il mio numero", "yours"), ("tu indovini il mio numero", "yours"), ("penso a un numero", "yours"),
        ("adivinhe meu número", "yours"), ("adivinha meu número", "yours"), ("adivinhe o meu número", "yours"),
        ("você adivinha meu número", "yours"), ("eu penso em um número", "yours"),
        ("私の数字を当てて", "yours"), ("わたしの数字を当てて", "yours"), ("僕の数字を当てて", "yours"), ("数字を当てて", "yours"),
        ("내 숫자 맞혀봐", "yours"), ("내 숫자 맞혀 봐", "yours"), ("내 숫자 맞춰봐", "yours"), ("내 숫자 맞혀", "yours"),
        ("猜我的数字", "yours"), ("你猜我的数字", "yours"), ("猜猜我的数字", "yours"), ("我想一个数字", "yours"),
        ("خمن رقمي", "yours"), ("حاول تخمين رقمي", "yours"), ("سأفكر في رقم", "yours"),
    ]

    private static func tools(_ folder: String) throws -> [ExtensionTool] {
        let (m, strings) = try GameCommandsInThePackTests.loaded(folder)
        let v = CommandVocabulary(manifest: m, strings: strings)
        return m.tools.keys.sorted().compactMap { name -> ExtensionTool? in
            guard let meta = m.tools[name], let commands = ToolCommands(meta.commands, vocabulary: v) else { return nil }
            let spec = ToolSpec(name: "ext.playtime.\(name)", title: name, description: "d", inputSchema: ["type": "object"], risk: .low, capabilities: [], category: .extensions, mutates: false)
            return ExtensionTool(spec: spec, extensionId: m.id, extensionName: m.name, remoteName: name, commands: commands) { _, _ in ToolResult(text: "") }
        }
    }

    private static func parser(_ tools: [ExtensionTool] = [], companion: String = "Mochi") -> IntentParser {
        IntentParser(when: TimeTest.parser(), home: "/Users/test", companionNames: ["sidefolk", "pip", companion], commandTools: tools)
    }

    private static func call(_ parser: IntentParser, _ text: String) -> ExtensionCommandCall? {
        if case .extensionCommand(let call)? = parser.parse(text, now: TimeTest.wednesday10)?.intent { return call }
        return nil
    }

    /// Tables, whole, with the pack: each opens what it did. With nothing installed none of them is anything.
    @Test func everyMenuSentence() throws {
        guard let folder = GameCommandsInThePackTests.folder else { return }
        let parser = Self.parser(try Self.tools(folder))
        #expect(Self.menu.count == 190)
        for sentence in Self.menu.sorted() {
            let call = Self.call(parser, sentence)
            #expect(call?.tool == "ext.playtime.open" && call?.input["game"]?.stringValue == "menu", "“\(sentence)”: \(String(describing: call?.input))")
        }
    }

    @Test func everyMenuSentenceIsNothingWithoutThePack() {
        let parser = Self.parser()
        for sentence in Self.menu.sorted() {
            let parsed = parser.parse(sentence, now: TimeTest.wednesday10)?.intent
            if case .find? = parsed { continue }
            #expect(parsed == nil, "“\(sentence)” is \(String(describing: parsed))")
        }
    }

    @Test func everyWhoGuessesSentence() throws {
        guard let folder = GameCommandsInThePackTests.folder else { return }
        let parser = Self.parser(try Self.tools(folder))
        #expect(Self.modes.count == 84)
        for (sentence, mode) in Self.modes {
            let input = Self.call(parser, sentence)?.input
            #expect(input?["game"]?.stringValue == "higher_lower" && input?["mode"]?.stringValue == mode, "“\(sentence)”: \(String(describing: input))")
            #expect(Self.call(Self.parser(), sentence) == nil, "“\(sentence)” with nothing installed")
        }
        // A range around one of them, as the old table took.
        #expect(Self.call(parser, "guess a number up to 500")?.input["max"]?.intValue == 500)
        let thinking = Self.call(parser, "i think of a number up to 100")?.input
        #expect(thinking?["mode"]?.stringValue == "yours" && thinking?["max"]?.intValue == 100, "the person thinks of it, so the companion guesses")
    }

    /// Everything the old chance patterns took: every way through them.
    @Test func everyWayThroughTheOldChancePatterns() throws {
        guard let folder = GameCommandsInThePackTests.folder else { return }
        let parser = Self.parser(try Self.tools(folder))
        func kind(_ text: String) -> JSONValue? {
            let call = Self.call(parser, text)
            return call?.tool == "ext.playtime.toss" ? call?.input : nil
        }
        let tails = ["", " for me", " again", " for me again"]
        for lets in ["", "let's "] {
            for verb in ["flip", "toss"] {
                for article in ["a", "one", "the"] {
                    for tail in tails { #expect(kind("\(lets)\(verb) \(article) coin\(tail)")?["kind"]?.stringValue == "coin", "\(lets)\(verb) \(article) coin\(tail)") }
                }
            }
        }
        for call in ["heads", ", heads", ": heads", "; heads", " - heads", " i call heads", ", i call heads", " and i call heads", ", i say heads", " i pick heads", ", i choose heads", " i go with heads", " i bet heads", " i bet on heads"] {
            for coin in ["flip a coin", "toss the coin", "coin flip", "coin toss", "flip a coin for me"] {
                let text = call.first == " " || call.first == "," || call.first == ":" || call.first == ";" ? coin + call : coin + " " + call
                #expect(kind(text)?["call"]?.stringValue == "heads", "\(text)")
            }
        }
        #expect(kind("coin flip again")?["kind"]?.stringValue == "coin" && kind("do a coin toss for me")?["kind"]?.stringValue == "coin")
        #expect(kind("flip 3 coins for me again")?["count"]?.intValue == 3 && kind("toss two coins for me")?["many"]?.stringValue == "n2")
        for lets in ["", "let's "] {
            for verb in ["roll", "throw"] {
                for die in ["a die", "a dice", "a d6", "one die", "one dice", "one d6", "the die", "the d6"] {
                    for tail in tails {
                        let got = kind("\(lets)\(verb) \(die)\(tail)")
                        #expect(got?["kind"]?.stringValue == "dice" && got?["count"] == nil, "\(lets)\(verb) \(die)\(tail)")
                    }
                }
                for dice in ["the dice", "dice"] {
                    for tail in tails { #expect(kind("\(lets)\(verb) \(dice)\(tail)")?["count"]?.intValue == 2, "\(lets)\(verb) \(dice)\(tail)") }
                }
            }
        }
        for verb in ["roll", "throw"] {
            for tail in tails {
                #expect(kind("\(verb) 3 dice\(tail)")?["count"]?.intValue == 3, "\(verb) 3 dice\(tail)")
                #expect(kind("\(verb) two dice\(tail)")?["many"]?.stringValue == "n2")
                #expect(kind("\(verb) 2 d20s\(tail)")?["sides"]?.intValue == 20)
                #expect(kind("\(verb) two d20s\(tail)")?["sides"]?.intValue == 20)
                for article in ["", "a ", "an ", "one "] {
                    #expect(kind("\(verb) \(article)d20\(tail)")?["sides"]?.intValue == 20, "\(verb) \(article)d20\(tail)")
                    #expect(kind("\(verb) \(article)d20+5\(tail)")?["modifier"]?.intValue == 5, "\(verb) \(article)d20+5\(tail)")
                    #expect(kind("\(verb) \(article)d20 + 5\(tail)")?["modifier"]?.intValue == 5, "\(verb) \(article)d20 + 5\(tail)")
                    #expect(kind("\(verb) \(article)d20 +5\(tail)")?["modifier"]?.intValue == 5)
                    #expect(kind("\(verb) \(article)d20-2\(tail)")?["minus"]?.intValue == 2)
                    #expect(kind("\(verb) \(article)d20 - 2\(tail)")?["minus"]?.intValue == 2)
                }
                #expect(kind("\(verb) 2d6+1\(tail)")?["modifier"]?.intValue == 1, "\(verb) 2d6+1\(tail)")
                #expect(kind("\(verb) 2d6 +1\(tail)")?["modifier"]?.intValue == 1)
                #expect(kind("\(verb) 2d6 - 1\(tail)")?["minus"]?.intValue == 1)
                for article in ["a", "an", "one"] {
                    for joint in ["-", " "] {
                        for die in ["die", "dice"] {
                            #expect(kind("\(verb) \(article) 12\(joint)sided \(die)\(tail)")?["sides"]?.intValue == 12, "\(verb) \(article) 12\(joint)sided \(die)\(tail)")
                        }
                    }
                }
            }
        }
        // Hands: the old pattern, with and without its lead-in.
        let leads = ["", "rock paper scissors ", "rock paper scissors, ", "rock paper scissors: ", "rock, paper, scissors - ", "rps ", "rps: ", "play rock paper scissors ", "let's play rps - ", "let's play rock, paper, scissors: ", "rock, paper, and scissors! "]
        for lead in leads {
            for playing in ["", "i choose ", "i pick ", "i play ", "i throw ", "i go with ", "i'll play ", "i'll pick ", "i'll throw ", "i'll go with ", "my hand is "] {
                #expect(kind("\(lead)\(playing)paper")?["hand"]?.stringValue == "paper", "\(lead)\(playing)paper")
            }
        }
        for asked in ["rps with me", "rock, paper, and scissors", "rock paper or scissors", "let's play rps", "i want to play rock paper scissors", "play rock paper scissors with me"] {
            #expect(Self.call(parser, asked)?.input["game"]?.stringValue == "rock_paper_scissors", "\(asked)")
        }
        for no in ["flip a coin to decide where we eat", "rock music", "roll back the last commit", "paper towels", "heads up", "rock paper scissors is a silly game",
                   "flip 20 coins", "roll 50 dice", "roll a d1", "do a flip", "let's", "for me", "again"] {
            #expect(kind(no) == nil, "\(no)")
        }
    }

    /// Calling the companion by name doesn't lose a sentence (the old parser's fillers held its names).
    @Test func theCompanionsNameCarriesAGamesSentence() throws {
        guard let folder = GameCommandsInThePackTests.folder else { return }
        let parser = Self.parser(try Self.tools(folder))
        for (text, game) in [("play trivia with mochi", "trivia"), ("mochi let's play trivia", "trivia"), ("play sudoku with mochi", "sudoku"), ("let's play trivia mochi", "trivia"),
                             ("play trivia against mochi", "trivia"), ("mochi, let's play trivia", "trivia"), ("jouons au morpion avec mochi", "tictactoe")] {
            #expect(Self.call(parser, text)?.input["game"]?.stringValue == game, "\(text)")
        }
        #expect(Self.call(parser, "play trivia with tom") == nil, "someone else isn't a carrying word")
    }
}
