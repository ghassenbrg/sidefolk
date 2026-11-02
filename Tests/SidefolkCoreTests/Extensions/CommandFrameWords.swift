import Foundation

/// Words a pack would hold under `carry`, `choices` and `parts`, in the ten languages (D100): enough to prove the frame on, kept here so
/// the mechanism in Sources holds none of them.
enum CommandFrameWords {
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
    /// Two people on this Mac (D96): "with my friend", "two players"; the game must be one two can play.
    static let twoPlayers = [
        "with my friend", "with a friend", "with my friends", "with friends", "with a friend of mine", "two players", "2 players", "two player",
        "2 player", "two-player", "2-player", "for two", "against my friend", "against a friend",
        "avec mon ami", "avec mon amie", "avec un ami", "avec une amie", "avec mes amis", "contre mon ami", "contre mon amie", "à deux",
        "deux joueurs", "2 joueurs",
        "con mi amigo", "con mi amiga", "con un amigo", "con una amiga", "con mis amigos", "contra mi amigo", "dos jugadores", "2 jugadores",
        "mit meinem freund", "mit meiner freundin", "mit einem freund", "mit einer freundin", "mit freunden", "gegen meinen freund", "zu zweit",
        "zwei spieler", "2 spieler",
        "con il mio amico", "con la mia amica", "con un amico", "con un'amica", "con i miei amici", "contro il mio amico", "in due",
        "due giocatori", "2 giocatori",
        "com meu amigo", "com minha amiga", "com o meu amigo", "com a minha amiga", "com um amigo", "com uma amiga", "contra meu amigo",
        "a dois", "dois jogadores", "2 jogadores",
        "友だちと", "友達と", "ともだちと", "ふたりで", "二人で", "2人で", "二人用", "2人用",
        "친구랑", "친구와", "친구하고", "둘이서", "둘이", "2인용", "두 명이서", "2명이서",
        "和朋友", "跟朋友", "和我朋友", "跟我朋友", "双人", "两个人", "两人", "2人",
        "مع صديقي", "مع صديق", "مع صديقتي", "ضد صديقي", "لاعبان", "لاعبين", "لشخصين",
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
