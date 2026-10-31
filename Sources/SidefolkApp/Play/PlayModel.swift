import AppKit
import SidefolkCore
import SwiftUI

/// One game in the Play panel (D75): the board on screen, the moves the person makes on it, its clock, and what the
/// companion is asked to do. Moves go only where the board offered them, one at a time.
@MainActor @Observable
final class PlayModel {
    let info: GameInfo
    let provider: any GameProvider
    /// What the panel shows: during a build-up, the board without its verdict (`GameSuspense`); then the game's own.
    private(set) var board: GameBoard?
    /// The game's latest board, verdict and all, once its moment has come.
    private(set) var latest: GameBoard?
    /// When the reveal on screen began, shared by its build-up and its verdict so it plays once.
    private(set) var revealStart = Date()
    /// The move sent and not yet answered: its tile looks pressed meanwhile.
    private(set) var pending: GameMove?
    /// The game stopped (it didn't answer, or its board was refused): said in the panel, which then only closes.
    private(set) var failure: String?
    var soundsOn: Bool
    /// When the board's timer started, by its id, so the same timer on the next board keeps running.
    private(set) var clock: (id: String, start: Date, seconds: Double)?
    /// Raised each time the board changes, so a reveal plays again.
    private(set) var turn = 0
    /// When the person last did anything, for keeping a closed game ten minutes.
    private(set) var lastActive = Date()
    /// A move was made: the game counts as played, for its Activity row.
    private(set) var played = false
    /// The board said it was over and its row was written.
    private(set) var recorded = false

    let companionName: String
    let portrait: NSImage?
    /// A new board's cue, once its verdict shows.
    var onCue: ((GameBoard) -> Void)?
    /// A reveal began: the companion pumps its fist, flicks the coin or throws the dice meanwhile.
    var onReveal: ((GameBoard.Reveal) -> Void)?
    /// A beat of suspense began (an answer pressed, its verdict not yet shown): a soft tick.
    var onBeat: (() -> Void)?
    /// The answer the person just gave, drawn pressed during the build-up.
    private var lastPick: Int?
    private var staging: Task<Void, Never>?
    /// The board just said the game is over.
    var onOver: ((GameBoard) -> Void)?
    var onClose: (() -> Void)?
    private var timerTask: Task<Void, Never>?
    /// Sidefolk's own timing of the later parts (PlayModel+Parts): what is typed, where the arrow keys point, the pads'
    /// playback, the cups' shuffle, the reflex signal and a board's `after`.
    var parts = PartsState()
    var partsTask: Task<Void, Never>?
    var afterTask: Task<Void, Never>?
    /// A pad lit during the playback: the companion does its move, its note plays.
    var onPadStep: ((GameBoard.Pads.Pad) -> Void)?

    init(info: GameInfo, provider: any GameProvider, companionName: String, portrait: NSImage?, soundsOn: Bool) {
        self.info = info
        self.provider = provider
        self.companionName = companionName
        self.portrait = portrait
        self.soundsOn = soundsOn
    }


    func start(_ setup: GameSetup) async {
        do {
            show(try await provider.start(setup))
        } catch {
            fail(error)
        }
    }

    /// The person's move: sent when this board offered it and nothing is waiting.
    func send(_ move: GameMove) {
        guard failure == nil, pending == nil, let board, move.offered(by: board), ready(for: move) else { return }
        afterTask?.cancel()
        pending = move
        if case .answer(let i) = move { lastPick = i } else { lastPick = nil }
        lastActive = Date()
        if move != .timeout, move != .next { played = true }
        if soundsOn, ![.timeout, .next].contains(move) { GameSounds.shared.play(.tap) }
        Task {
            do {
                // `pending` stays until the verdict shows, so nothing is pressed twice during the build-up.
                show(try await provider.move(move))
            } catch {
                pending = nil
                fail(error)
            }
        }
    }

    /// Shows a board in its order (D75): if it would give a result away, its build-up first (the reveal playing, or
    /// the pick pressed beside the sealed card), then the board itself, its cue, sound and announcement.
    private func show(_ next: GameBoard) {
        staging?.cancel()
        timerTask?.cancel()
        clock = nil
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard let (build, seconds) = GameSuspense.buildUp(from: latest, to: next, picked: lastPick), !(still && next.reveal != nil) else {
            return verdict(next)
        }
        board = build
        turn += 1
        shown(build, verdict: false)
        if let reveal = next.reveal {
            revealStart = Date()
            onReveal?(reveal)
        } else {
            onBeat?()
        }
        staging = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.verdict(next)
        }
    }

    private func verdict(_ next: GameBoard) {
        let wasOver = latest?.over ?? false
        if next.reveal == nil { revealStart = .distantPast }
        latest = next
        board = next
        pending = nil
        lastPick = nil
        turn += 1
        failure = nil
        onCue?(next)
        announce(next)
        if next.over, !wasOver {
            recorded = true
            onOver?(next)
        } else if !next.over {
            recorded = false
        }
        runClock(next.timer)
        shown(next, verdict: true)
    }

    /// VoiceOver hears the verdict when it shows: the hands' sentence, or whether the pick was right.
    private func announce(_ board: GameBoard) {
        var words: String?
        if case .hands(let you, let companion)? = board.reveal { words = Toss.hands(person: you, companion: companion).result }
        if words == nil, let a = board.answers, a.locked {
            if a.tiles.contains(where: { $0.state == .wrong }) { words = String(localized: "wrong", comment: "A game's answer, read by VoiceOver") }
            else if a.tiles.contains(where: { $0.state == .right }) { words = String(localized: "right", comment: "A game's answer, read by VoiceOver") }
        }
        guard let words else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: words, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    /// Sidefolk keeps the time, so a game never runs a clock: when it ends, the game hears `{timeout: true}`.
    private func runClock(_ timer: GameBoard.Timer?) {
        guard let timer else {
            timerTask?.cancel()
            clock = nil
            return
        }
        guard clock?.id != timer.id else { return }
        timerTask?.cancel()
        clock = (timer.id, Date(), timer.seconds)
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timer.seconds))
            guard !Task.isCancelled, let self, self.clock?.id == timer.id else { return }
            self.clock = nil
            self.send(.timeout)
        }
    }

    private func fail(_ error: Error) {
        staging?.cancel()
        timerTask?.cancel()
        partsTask?.cancel()
        afterTask?.cancel()
        clock = nil
        failure = (error as? UserFacingError)?.message ?? String(localized: "The game stopped.", comment: "A game in the Play panel ended by itself")
    }

    #if DEBUG
    /// Keeps the build-up on screen, for the UI snapshots that show it.
    func holdBuildUp() { staging?.cancel() }

    /// Shows `next` as it would come after `previous` (its build-up held when `buildUp`), with the parts' own time
    /// stopped at rest: for the UI snapshots of a game's real boards.
    func stage(after previous: GameBoard?, _ next: GameBoard, buildUp: Bool) {
        latest = previous
        board = previous
        show(next)
        if buildUp { staging?.cancel() } else if staging != nil { staging?.cancel(); verdict(next) }
        partsTask?.cancel()
        afterTask?.cancel()
        parts.playing = false
        parts.shuffling = false
        parts.waiting = false
    }
    #endif

    func stop() {
        staging?.cancel()
        timerTask?.cancel()
        partsTask?.cancel()
        afterTask?.cancel()
        clock = nil
    }

    // MARK: Keys

    /// A key the panel heard: a tile's letter or number, a button's letter, Return or Space for the main button.
    /// True when the board used it.
    /// - Parameter time: when the key went down (the event's timestamp), so a reflex press is timed from the key itself.
    func press(_ key: String, at time: TimeInterval? = nil) -> Bool {
        guard let board, failure == nil else { return false }
        let k = key.lowercased()
        if pressPart(k, at: time) { return true }
        if let answers = board.answers, !answers.locked {
            let letters = Self.keyCaps(answers)
            if let i = letters.firstIndex(where: { $0.lowercased() == k }) ?? Int(k).map({ $0 - 1 }), answers.tiles.indices.contains(i) {
                send(.answer(i))
                return true
            }
        }
        if k == "return" || k == "space", let primary = board.primary {
            send(.button(primary.move))
            return true
        }
        if let button = board.buttons.first(where: { $0.key == k && !$0.disabled }) {
            send(.button(button.move))
            return true
        }
        // A number picks one of the cards of the first choice, when there are no tiles to answer.
        if board.answers.map({ $0.locked }) ?? true, let n = Int(k), let choice = board.parts.lazy.compactMap({ part -> GameBoard.Choice? in
            if case .choice(let c) = part { c } else { nil }
        }).first, choice.options.indices.contains(n - 1) {
            send(.choice(name: choice.name, value: choice.options[n - 1].value))
            return true
        }
        return false
    }

    /// The letter on each tile's key cap: R, P and S for hands, A to D otherwise.
    static func keyCaps(_ answers: GameBoard.Answers) -> [String] {
        answers.tiles.enumerated().map { i, tile in
            if let key = tile.key { return key }
            return switch tile.art {
            case .rock: "R"
            case .paper: "P"
            case .scissors: "S"
            case nil: ["A", "B", "C", "D"][i]
            }
        }
    }

    /// The quiet line of keys under the board, in Sidefolk's words.
    var footer: String {
        var parts: [String] = []
        if let answers = board?.answers, !answers.locked {
            let caps = Self.keyCaps(answers)
            parts.append(answers.tiles.contains(where: { $0.art != nil || $0.key != nil })
                ? String(localized: "\(caps.joined(separator: " ")) to play", comment: "Keys in the Play panel: “R P S to play”")
                : String(localized: "1–\(answers.tiles.count) to answer", comment: "Keys in the Play panel: “1–4 to answer”"))
        }
        if let hint = partsFooter { parts.append(hint) }
        if let primary = board?.primary {
            parts.append(String(localized: "Return: \(primary.label)", comment: "Keys in the Play panel: what Return does, “Return: Next”"))
        }
        for button in board?.buttons ?? [] where button.key != nil && !button.disabled {
            parts.append("\(button.key!.uppercased()): \(button.label)")
        }
        parts.append(String(localized: "Esc to close", comment: "Keys in the Play panel"))
        return parts.joined(separator: " · ")
    }
}
