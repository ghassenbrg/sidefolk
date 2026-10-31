#if DEBUG
import AppKit
import SidefolkCore
import SwiftUI

/// The Play panel in each of its states for the UI snapshots (D75): trivia as Playtime draws it (set-up, a question
/// with the companion's sealed pick, the lifeline, right, wrong, the end card), the companion's best of three, and a
/// game that stopped. The boards are written here as a game would send them; the debug app plays the real ones.
@MainActor
enum SamplePlayBoards {
    /// Answers whatever board it was made with.
    final class Fixed: GameProvider {
        let info: GameInfo
        let board: GameBoard?
        /// What a move answers, for the build-up samples.
        let next: GameBoard?
        init(_ info: GameInfo, _ board: GameBoard?, next: GameBoard? = nil) {
            self.info = info
            self.board = board
            self.next = next
        }
        func start(_ setup: GameSetup) async throws -> GameBoard {
            guard let board else { throw UserFacingError(verbatim: ExtensionHost.noAnswer("Playtime")) }
            return board
        }
        func move(_ move: GameMove) async throws -> GameBoard { next ?? board ?? GameBoard() }
        func end(_ reason: GameEndReason) async {}
    }

    static let trivia = GameInfo(extensionId: "dev.sidefolk.playtime", extensionName: "Playtime", game: "trivia", title: "Trivia",
                                 symbol: "questionmark.bubble.fill", levels: [], iconPath: FixtureServices.addonIcon("playtime"))

    /// Each sample's model as the panel shows it, and the moment of its reveal to draw. The build-up samples prove the
    /// order (D75): what shows while the reveal plays or the answer waits has no verdict in it.
    static func models(portrait: NSImage?) async -> [(String, PlayModel, Double?)] {
        var out: [(String, PlayModel, Double?)] = []
        for (name, info, board) in boards() {
            let model = PlayModel(info: info, provider: Fixed(info, board), companionName: "Mochi", portrait: portrait, soundsOn: name.hasPrefix("trivia-question"))
            await model.start(GameSetup())
            // A board that opens on a reveal plays it first; these samples show it landed.
            if board?.reveal != nil { try? await Task.sleep(for: .seconds(GameSuspense.revealSeconds + 0.2)) }
            out.append((name, model, 1))
        }
        // Mid-move: the throw pumping sealed, the hands just opened, and an answer waiting for its verdict.
        let match = HandsMatch(db: nil, companionName: "Mochi")
        let pick = match.board(HandsMatch.State(round: 2, you: 1, companion: 0, sealed: .scissors), cue: nil)
        let thrown = match.board(HandsMatch.State(round: 2, you: 1, companion: 1, last: (.rock, .paper)), cue: GameCue(move: .giggle, line: .tease))
        for (name, at) in [("rps-buildup-pumping", 0.25), ("rps-buildup-open", 0.55)] {
            let model = PlayModel(info: .handsMatch, provider: Fixed(.handsMatch, pick, next: thrown), companionName: "Mochi", portrait: portrait, soundsOn: false)
            await model.start(GameSetup())
            model.send(.answer(0))
            try? await Task.sleep(for: .milliseconds(150))
            model.holdBuildUp()
            out.append((name, model, at))
        }
        let (_, _, question) = boards().first { $0.0 == "trivia-question" }!
        let (_, _, right) = boards().first { $0.0 == "trivia-right" }!
        let beat = PlayModel(info: trivia, provider: Fixed(trivia, question, next: right), companionName: "Mochi", portrait: portrait, soundsOn: false)
        await beat.start(GameSetup())
        beat.send(.answer(2))
        try? await Task.sleep(for: .milliseconds(150))
        beat.holdBuildUp()
        out.append(("trivia-beat", beat, nil))
        return out
    }

    /// Playtime's real boards (its test `writeSampleBoards` writes them, in the language asked): each as the panel shows
    /// it, and, when it decides something, its build-up too.
    static func real(from dir: URL, portrait: NSImage?) async -> [(String, PlayModel)] {
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var out: [(String, PlayModel)] = []
        for file in files {
            guard let data = try? Data(contentsOf: file), let json = try? JSONDecoder().decode(JSONValue.self, from: data),
                  let raw = json["board"], let board = try? GameBoard.parse(raw) else { continue }
            let previous = json["previous"].flatMap { try? GameBoard.parse($0) }
            let info = GameInfo(extensionId: "dev.sidefolk.playtime", extensionName: "Playtime", game: json["game"]?.stringValue ?? "game",
                                title: json["title"]?.stringValue ?? "Game", symbol: json["symbol"]?.stringValue,
                                iconPath: FixtureServices.addonIcon("playtime"))
            let name = file.deletingPathExtension().lastPathComponent
            var stages = [(name, false)]
            if let previous, GameSuspense.buildUp(from: previous, to: board, picked: nil) != nil { stages.insert((name + "-buildup", true), at: 0) }
            for (shot, held) in stages {
                let model = PlayModel(info: info, provider: Fixed(info, board), companionName: "Mochi", portrait: portrait, soundsOn: false)
                model.stage(after: previous, board, buildUp: held)
                out.append((shot, model))
            }
        }
        return out
    }

    private static func json(_ text: String) -> GameBoard { try! GameBoard.parse(try! JSONValue.parse(text)) }

    static func boards() -> [(String, GameInfo, GameBoard?)] {
        let question = #"{"type": "prompt", "chip": "Space", "eyebrow": "3 of 10", "text": "Which planet is called the Red Planet?"}"#
        let score = #"{"type": "score", "you": 2, "companion": 1, "streak": 2, "companion_picked": true}"#
        let answered = #"{"type": "score", "you": 3, "companion": 1, "streak": 3}"#
        func tiles(_ states: [String], companion: Int? = nil) -> String {
            let labels = ["Venus", "Jupiter", "Mars", "Mercury"]
            let items = labels.enumerated().map { i, l in
                #"{"label": "\#(l)", "state": "\#(states[i])"\#(companion == i ? #", "companion": true"# : "")}"#
            }
            return #"{"type": "answers", "locked": \#(states.contains { $0 != "none" && $0 != "faded" } ? "true" : "false"), "items": [\#(items.joined(separator: ","))]}"#
        }
        let fact = #"{"type": "note", "title": "Did you know?", "text": "Mars is red because of iron oxide, rust, in its dust."}"#
        let next = #"{"type": "button", "label": "Next", "move": "next", "style": "primary", "symbol": "arrow.right"}"#
        let hint = #"{"type": "button", "label": "Ask Mochi", "move": "hint", "style": "plain", "symbol": "lightbulb", "key": "h"}"#
        let topics = ["mix:Mix:shuffle", "science:Science:atom", "space:Space:moon.stars.fill", "geography:Geography:globe.europe.africa.fill",
                      "history:History:building.columns.fill", "nature:Nature:leaf.fill", "food:Food:fork.knife", "arts:Arts:paintpalette.fill",
                      "tech:Tech:cpu", "sports:Sports:figure.run"].map { t -> String in
            let p = t.split(separator: ":")
            return #"{"value": "\#(p[0])", "label": "\#(p[1])", "symbol": "\#(p[2])"}"#
        }
        let setup = """
            {"parts": [{"type": "prompt", "eyebrow": "A quiz with Mochi", "text": "Pick a topic"},
              {"type": "choice", "name": "topic", "style": "cards", "selected": "mix", "options": [\(topics.joined(separator: ","))]},
              {"type": "choice", "name": "length", "label": "Questions", "style": "segmented", "selected": "10",
               "options": [{"value": "5", "label": "5"}, {"value": "10", "label": "10"}, {"value": "endless", "label": "Endless"}]},
              {"type": "choice", "name": "pace", "label": "Pace", "style": "segmented", "selected": "relaxed",
               "options": [{"value": "relaxed", "label": "Relaxed"}, {"value": "quick", "label": "Quick, 15 s"}]},
              {"type": "button", "label": "Start", "move": "start", "style": "primary", "symbol": "play.fill"}],
             "companion": {"move": "ready", "line": "hello"}}
            """
        let quick = """
            {"parts": [\(score), {"type": "prompt", "chip": "Space", "eyebrow": "3 of 10", "text": "Which planet is called the Red Planet?"},
              {"type": "timer", "id": "q3", "seconds": 15}, \(tiles(["none", "none", "none", "none"])), \(hint)]}
            """
        let end = """
            {"parts": [{"type": "score", "you": 7, "companion": 6, "streak": 0},
              {"type": "result", "figure": "7 / 10", "line": "You beat Mochi by one!", "ribbon": "New best!", "tone": "good",
               "facts": [{"label": "Mochi", "value": "6"}, {"label": "Best streak", "value": "4"}, {"label": "Topic", "value": "Mix"}],
               "actions": [{"label": "Play again", "move": "again", "style": "primary", "symbol": "arrow.clockwise"},
                           {"label": "Another topic", "move": "topics", "style": "secondary"}]}],
             "companion": {"move": "sulk", "line": "you_win"}, "over": true}
            """
        let hands = GameInfo.handsMatch
        let match = HandsMatch(db: nil, companionName: "Mochi")
        let revealed = match.board(HandsMatch.State(round: 2, you: 1, companion: 0, last: (.rock, .scissors)), cue: nil)
        let draw = match.board(HandsMatch.State(round: 2, you: 1, companion: 0, last: (.paper, .paper)), cue: nil)
        return [
            ("trivia-setup", trivia, json(setup)),
            ("trivia-question", trivia, json(#"{"parts": [\#(score), \#(question), \#(tiles(["none", "none", "none", "none"])), \#(hint)], "companion": {"move": "think", "look": "panel"}}"#)),
            ("trivia-question-quick", trivia, json(quick)),
            ("trivia-lifeline", trivia, json(#"{"parts": [\#(score), \#(question), \#(tiles(["faded", "none", "none", "faded"]))], "companion": {"move": "sweat", "line": "hint_intro"}}"#)),
            ("trivia-right", trivia, json(#"{"parts": [\#(answered), \#(question), \#(tiles(["faded", "faded", "right", "faded"], companion: 2)), \#(fact), \#(next)], "companion": {"move": "nod", "line": "streak"}}"#)),
            ("trivia-wrong", trivia, json(#"{"parts": [{"type": "score", "you": 2, "companion": 2}, \#(question), \#(tiles(["wrong", "faded", "right", "faded"], companion: 2)), \#(fact), \#(next)]}"#)),
            ("trivia-end", trivia, json(end)),
            ("rps-pick", hands, match.board(HandsMatch.State(sealed: .rock), cue: nil)),
            ("rps-reveal", hands, revealed),
            ("rps-draw", hands, draw),
            ("rps-lost", hands, match.board(HandsMatch.State(round: 2, you: 0, companion: 1, last: (.rock, .paper)), cue: nil)),
            ("rps-match-end", hands, match.board(HandsMatch.State(round: 3, you: 1, companion: 2, last: (.scissors, .rock)), cue: nil)),
            ("stopped", trivia, nil),
        ]
    }
}
#endif
