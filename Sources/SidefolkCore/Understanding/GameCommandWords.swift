import Foundation

/// The whole sentences that steer games without AI (D93), in the ten languages Sidefolk speaks, as D79's menu
/// sentences are: an exception to D76's English commands, because a game is played in the person's own words. Each is
/// compared as `GameCommandWords.key` makes it (lowercased, Latin letters without accents, no spaces), so "Revanche",
/// "revanche!" and "한판 더" / "한 판 더" are one. Only phrases that can mean nothing but a game: a bare "again",
/// "nochmal" or "otra vez" could be about anything, so they go to the AI.
enum GameCommandWords {
    static let again: Set<String> = keys([
        // English
        "rematch", "a rematch", "i want a rematch", "give me a rematch", "play again", "let's play again", "play that again", "play it again",
        "one more game", "one more round", "another round", "another game", "same game again", "let's go again", "run it back",
        // French
        "revanche", "la revanche", "je veux ma revanche", "on rejoue", "rejouons", "rejouer", "encore une partie", "une autre partie",
        "une partie de plus",
        // Spanish
        "revancha", "la revancha", "quiero la revancha", "otra partida", "otra ronda", "juguemos otra vez", "jugar otra vez", "jugar de nuevo",
        "juguemos de nuevo",
        // German
        "revanche", "ich will revanche", "noch eine runde", "noch ein spiel", "noch mal spielen", "nochmal spielen", "lass uns nochmal spielen",
        "noch eine partie",
        // Italian
        "rivincita", "la rivincita", "voglio la rivincita", "un'altra partita", "un altro round", "giochiamo ancora", "giochiamo di nuovo",
        "ancora una partita", "rigiochiamo",
        // Portuguese (Brazil)
        "quero revanche", "quero a revanche", "outra partida", "mais uma partida", "mais uma rodada", "jogar de novo", "vamos jogar de novo",
        "outra rodada",
        // Japanese
        "もう一回やろう", "もう一回しよう", "もう1回やろう", "もう一戦", "リベンジ", "再戦", "リマッチ",
        // Korean
        "한 판 더", "한 판 더 하자", "다시 하자", "재경기", "다시 한 판", "리매치", "한 게임 더",
        // Chinese (Simplified)
        "再来一局", "再来一盘", "再玩一次", "再玩一局", "再来一把", "重赛", "复仇赛",
        // Arabic
        "مباراة أخرى", "جولة أخرى", "لنلعب مرة أخرى", "العب مرة أخرى", "مباراة ثأرية", "أريد الثأر", "لعبة أخرى",
    ])

    static let harder: Set<String> = keys([
        "make it harder", "harder", "a harder one", "harder level", "too easy", "this is too easy", "that was too easy", "level up",
        "make it more difficult", "more difficult", "make the game harder", "make this harder", "turn up the difficulty", "go harder",
        "plus difficile", "plus dur", "rends-le plus difficile", "rends le plus difficile", "c'est trop facile", "trop facile",
        "augmente la difficulté",
        "más difícil", "hazlo más difícil", "demasiado fácil", "es demasiado fácil", "sube la dificultad",
        "schwerer", "schwieriger", "mach es schwerer", "mach es schwieriger", "mach's schwerer", "zu leicht", "das ist zu leicht", "zu einfach",
        "erhöhe die schwierigkeit",
        "più difficile", "rendilo più difficile", "troppo facile", "è troppo facile", "aumenta la difficoltà",
        "mais difícil", "deixa mais difícil", "deixe mais difícil", "fácil demais", "está fácil demais", "aumenta a dificuldade",
        "aumente a dificuldade",
        "もっと難しく", "もっとむずかしく", "難しくして", "むずかしくして", "もっと難しくして", "簡単すぎる", "かんたんすぎる", "難易度を上げて",
        "더 어렵게", "더 어렵게 해줘", "너무 쉬워", "난이도 올려줘", "어렵게 해줘",
        "难一点", "再难一点", "更难", "更难一点", "太简单了", "太简单", "提高难度", "加大难度",
        "أصعب", "اجعلها أصعب", "اجعل اللعبة أصعب", "سهلة جدا", "سهلة جدًا", "إنها سهلة جدا", "زد الصعوبة", "ارفع الصعوبة",
    ])

    static let easier: Set<String> = keys([
        "make it easier", "easier", "an easier one", "easier level", "too hard", "this is too hard", "that was too hard", "too difficult",
        "make it less difficult", "less difficult", "make the game easier", "make this easier", "turn down the difficulty", "go easy on me",
        "plus facile", "rends-le plus facile", "rends le plus facile", "c'est trop difficile", "trop difficile", "c'est trop dur", "trop dur",
        "baisse la difficulté",
        "más fácil", "hazlo más fácil", "demasiado difícil", "es demasiado difícil", "baja la dificultad",
        "leichter", "einfacher", "mach es leichter", "mach es einfacher", "mach's leichter", "zu schwer", "das ist zu schwer", "zu schwierig",
        "verringere die schwierigkeit",
        "più facile", "rendilo più facile", "troppo difficile", "è troppo difficile", "abbassa la difficoltà",
        "mais fácil", "deixa mais fácil", "deixe mais fácil", "difícil demais", "está difícil demais", "diminui a dificuldade",
        "diminua a dificuldade",
        "もっと簡単に", "もっとかんたんに", "簡単にして", "かんたんにして", "やさしくして", "もっとやさしく", "難しすぎる", "むずかしすぎる",
        "難易度を下げて",
        "더 쉽게", "더 쉽게 해줘", "너무 어려워", "난이도 내려줘", "난이도 낮춰줘", "쉽게 해줘",
        "简单一点", "容易一点", "更简单", "太难了", "太难", "降低难度",
        "أسهل", "اجعلها أسهل", "اجعل اللعبة أسهل", "صعبة جدا", "صعبة جدًا", "إنها صعبة جدا", "قلل الصعوبة",
    ])

    static let resume: Set<String> = keys([
        "resume the game", "resume my game", "continue the game", "continue my game", "back to the game", "back to my game",
        "unpause the game", "keep playing", "let's keep playing", "continue playing",
        "reprends le jeu", "reprendre le jeu", "reprendre la partie", "reprends la partie", "continue la partie", "continuer la partie",
        "retour au jeu",
        "reanuda el juego", "reanudar el juego", "reanuda la partida", "continúa la partida", "continuar la partida", "seguir jugando",
        "sigamos jugando", "volver al juego",
        "spiel fortsetzen", "setz das spiel fort", "weiterspielen", "lass uns weiterspielen", "zurück zum spiel", "das spiel fortsetzen",
        "riprendi il gioco", "riprendi la partita", "riprendere la partita", "continua la partita", "continuiamo a giocare", "torna al gioco",
        "retomar o jogo", "retome o jogo", "continuar o jogo", "continue o jogo", "continuar a partida", "voltar ao jogo",
        "vamos continuar jogando",
        "ゲームを再開", "ゲームを再開して", "続きをやろう", "続きをしよう", "ゲームに戻る", "ゲームに戻って",
        "게임 다시 시작", "게임 재개", "게임 계속하기", "계속하자", "게임으로 돌아가", "이어서 하자",
        "继续游戏", "恢复游戏", "继续玩", "回到游戏",
        "استأنف اللعبة", "استئناف اللعبة", "تابع اللعبة", "أكمل اللعبة", "العودة إلى اللعبة", "لنكمل اللعب",
    ])

    static let random: Set<String> = keys([
        "a random game", "random game", "play a random game", "let's play a random game", "pick a random game", "pick a game",
        "pick a game for me", "you pick a game", "you choose a game", "choose a game for me", "surprise me with a game", "any game",
        "play any game",
        "un jeu au hasard", "jeu au hasard", "jeu aléatoire", "un jeu aléatoire", "choisis un jeu", "choisis un jeu pour moi",
        "choisis-moi un jeu", "n'importe quel jeu",
        "un juego al azar", "juego al azar", "juego aleatorio", "un juego aleatorio", "elige un juego", "elige tú un juego", "elígeme un juego",
        "cualquier juego", "escoge un juego",
        "ein zufälliges spiel", "zufälliges spiel", "zufallsspiel", "such ein spiel aus", "such du ein spiel aus", "such mir ein spiel aus",
        "irgendein spiel", "wähl ein spiel",
        "un gioco a caso", "gioco a caso", "gioco casuale", "un gioco casuale", "scegli un gioco", "scegli tu un gioco",
        "scegli un gioco per me", "un gioco qualsiasi", "qualsiasi gioco",
        "um jogo aleatório", "jogo aleatório", "escolha um jogo", "escolhe um jogo", "escolha um jogo pra mim", "escolha um jogo para mim",
        "qualquer jogo",
        "ランダムなゲーム", "ランダムでゲーム", "ゲームを選んで", "何かゲームを選んで", "おまかせでゲーム", "適当なゲーム", "ランダムで遊ぼう",
        "랜덤 게임", "아무 게임", "아무 게임이나", "게임 골라줘", "게임 하나 골라줘", "랜덤으로 게임하자",
        "随机游戏", "随机玩一个", "随便玩一个", "随便一个游戏", "你选一个游戏", "帮我选个游戏", "帮我选一个游戏",
        "لعبة عشوائية", "العب لعبة عشوائية", "اختر لعبة", "اختر لي لعبة", "أي لعبة", "اختر أنت لعبة",
    ])

    static let center: Set<String> = keys([
        "show my stats", "my stats", "my game stats", "game stats", "show my game stats", "my scores", "show my scores", "my high scores",
        "my best scores", "my game records", "show my game records", "game center", "the game center", "open the game center",
        "show the game center", "how am i doing in games", "my achievements", "my badges", "show my badges",
        "mes scores", "montre mes scores", "montre-moi mes scores", "mes statistiques", "mes stats", "mes records", "mes badges",
        "centre de jeux", "le centre de jeux", "ouvre le centre de jeux",
        "mis puntuaciones", "muéstrame mis puntuaciones", "mis estadísticas", "mis récords", "mis insignias", "mis marcadores",
        "centro de juegos", "el centro de juegos", "abre el centro de juegos",
        "meine punkte", "zeig meine punkte", "zeig mir meine punkte", "meine statistik", "meine statistiken", "meine spielstatistik",
        "meine rekorde", "meine abzeichen", "meine punktestände", "spielecenter", "das spielecenter", "öffne das spielecenter",
        "i miei punteggi", "mostrami i miei punteggi", "le mie statistiche", "i miei record", "i miei badge", "centro giochi",
        "il centro giochi", "apri il centro giochi",
        "minhas pontuações", "mostre minhas pontuações", "me mostra minhas pontuações", "minhas estatísticas", "meus recordes",
        "minhas conquistas", "central de jogos", "a central de jogos", "abre a central de jogos", "abra a central de jogos",
        "スコアを見せて", "私のスコア", "成績を見せて", "ゲームの成績", "ゲームの記録", "ゲームセンター", "ゲームセンターを開いて", "バッジを見せて",
        "내 점수", "내 점수 보여줘", "점수 보여줘", "내 기록", "게임 기록", "게임 센터", "게임 센터 열어줘", "내 배지",
        "我的分数", "看看我的分数", "我的成绩", "我的战绩", "游戏记录", "游戏中心", "打开游戏中心", "我的徽章",
        "نتائجي", "أرني نتائجي", "إحصائياتي", "أرقامي القياسية", "شاراتي", "مركز الألعاب", "افتح مركز الألعاب",
    ])

    static let pause: Set<String> = keys([
        "pause the game", "pause game", "pause my game", "pause this game", "hide the game", "put the game away", "game pause",
        "pause the match",
        "mets le jeu en pause", "mettre le jeu en pause", "pause le jeu", "jeu en pause", "mets la partie en pause", "cache le jeu",
        "pausa el juego", "pausar el juego", "pon el juego en pausa", "juego en pausa", "pausa la partida", "esconde el juego",
        "spiel pausieren", "pausiere das spiel", "das spiel pausieren", "spiel anhalten", "halte das spiel an", "versteck das spiel",
        "metti in pausa il gioco", "metti il gioco in pausa", "pausa il gioco", "gioco in pausa", "metti in pausa la partita",
        "nascondi il gioco",
        "pausar o jogo", "pause o jogo", "pausa o jogo", "jogo em pausa", "pausar a partida", "esconder o jogo", "esconda o jogo",
        "ゲームを一時停止", "ゲームを一時停止して", "ゲームを止めて", "ゲームをしまって", "ゲームを隠して",
        "게임 일시정지", "게임 멈춰", "게임 멈춰줘", "게임 잠깐 멈춰", "게임 숨겨줘",
        "暂停游戏", "游戏暂停", "把游戏暂停", "暂停一下游戏", "隐藏游戏",
        "أوقف اللعبة مؤقتا", "أوقف اللعبة مؤقتًا", "إيقاف اللعبة مؤقتا", "إيقاف مؤقت للعبة", "أخف اللعبة",
    ])

    static let soundsOff: Set<String> = keys([
        "turn game sounds off", "turn off game sounds", "game sounds off", "mute the game", "mute game sounds", "mute the games",
        "no game sounds", "silence the game", "turn the game sounds off", "turn off the game sounds", "mute games",
        "coupe le son du jeu", "coupe les sons du jeu", "désactive les sons du jeu", "sons du jeu désactivés", "coupe le son des jeux",
        "désactive les sons des jeux",
        "silencia el juego", "apaga los sonidos del juego", "desactiva los sonidos del juego", "quita el sonido del juego",
        "sonidos del juego desactivados", "apaga los sonidos de los juegos",
        "spielgeräusche aus", "spielsounds aus", "schalte die spielgeräusche aus", "spiel stumm", "spiel stummschalten",
        "schalte den spielton aus", "spielton aus",
        "disattiva i suoni del gioco", "togli l'audio del gioco", "silenzia il gioco", "suoni del gioco disattivati",
        "disattiva i suoni dei giochi",
        "desligar os sons do jogo", "desliga os sons do jogo", "desligue os sons do jogo", "silenciar o jogo", "silencie o jogo",
        "sons do jogo desligados",
        "ゲームの音を消して", "ゲーム音オフ", "ゲームの音をオフ", "ゲームの音をオフにして", "ゲームをミュート",
        "게임 소리 꺼줘", "게임 소리 끄기", "게임 소리 꺼", "게임 음소거",
        "关闭游戏声音", "关掉游戏声音", "游戏静音", "关闭游戏音效", "把游戏声音关掉",
        "أوقف أصوات اللعبة", "اكتم صوت اللعبة", "أطفئ أصوات اللعبة", "كتم أصوات الألعاب",
    ])

    static let soundsOn: Set<String> = keys([
        "turn game sounds on", "turn on game sounds", "game sounds on", "unmute the game", "unmute game sounds", "unmute the games",
        "turn the game sounds on", "turn on the game sounds",
        "remets le son du jeu", "active les sons du jeu", "sons du jeu activés", "active le son des jeux", "rallume le son du jeu",
        "activa los sonidos del juego", "enciende los sonidos del juego", "pon el sonido del juego", "sonidos del juego activados",
        "spielgeräusche an", "spielsounds an", "schalte die spielgeräusche ein", "schalte die spielgeräusche an", "spielton an",
        "spielton einschalten",
        "attiva i suoni del gioco", "riattiva l'audio del gioco", "suoni del gioco attivati", "attiva i suoni dei giochi",
        "ligar os sons do jogo", "liga os sons do jogo", "ligue os sons do jogo", "ativar os sons do jogo", "sons do jogo ligados",
        "ゲームの音をつけて", "ゲーム音オン", "ゲームの音をオン", "ゲームの音をオンにして", "ゲームのミュートを解除",
        "게임 소리 켜줘", "게임 소리 켜기", "게임 소리 켜", "게임 음소거 해제",
        "打开游戏声音", "开启游戏声音", "打开游戏音效", "取消游戏静音",
        "شغل أصوات اللعبة", "شغّل أصوات اللعبة", "ألغ كتم صوت اللعبة", "فعّل أصوات اللعبة",
    ])

    /// How a sentence is compared (`CommandText`, since D100 the same for extensions' commands).
    static func key(_ text: String) -> String { CommandText.key(text) }

    static func keys(_ sentences: [String]) -> Set<String> { Set(sentences.map(key)) }

    static func latinFolded(_ text: String) -> String { CommandText.latinFolded(text) }

    static func digits(_ text: String) -> String { CommandText.digits(text) }
}
