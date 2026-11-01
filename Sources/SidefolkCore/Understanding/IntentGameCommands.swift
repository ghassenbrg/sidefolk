import Foundation
import Synchronization

/// What a person can tell the companion about games without AI (D93), typed or said, in any of the ten languages.
public enum GameCommand: Sendable, Equatable {
    /// A game by its name, with what was said about it: "play tic-tac-toe on hard", "trivia about space, 10
    /// questions", "guess a number between 1 and 1000".
    case open(extensionId: String, game: String, level: String?, slots: GameSlots)
    /// "rematch", "play again"; with a step, "make it harder" or "too easy".
    case again(GameLevels.Step?)
    /// "resume the game": the game put away, where it was.
    case resume
    /// "a random game", "pick a game for me".
    case random
    /// "show my stats", "my scores": the Game Center in Home.
    case center
    /// "pause the game": the panel puts it away.
    case pause
    /// "turn game sounds off" / "on", for every game.
    case sounds(Bool)
}

/// The app's own game sentences (D93): whole sentences for steering ("rematch", "make it harder", "pause the game",
/// "show my stats", "turn game sounds off"), and a game's name with its slots around it. The slots are Sidefolk's,
/// for every game alike (a level, a quiz's topic and count, a number game's range and who guesses), so a new game
/// gets them by its name and look alone. Conservative like the rest of the parser: once the slots and the words that
/// only carry the sentence are out, what remains must be exactly one game's name, or nothing is claimed.
extension IntentParser {
    func gameCommand(_ command: String) -> ParsedIntent? {
        let key = GameCommandWords.key(command)
        let W = GameCommandWords.self
        let found: GameCommand? = if W.again.contains(key) { .again(nil) } else if W.harder.contains(key) { .again(.harder) }
            else if W.easier.contains(key) { .again(.easier) } else if W.resume.contains(key) { .resume } else if W.random.contains(key) { .random }
            else if W.center.contains(key) { .center } else if W.pause.contains(key) { .pause } else if W.soundsOff.contains(key) { .sounds(false) }
            else if W.soundsOn.contains(key) { .sounds(true) } else { nil }
        if let found { return ParsedIntent(intent: .gameCommand(found), hint: ParsedIntent.hint(found.title)) }
        return openGame(command)
    }

    /// A game's name with its slots, or nil.
    private func openGame(_ command: String) -> ParsedIntent? {
        guard !games.isEmpty else { return nil }
        var text = " " + GameCommandWords.digits(command.lowercased()).replacingOccurrences(of: "’", with: "'") + " "
        let words = Set(text.split { $0.isWhitespace || ",.!?".contains($0) }.map(String.init))
        let played = !words.isDisjoint(with: GameSlotWords.playWords) || GameSlotWords.playJoined.contains { text.contains($0) }
        var slots = GameSlots()
        var level: String?

        // Who guesses, which also names the number game.
        var byMode: GameInfo?
        if let phrase = Self.take(Self.modePattern, from: &text) {
            slots.mode = Self.modeOf[phrase]
            byMode = games.first { $0.look == .numbers }
            guard byMode != nil else { return nil }
        }
        if Self.take(Self.twoPattern, from: &text) != nil { slots.players = 2 }
        if let m = Self.capture(Self.rangePatterns, in: &text), let low = Int(m[0]), let high = Int(m[1]) {
            slots.min = low
            slots.max = high
        } else if let m = Self.capture(Self.upToPatterns, in: &text), let high = Int(m[0]) {
            slots.min = 1
            slots.max = high
        }
        if let m = Self.capture(Self.countPatterns, in: &text), let n = Int(m[0]) { slots.count = n }
        while let word = Self.take(Self.levelPattern, from: &text) {
            guard level == nil else { return nil }
            level = Self.levelOf[word]
        }

        // The name alone, else a quiz's name once its topic is taken out.
        var game = byMode.flatMap { g in residual(text).isEmpty || names(of: g).contains(residual(text)) ? g : nil } ?? named(residual(text))
        if game == nil, byMode == nil, let m = Self.capture(Self.topicPatterns, in: &text) {
            slots.topic = topicWords(m[0])
            game = named(residual(text))
        }
        guard let game, played || level != nil || !slots.isEmpty else { return nil }
        // Slots only where they mean something: a topic and a count for a quiz, a range and who guesses for numbers.
        let quiz = game.look == .quiz, numbers = game.look == .numbers
        if (!quiz && (slots.topic != nil || slots.count != nil)) || (!numbers && (slots.min != nil || slots.mode != nil)) { return nil }
        // Two people need a game two can play: not a puzzle, and not Guess My Animal, where the companion is the one guessing.
        if slots.players != nil, game.look?.solo == true || game.look == .animals { return nil }
        let checked = GameSlots(.object(slots.options))
        guard checked == slots else { return nil }
        let chosen = level.flatMap { GameLevels.match($0, in: game.levels) }
        if level != nil, chosen == nil { return nil }
        let open = GameCommand.open(extensionId: game.extensionId, game: game.game, level: chosen, slots: slots)
        return ParsedIntent(intent: .gameCommand(open), hint: ParsedIntent.hint(open.title(game)))
    }

    /// The one game whose name this is.
    private func named(_ rest: String) -> GameInfo? {
        guard !rest.isEmpty else { return nil }
        let found = games.filter { names(of: $0).contains(rest) }
        return found.count == 1 ? found[0] : nil
    }

    /// A game's names as the parser compares them: its title in the person's language and each of its sentences, with
    /// the carrying words out ("let's play tic-tac-toe" is "tictactoe", "jouons au morpion" "morpion").
    private func names(of game: GameInfo) -> Set<String> {
        let key = names.joined(separator: ",")
        if let known = Self.nameCache.withLock({ $0[game]?[key] }) { return known }
        let found = Set(([game.title] + game.say).map(residual).filter { !$0.isEmpty })
        Self.nameCache.withLock { $0[game, default: [:]][key] = found }
        return found
    }

    /// Each game's names, worked out once per set of companion names (they are carrying words too).
    private static let nameCache = Mutex<[GameInfo: [String: Set<String>]]>([:])

    /// The words left once the carrying ones are out, joined without spaces.
    func residual(_ text: String) -> String {
        var t = GameCommandWords.latinFolded(text.lowercased())
        for mark in [",", ".", "!", "?", "？", "！", "。", "、", "؟", "،", ";", ":", "-", "–", "\"", "“", "”", "«", "»"] {
            t = t.replacingOccurrences(of: mark, with: " ")
        }
        let fillers = Self.fillers.union(names)
        let words = t.split(whereSeparator: \.isWhitespace).map(String.init).compactMap { word -> String? in
            // Elided articles: "l'ultimo", "all'ultimo", "d'animaux".
            var w = word
            if let quote = w.firstIndex(of: "'"), w.distance(from: w.startIndex, to: quote) <= 4, w.index(after: quote) < w.endIndex,
               !fillers.contains(w) {
                w = String(w[w.index(after: quote)...])
            }
            if fillers.contains(w) { return nil }
            for p in GameSlotWords.particles where w.count > p.count + 1 && w.hasSuffix(p) && w.unicodeScalars.first.map(Self.isHangul) == true {
                w = String(w.dropLast(p.count))
                break
            }
            return w
        }
        var joined = words.joined()
        for piece in Self.joinedPieces where joined.contains(piece) { joined = joined.replacingOccurrences(of: piece, with: "") }
        return joined
    }

    private static let fillers = Set(GameSlotWords.fillers.map { GameCommandWords.latinFolded($0) })
    private static let joinedPieces = GameSlotWords.joined.sorted { $0.count > $1.count }

    /// A topic in the person's words, without carrying words at its ends ("space with" is "space").
    private func topicWords(_ raw: String) -> String? {
        var words = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let fillers = GameSlotWords.fillers
        while let w = words.last, fillers.contains(w.lowercased()) { words.removeLast() }
        while let w = words.first, fillers.contains(w.lowercased()) { words.removeFirst() }
        let topic = words.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
        return topic.isEmpty ? nil : topic
    }

    private static func isHangul(_ s: Unicode.Scalar) -> Bool { (0xAC00...0xD7A3).contains(s.value) }

    // The patterns, made once: a parse runs on every key typed in Ask.
    private static let modeOf = Dictionary(GameSlotWords.modes.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
    private static let levelOf = Dictionary(GameSlotWords.levels.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
    private static let modePattern = alternation(GameSlotWords.modes.map(\.0))
    private static let levelPattern = alternation(GameSlotWords.levels.map(\.0))
    private static let twoPattern = alternation(GameSlotWords.twoPlayers)
    private static let rangePatterns = compile(GameSlotWords.range)
    private static let upToPatterns = compile(GameSlotWords.upTo)
    private static let countPatterns = compile(GameSlotWords.count)
    private static let topicPatterns = compile(GameSlotWords.topic.map { $0.replacingOccurrences(of: "(.+)", with: "([^,،、]+)") })

    /// One pattern for many phrases, longest first, each standing alone (between spaces, punctuation or the ends;
    /// anywhere in unspaced Japanese and Chinese).
    private static func alternation(_ phrases: [String]) -> NSRegularExpression {
        let parts = phrases.sorted { $0.count > $1.count }.map { phrase -> String in
            let escaped = NSRegularExpression.escapedPattern(for: phrase)
            let cjk = phrase.unicodeScalars.contains { (0x3040...0x9FFF).contains($0.value) }
            return cjk ? escaped : #"(?<![\p{L}\p{N}'])"# + escaped + #"(?![\p{L}\p{N}])"#
        }
        return try! NSRegularExpression(pattern: "(?:" + parts.joined(separator: "|") + ")", options: [.caseInsensitive])
    }

    private static func compile(_ patterns: [String]) -> [NSRegularExpression] {
        patterns.map { try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])"# + $0, options: [.caseInsensitive]) }
    }

    /// Takes the first phrase the pattern finds out of the text, and says which it was.
    static func take(_ pattern: NSRegularExpression, from text: inout String) -> String? {
        guard let m = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let r = Range(m.range, in: text) else { return nil }
        let found = String(text[r]).lowercased()
        text.replaceSubrange(r, with: " ")
        return found
    }

    /// The groups of the first pattern that matches, taken out of the text.
    static func capture(_ patterns: [NSRegularExpression], in text: inout String) -> [String]? {
        for re in patterns {
            guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let whole = Range(m.range, in: text) else { continue }
            let groups = (1..<m.numberOfRanges).compactMap { i in Range(m.range(at: i), in: text).map { String(text[$0]) } }
            text.replaceSubrange(whole, with: " ")
            return groups.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }
}

extension GameCommand {
    /// What the Ask panel's hint says before Return.
    var title: String {
        switch self {
        case .open: String(localized: "Open a game")
        case .again(nil): String(localized: "Play again", comment: "Opening the last game again")
        case .again(.harder): String(localized: "Play again, harder", comment: "The last game again one level harder")
        case .again(.easier): String(localized: "Play again, easier", comment: "The last game again one level easier")
        case .resume: String(localized: "Back to the game", comment: "The game put away, where it was")
        case .random: String(localized: "Play a random game", comment: "The companion picks a game to open")
        case .center: String(localized: "Show the Game Center", comment: "Opening Playtime's page in Home, the Game Center")
        case .pause: String(localized: "Put the game away", comment: "The Play panel hides its game, to resume later")
        case .sounds(let on): on ? String(localized: "Game sounds on", comment: "games.settings: sounds turned on for every game")
            : String(localized: "Game sounds off", comment: "games.settings: sounds turned off for every game")
        }
    }

    /// The hint for a game with what was said about it: "Play Trivia · Hard · about space · 10 questions".
    func title(_ game: GameInfo) -> String {
        guard case .open(_, _, let level, let slots) = self else { return title }
        var parts = [String(localized: "Play \(game.title)", comment: "Opening a game in the Play panel: “Play Trivia”")]
        if let level { parts.append(GameLevels.name(level)) }
        if let topic = slots.topic { parts.append(String(localized: "about \(topic)", comment: "A quiz's topic in the hint: “about space”")) }
        if let count = slots.count { parts.append(String(localized: "\(count) questions", comment: "A quiz's length in the hint")) }
        if let min = slots.min, let max = slots.max { parts.append(String(localized: "\(min)–\(max)", comment: "A number game's range in the hint")) }
        if let mode = slots.mode {
            parts.append(mode == .mine ? String(localized: "you guess", comment: "Higher or Lower: the person guesses the companion's number")
                : String(localized: "it guesses", comment: "Higher or Lower: the companion guesses the person's number"))
        }
        return parts.joined(separator: " · ")
    }

    /// `games.open`'s input for it, or `games.settings`' for sounds; nil for what isn't a tool (pause).
    var input: (tool: String, input: JSONValue)? {
        switch self {
        case .open(let ext, let game, let level, let slots):
            var input = slots.options
            input["extension"] = .string(ext)
            input["game"] = .string(game)
            if let level { input["level"] = .string(level) }
            return ("games.open", .object(input))
        case .again(let step):
            var input: [String: JSONValue] = ["game": "again"]
            if let step { input["level"] = .string(step.rawValue) }
            return ("games.open", .object(input))
        case .resume: return ("games.open", ["game": "last"])
        case .random: return ("games.open", ["game": "random"])
        case .center: return ("games.open", ["game": "center"])
        case .sounds(let on): return ("games.settings", ["sounds": .bool(on)])
        case .pause: return nil
        }
    }
}
