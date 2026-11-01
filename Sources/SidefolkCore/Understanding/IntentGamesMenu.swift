import Foundation

/// "show me the games", "what games do you have", "let's play", "games": the Play panel's menu of every game (D79
/// amended), right away and without AI, in the ten languages Sidefolk speaks (an exception to D76's English commands,
/// like a game's own sentences). Whole sentences only: "play trivia" is the game, "play this on the TV" an extension's.
extension IntentParser {
    /// Each as the parser sees it: lowercased, its last punctuation gone, English lead-ins ("please", "can you") removed.
    static let gamesMenuSentences: Set<String> = [
        // English
        "games", "the games", "all the games", "all games", "play", "let's play", "lets play", "let's play a game", "let's play something",
        "play a game", "play something", "i want to play", "i want to play something", "i want to play a game", "i'd like to play",
        "show me the games", "show me all the games", "show me your games", "show the games", "show games", "show me games",
        "open the games", "open games", "game menu", "the game menu", "list the games", "list your games",
        "what games do you have", "what games are there", "what games can we play", "what games can i play", "what are the games",
        "what are all the games", "what are your games", "which games do you have", "which games are there", "what can we play",
        // French
        "jeux", "les jeux", "jouer", "on joue", "jouons", "jouons à quelque chose", "on joue à un jeu", "je veux jouer",
        "je veux jouer à quelque chose", "montre-moi les jeux", "montre moi les jeux", "montre les jeux", "quels jeux as-tu",
        "quels sont les jeux", "à quoi on peut jouer", "à quoi peut-on jouer",
        // Spanish
        "juegos", "los juegos", "jugar", "juguemos", "vamos a jugar", "juguemos a algo", "quiero jugar", "quiero jugar a algo",
        "muéstrame los juegos", "enséñame los juegos", "qué juegos tienes", "¿qué juegos tienes", "cuáles son los juegos",
        "a qué podemos jugar", "¿a qué podemos jugar",
        // German
        "spiele", "die spiele", "spielen", "lass uns spielen", "lass uns etwas spielen", "ich will spielen", "ich möchte spielen",
        "ich will etwas spielen", "zeig mir die spiele", "zeig mir alle spiele", "zeig die spiele", "welche spiele hast du",
        "welche spiele gibt es", "was können wir spielen",
        // Italian
        "giochi", "i giochi", "giocare", "giochiamo", "giochiamo a qualcosa", "voglio giocare", "voglio giocare a qualcosa",
        "mostrami i giochi", "fammi vedere i giochi", "che giochi hai", "quali giochi hai", "quali sono i giochi", "a cosa possiamo giocare",
        // Portuguese (Brazil)
        "jogos", "os jogos", "jogar", "vamos jogar", "vamos jogar alguma coisa", "quero jogar", "quero jogar alguma coisa",
        "me mostra os jogos", "mostre os jogos", "mostre-me os jogos", "quais jogos você tem", "que jogos você tem", "quais são os jogos",
        "o que podemos jogar",
        // Japanese
        "ゲーム", "ゲーム一覧", "ゲームを見せて", "ゲームを全部見せて", "どんなゲームがある", "どんなゲームがあるの", "ゲームは何がある",
        "遊ぼう", "あそぼう", "何か遊ぼう", "なにか遊ぼう", "遊びたい", "ゲームしよう", "ゲームがしたい", "ゲームしたい",
        // Korean
        "게임", "게임 목록", "게임 보여줘", "게임 보여 줘", "게임 다 보여줘", "어떤 게임 있어", "무슨 게임 있어", "게임 뭐 있어",
        "놀자", "게임하자", "게임 하자", "뭐 하고 놀까", "놀고 싶어", "게임하고 싶어", "게임 하고 싶어",
        // Chinese (Simplified)
        "游戏", "游戏列表", "给我看看游戏", "看看游戏", "有什么游戏", "有哪些游戏", "你有什么游戏", "玩", "来玩吧", "我们玩吧", "玩游戏",
        "我想玩", "我想玩游戏", "玩点什么",
        // Arabic
        "ألعاب", "الألعاب", "العب", "لنلعب", "هيا نلعب", "لنلعب شيئًا", "لنلعب شيئا", "أريد أن ألعب", "أريد أن ألعب شيئًا", "أرني الألعاب",
        "اعرض الألعاب", "ما الألعاب التي لديك", "ما هي الألعاب", "ماذا يمكننا أن نلعب",
    ]

    func gamesMenu(_ command: String) -> ParsedIntent? {
        let text = command.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " !.?？！。؟"))
        guard Self.gamesMenuSentences.contains(text) else { return nil }
        return ParsedIntent(intent: .gamesMenu,
                            hint: ParsedIntent.hint(String(localized: "Show the games", comment: "Opening the Play panel's menu of every game")))
    }
}
