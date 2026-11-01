import Foundation

/// The words around a game's name in the ten languages (D93): its level, how many questions, a quiz's topic, a number
/// game's range and who guesses, and the words that only carry the sentence ("let's", "play", "jouons", "しよう"). Each
/// slot is a pattern Sidefolk takes out of the sentence; what remains, without the carrying words, must be a game's
/// name and nothing else, or the sentence goes to the AI.
enum GameSlotWords {
    /// A level word and the level it means; the game's own levels decide which of its levels that is (`GameLevels.match`).
    static let levels: [(String, String)] = [
        ("easy", "easy"), ("beginner", "easy"), ("facile", "easy"), ("fácil", "easy"), ("leicht", "easy"), ("einfach", "easy"),
        ("かんたん", "easy"), ("簡単", "easy"), ("やさしい", "easy"), ("易しい", "easy"), ("쉬움", "easy"), ("쉬운", "easy"), ("쉽게", "easy"),
        ("简单", "easy"), ("容易", "easy"), ("سهل", "easy"), ("سهلة", "easy"), ("السهل", "easy"),
        ("fair", "fair"), ("medium", "fair"), ("normal", "fair"), ("moyen", "fair"), ("medio", "fair"), ("mittel", "fair"), ("normale", "fair"),
        ("médio", "fair"), ("ふつう", "fair"), ("普通", "fair"), ("보통", "fair"), ("中等", "fair"), ("متوسط", "fair"), ("عادي", "fair"),
        ("المتوسط", "fair"),
        ("hard", "hard"), ("difficult", "hard"), ("expert", "hard"), ("difficile", "hard"), ("dur", "hard"), ("difícil", "hard"),
        ("schwer", "hard"), ("schwierig", "hard"), ("むずかしい", "hard"), ("難しい", "hard"), ("어려움", "hard"), ("어려운", "hard"),
        ("어렵게", "hard"), ("困难", "hard"), ("难", "hard"), ("صعب", "hard"), ("صعبة", "hard"), ("الصعب", "hard"),
    ]

    /// A count of questions or rounds: the number is the first group.
    static let count = [
        #"(\d{1,3})\s*(?:questions?|rounds?|qs)"#, #"(\d{1,3})\s*(?:questions?|manches?|tours?)"#, #"(\d{1,3})\s*(?:preguntas?|rondas?)"#,
        #"(\d{1,3})\s*(?:fragen?|runden?)"#, #"(\d{1,3})\s*(?:domande|domanda|round)"#, #"(\d{1,3})\s*(?:perguntas?|rodadas?)"#,
        #"(\d{1,3})\s*(?:問題|問|もん)"#, #"(\d{1,3})\s*(?:문제|문항|라운드)"#, #"(\d{1,3})\s*(?:道题|道|个问题|题|轮)"#,
        #"(\d{1,3})\s*(?:أسئلة|سؤالًا|سؤالا|سؤال|جولات|جولة)"#,
    ]

    /// A range from the first group to the second.
    static let range = [
        #"(?:between|from)\s+(\d+)\s+(?:and|to)\s+(\d+)"#, #"(\d+)\s*(?:-|–|to)\s*(\d+)"#,
        #"(?:entre|de)\s+(\d+)\s+(?:et|à)\s+(\d+)"#, #"(?:entre|del?|desde)\s+(\d+)\s+(?:y|al?|hasta)\s+(\d+)"#,
        #"(?:zwischen|von)\s+(\d+)\s+(?:und|bis)\s+(\d+)"#, #"(?:tra|fra|da)\s+(\d+)\s+(?:e|a)\s+(\d+)"#,
        #"(?:entre|de)\s+(\d+)\s+(?:e|a)\s+(\d+)"#, #"(\d+)\s*(?:から|〜|~)\s*(\d+)\s*(?:まで)?"#,
        #"(\d+)\s*(?:부터|에서)\s*(\d+)\s*(?:까지)?"#, #"从?\s*(\d+)\s*(?:到|至)\s*(\d+)\s*(?:之间)?"#,
        #"(?:بين|من)\s+(\d+)\s+(?:و|إلى|الى)\s*(\d+)"#,
    ]

    /// A range's top only (from 1).
    static let upTo = [
        #"(?:up\s+to|at\s+most|max(?:imum)?)\s+(\d+)"#, #"jusqu'?\s*(?:à|a)\s+(\d+)"#, #"hasta(?:\s+el)?\s+(\d+)"#, #"bis(?:\s+zu)?\s+(\d+)"#,
        #"fino\s+al?\s+(\d+)"#, #"até(?:\s+o)?\s+(\d+)"#, #"(\d+)\s*まで"#, #"(\d+)\s*까지"#, #"(\d+)\s*以内"#, #"حتى\s+(\d+)"#,
    ]

    /// A quiz's topic: what follows these words, to a comma or the end.
    static let topic = [
        #"(?:about|on\s+the\s+topic\s+of|on\s+the\s+subject\s+of)\s+(.+)"#, #"(?:sur(?:\s+le|\s+la|\s+les)?|à\s+propos\s+de)\s+(.+)"#,
        #"sobre(?:\s+el|\s+la|\s+los|\s+las|\s+o|\s+a|\s+os|\s+as)?\s+(.+)"#, #"(?:über(?:\s+das|\s+die|\s+den)?|zum\s+thema)\s+(.+)"#,
        #"(?:sul|sulla|sullo|sui|sugli|sulle|su)\s+(.+)"#, #"(.+?)(?:について|に関する)"#, #"(.+?)\s*(?:에\s*대한|관련)"#,
        #"关于\s*(.+?)的"#, #"(?:عن|حول)\s+(.+)"#,
    ]

    /// Who guesses in a number game; each phrase also names it.
    static let modes: [(String, GameSlots.Mode)] = [
        ("guess a number", .mine), ("guess your number", .mine), ("i guess your number", .mine), ("let me guess your number", .mine),
        ("i'll guess your number", .mine), ("think of a number", .mine), ("you think of a number", .mine),
        ("deviner un nombre", .mine), ("devine un nombre", .mine), ("je devine ton nombre", .mine), ("pense à un nombre", .mine),
        ("adivina un número", .mine), ("adivinar un número", .mine), ("yo adivino tu número", .mine), ("piensa en un número", .mine),
        ("rate eine zahl", .mine), ("zahl raten", .mine), ("ich rate deine zahl", .mine), ("denk dir eine zahl aus", .mine),
        ("indovina un numero", .mine), ("indovinare un numero", .mine), ("indovino il tuo numero", .mine), ("pensa a un numero", .mine),
        ("adivinhe um número", .mine), ("adivinha um número", .mine), ("adivinhar um número", .mine), ("eu adivinho seu número", .mine),
        ("pense em um número", .mine),
        ("数当て", .mine), ("数あて", .mine), ("数字当て", .mine), ("あなたの数字を当てる", .mine), ("数字を考えて", .mine),
        ("숫자 맞히기", .mine), ("숫자 맞추기", .mine), ("네 숫자 맞힐게", .mine), ("숫자 하나 생각해", .mine),
        ("猜数字", .mine), ("我猜你的数字", .mine), ("你想一个数字", .mine),
        ("خمن رقما", .mine), ("خمن رقمًا", .mine), ("تخمين رقم", .mine), ("سأخمن رقمك", .mine), ("فكر في رقم", .mine),
        ("you guess my number", .yours), ("guess my number", .yours), ("try to guess my number", .yours), ("i'll think of a number", .yours),
        ("i think of a number", .yours), ("i'll pick a number", .yours),
        ("devine mon nombre", .yours), ("tu devines mon nombre", .yours), ("je pense à un nombre", .yours),
        ("adivina mi número", .yours), ("tú adivinas mi número", .yours), ("pienso un número", .yours), ("yo pienso un número", .yours),
        ("rate meine zahl", .yours), ("du rätst meine zahl", .yours), ("ich denke mir eine zahl aus", .yours),
        ("indovina il mio numero", .yours), ("tu indovini il mio numero", .yours), ("penso a un numero", .yours),
        ("adivinhe meu número", .yours), ("adivinha meu número", .yours), ("adivinhe o meu número", .yours),
        ("você adivinha meu número", .yours), ("eu penso em um número", .yours),
        ("私の数字を当てて", .yours), ("わたしの数字を当てて", .yours), ("僕の数字を当てて", .yours), ("数字を当てて", .yours),
        ("내 숫자 맞혀봐", .yours), ("내 숫자 맞혀 봐", .yours), ("내 숫자 맞춰봐", .yours), ("내 숫자 맞혀", .yours),
        ("猜我的数字", .yours), ("你猜我的数字", .yours), ("猜猜我的数字", .yours), ("我想一个数字", .yours),
        ("خمن رقمي", .yours), ("حاول تخمين رقمي", .yours), ("سأفكر في رقم", .yours),
    ]

    /// Words that only carry the sentence, between spaces: dropped from the person's words and from games' names alike,
    /// so "let's play a game of tic-tac-toe on hard" and "jouons au morpion" come down to the game's name.
    static let fillers: Set<String> = [
        // English
        "let's", "lets", "let", "us", "play", "playing", "start", "open", "launch", "begin", "a", "an", "the", "game", "round", "match", "of",
        "some", "i", "want", "to", "wanna", "would", "like", "we", "can", "could", "shall", "with", "you", "against", "on", "at", "in", "level",
        "mode", "difficulty", "and", "today's", "todays", "daily", "today", "day", "new", "quick", "for", "me", "do", "go", "have", "now",
        "questions", "question", "game's",
        // French
        "jouons", "jouer", "joue", "on", "à", "au", "aux", "un", "une", "le", "la", "les", "de", "du", "des", "partie", "jeu", "je", "veux",
        "faire", "faisons", "avec", "toi", "contre", "en", "niveau", "difficulté", "et", "jour", "aujourd'hui", "nouvelle", "nouveau",
        // Spanish
        "juguemos", "jugar", "juega", "vamos", "el", "los", "las", "una", "partida", "juego", "quiero", "contigo", "tú", "modo", "nivel",
        "dificultad", "y", "día", "hoy", "nueva", "nuevo", "del",
        // German
        "lass", "uns", "spielen", "spiel", "spiele", "eine", "ein", "einen", "das", "die", "der", "den", "ich", "will", "möchte", "mit", "dir",
        "gegen", "auf", "im", "stufe", "modus", "schwierigkeit", "und", "tages", "heute", "heutige", "heutiges", "neues", "neue", "runde",
        // Italian
        "giochiamo", "giocare", "gioca", "uno", "il", "lo", "gli", "partita", "gioco", "voglio", "con", "te", "contro", "livello", "modalità",
        "difficoltà", "giorno", "oggi", "nuova", "nuovo", "di", "del", "della", "a",
        // Portuguese
        "vamos", "jogar", "joga", "jogo", "um", "uma", "o", "os", "as", "quero", "com", "você", "contra", "no", "na", "em", "nível",
        "dificuldade", "e", "dia", "hoje", "novo", "nova", "do", "da",
        // Arabic
        "لنلعب", "العب", "نلعب", "هيا", "لعبة", "أريد", "أن", "ألعب", "على", "مستوى", "بمستوى", "مع", "في", "وضع", "اليوم", "و",
        // Korean (spaced words)
        "하자", "할래", "게임", "같이", "오늘의", "모드", "난이도", "하고", "싶어", "해줘", "해", "줘", "놀자", "한", "판",
    ]

    /// Words that carry the sentence inside unspaced Japanese and Chinese, and Korean particles at a word's end; taken
    /// out wherever they are, longest first.
    static let joined: [String] = [
        "をしよう", "でしよう", "しよう", "しよ", "をやろう", "でやろう", "やろう", "で遊ぼう", "遊ぼう", "あそぼう", "がしたい", "したい", "やりたい",
        "一緒に", "今日の", "ゲーム", "モード", "レベル", "を", "で", "の",
        "我想玩", "我们", "来玩", "一起", "一局", "一下", "游戏", "今天的", "每日", "模式", "难度", "玩", "吧", "的", "个", "来",
    ]

    /// Words that say a game is meant: a bare name ("copy", "memory") may be another extension's command (D50), so
    /// a name without a slot needs one of these ("play memory pairs", "daily sudoku"); between spaces, or anywhere in
    /// unspaced Japanese and Chinese.
    static let playWords: Set<String> = [
        "play", "let's", "lets", "start", "launch", "daily", "today's", "todays",
        "jouons", "jouer", "joue", "jour", "juguemos", "jugar", "juega", "día", "spielen", "spiel", "spiele", "lass", "tages", "heutige",
        "giochiamo", "giocare", "gioca", "giorno", "jogar", "joga", "vamos", "dia", "لنلعب", "العب", "نلعب", "اليوم", "하자", "놀자", "오늘의",
    ]
    static let playJoined = ["しよう", "やろう", "遊ぼう", "あそぼう", "今日の", "来玩", "我想玩", "玩", "每日", "今天的"]

    /// Korean particles left on a word ("틱택토를" is 틱택토).
    static let particles = ["으로", "를", "을", "로"]
}
