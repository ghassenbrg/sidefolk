import Foundation
@testable import SidefolkCore
import Testing

/// What people say to open a game, as the gallery's own pack declares it (D101): the sentences the app's tables answered until now, answered by the commands a pack holds.
/// Skipped with no add-ons checkout at hand.
struct GameCommandsInThePackTests {
    static var folder: String? {
        let repo = ProcessInfo.processInfo.environment["SIDEFOLK_ADDONS_REPO"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("sidefolk-addons")
        let folder = repo.appendingPathComponent("extensions/playtime").path
        return FileManager.default.fileExists(atPath: folder + "/" + ExtensionManifest.fileName) ? folder : nil
    }

    static func loaded(_ folder: String) throws -> (manifest: ExtensionManifest, strings: ExtensionStrings?) {
        let data = try Data(contentsOf: URL(fileURLWithPath: folder + "/" + ExtensionManifest.fileName))
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: data)
        var issues: [ValidationIssue] = []
        let strings = ExtensionStrings.load(folder: folder, manifest: manifest, issues: &issues)
        #expect(issues.isEmpty, "\(issues.map(\.description))")
        return (manifest, strings)
    }

    @Test func theSentencesPeopleSay() throws {
        guard let folder = Self.folder else { return }
        let (m, strings) = try Self.loaded(folder)
        let v = CommandVocabulary(manifest: m, strings: strings)
        let open = try #require(m.tools["open"].flatMap { ToolCommands($0.commands, vocabulary: v) })
        func input(_ text: String) -> [String: JSONValue]? {
            guard var out = open.input(for: text)?.objectValue else { return nil }
            out["person"] = nil
            return out
        }
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
            ("word of the day", ["game": "daily_word"]),
            ("sudoku hard", ["game": "sudoku", "level": "hard"]),
            ("tic tac toe", ["game": "tictactoe"]), ("hangman", ["game": "balloon_words"]), ("jouons au morpion", ["game": "tictactoe"]), ("今日のことば", ["game": "daily_word"]),
            ("数独を難しいでしよう", ["game": "sudoku", "level": "hard"]),
            ("rematch", ["game": "again"]), ("Revanche!", ["game": "again"]), ("noch eine runde", ["game": "again"]), ("もう一回やろう", ["game": "again"]),
            ("한판 더", ["game": "again"]), ("再来一局", ["game": "again"]), ("مباراة أخرى", ["game": "again"]),
            ("make it harder", ["game": "again", "level": "harder"]), ("mas dificil", ["game": "again", "level": "harder"]), ("أصعب", ["game": "again", "level": "harder"]),
            ("too hard", ["game": "again", "level": "easier"]), ("resume the game", ["game": "last"]), ("a random game", ["game": "random"]), ("show my stats", ["game": "center"]),
            ("mes scores", ["game": "center"]), ("游戏中心", ["game": "center"]),
        ]
        for (text, expected) in cases { #expect(input(text) == expected, "\(text): \(String(describing: input(text)))") }
        for text in ["copy", "memory", "play some music", "play this on the TV", "start the timer", "hard", "again", "nochmal", "sudoku 10 questions", "tic-tac-toe about space",
                     "guess a number between 1000 and 1", "trivia about " + String(repeating: "a", count: 60), "tell me about trivia", "play tic-tac-toe on hard and easy",
                     "how are my stats at work", "higher or lower on hard", "trivia 500 questions"] {
            #expect(input(text) == nil, "\(text): \(String(describing: input(text)))")
        }
        // Pausing and the sounds are their own tools.
        #expect(m.tools["put_away"].flatMap { ToolCommands($0.commands, vocabulary: v) }?.input(for: "pause the game") != nil)
        let sounds = try #require(m.tools["game_settings"].flatMap { ToolCommands($0.commands, vocabulary: v) })
        #expect(sounds.input(for: "게임 소리 꺼줘")?["sounds"]?.boolValue == false && sounds.input(for: "turn game sounds on")?["sounds"]?.boolValue == true)
    }

    /// Every name a pack gives a game, in every language, opens that game with a word saying it is meant.
    @Test func everyGamesNameInEveryLanguage() throws {
        guard let folder = Self.folder else { return }
        let (m, strings) = try Self.loaded(folder)
        let v = CommandVocabulary(manifest: m, strings: strings)
        let commands = try #require(m.tools["open"]).commands
        let open = try #require(ToolCommands(commands, vocabulary: v))
        let leads = ["en": "play", "fr": "jouons", "es": "juguemos", "de": "spielen", "it": "giochiamo", "pt-BR": "jogar", "ja": "", "ko": "", "zh-Hans": "", "ar": "لنلعب"]
        for command in commands where !command.names.isEmpty {
            let game = command.input?["game"]?.stringValue
            var said = command.names.map { ("en", $0) }
            for (language, table) in strings?.tables ?? [:] { said += (table.commands[command.name ?? ""]?.names ?? []).map { (language, $0) } }
            for (language, name) in said {
                let got = open.input(for: name) ?? open.input(for: "\(leads[language] ?? "") \(name)") ?? open.input(for: "\(name) しよう") ?? open.input(for: "来玩\(name)") ?? open.input(for: "\(name) 하자")
                #expect(got?["game"]?.stringValue == game, "\(language): \(name)")
            }
        }
    }

    @Test func thePackIsValidAndNamesNoGamesKey() throws {
        guard let folder = Self.folder else { return }
        let (m, _) = try Self.loaded(folder)
        #expect(m.games.isEmpty, "no game channel")
        #expect(m.surfaces["play"] != nil && m.assets == "assets")
        #expect(m.settings.filter { !$0.listed }.count > 0 && m.settings.filter(\.listed).map(\.key) == ["tone", "sounds", "sneaky"])
    }
}
