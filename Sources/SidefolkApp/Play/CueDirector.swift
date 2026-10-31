import AppKit
import SidefolkCharacter
import SidefolkCore

/// Plays a game's companion cues (D75): a mood from a fixed list on the rig every companion has, a line of Sidefolk's
/// own in the person's language and tone, a prop or a short effect drawn above it, a sound, a glance. Paced by
/// `CueLimiter`, honoured only while the Play panel shows the game, and none of it can move the companion's window,
/// open a bubble, take focus or say a game's own words.
@MainActor
final class CueDirector {
    private let companion: CompanionWindowController
    private let caption: CompanionCaption
    private var limiter = CueLimiter()
    private var waiting: Task<Void, Never>?
    private var held: Task<Void, Never>?
    /// Where the panel is, for the companion to look at.
    var panelFrame: () -> NSRect? = { nil }
    /// Puts the companion back in the state its mood says once a held one (thinking, celebrating) is over.
    var restoreMood: () -> Void = {}
    /// Whether a sound may play now: not in Quiet mode, nor over a fullscreen app.
    var soundsAllowed: () -> Bool = { true }
    /// Says a line aloud, when the person hears spoken replies.
    var speak: ((String) -> Void)?

    init(companion: CompanionWindowController, caption: CompanionCaption) {
        self.companion = companion
        self.caption = caption
    }

    /// A board's cue (and Sidefolk's own words for its own games), played when its verdict shows (`PlayModel`).
    func play(_ board: GameBoard, tone: GameTone, sounds: Bool) {
        waiting?.cancel()
        guard board.cue != nil || board.said != nil else { return }
        act(board.cue ?? GameCue(), said: board.said, tone: tone, sounds: sounds)
    }

    /// A reveal is Sidefolk's own choreography: the companion pumps its fist, flicks the coin or throws the dice while
    /// it plays, as on the desktop (D44); nothing about the outcome, which waits for the verdict.
    func reveal(_ reveal: GameBoard.Reveal, sounds: Bool) {
        switch reveal {
        case .hands: companion.character.perform(.pump)
        case .coin: companion.character.perform(.flick)
        case .dice: companion.character.perform(.roll)
        }
        if sounds, soundsAllowed() { GameSounds.shared.play(Self.revealSound(reveal)) }
    }

    /// A pad lit in Copy Me's playback: the companion does that pad's move with it. Sidefolk's own choreography of
    /// the sequence the game sent (at most 64 steps, each at least 0.25 s), like a reveal, so not paced as cues are.
    func padStep(_ pad: GameBoard.Pads.Pad) {
        guard let move = pad.move, let antic = Self.moment(move) else { return }
        companion.character.perform(antic, toward: panelFrame().map { NSPoint(x: $0.midX, y: $0.midY) })
    }

    /// The beat between an answer and its verdict: the companion's "…" and a soft tick.
    func beat(sounds: Bool) {
        caption.flash(.question)
        if sounds, soundsAllowed(), limiter.sound(at: Date()) { GameSounds.shared.play(.tick) }
    }

    private func act(_ cue: GameCue, said: String?, tone: GameTone, sounds: Bool) {
        let now = Date()
        if let look = cue.look { self.look(look) }
        if let move = cue.move {
            switch limiter.move(move, at: now) {
            case .now: perform(move, toward: cue.look)
            case .after(let wait):
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(wait))
                    guard let self, self.limiter.takeWaiting(move, at: Date()) else { return }
                    self.perform(move, toward: cue.look)
                }
            }
        }
        if let effect = cue.effect { caption.flash(effect) }
        if let prop = cue.prop { caption.hold(prop) }
        if let line = said ?? cue.line.map({ GameLines.line($0, tone: tone) }), limiter.line(at: now) {
            caption.show(line, for: 2.6)
            speak?(line)
        }
        if let sound = cue.sound, sounds, soundsAllowed(), limiter.sound(at: now) { GameSounds.shared.play(sound) }
    }

    static func revealSound(_ reveal: GameBoard.Reveal) -> GameSound {
        switch reveal {
        case .hands: .whoosh
        case .coin: .flip
        case .dice: .rattle
        }
    }

    /// The companion's moves for each cue: its own moments and states, which every 2D and 3D companion has. Moves
    /// still to be made for every companion (sulk, shrug, tease, ready) borrow the nearest one meanwhile.
    static func moment(_ move: GameCue.Move) -> CharacterAntic? {
        switch move {
        case .cheer: .cheer
        case .bow, .accentBow: .bow
        case .nod: .nod
        case .shrug, .sweat: .scratch
        case .giggle: .giggle
        case .wince, .gasp: .startle
        case .tease: .wiggle
        case .dizzy: .dizzy
        case .ready: .peek
        case .shuffle, .dance: .dance
        case .hop, .accentHop: .hop
        case .spin, .accentSpin: .spin
        case .wave, .accentWave: .wave
        case .think, .celebrate, .sulk: nil
        }
    }

    /// Moves that are states held for a moment rather than one-shot moments.
    static func state(_ move: GameCue.Move) -> (CharacterState, TimeInterval)? {
        switch move {
        case .think: (.thinking, 2.4)
        case .celebrate: (.celebrating, 2.2)
        case .sulk: (.error, 1.6)
        default: nil
        }
    }

    private func perform(_ move: GameCue.Move, toward look: GameCue.Look?) {
        if move == .sweat { caption.flash(.sweat) }
        if let (state, seconds) = Self.state(move) {
            held?.cancel()
            companion.character.state = state
            held = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.restoreMood()
            }
            return
        }
        guard let antic = Self.moment(move) else { return }
        let target: NSPoint? = look == .panel || look == nil ? panelFrame().map { NSPoint(x: $0.midX, y: $0.midY) } : nil
        companion.character.perform(antic, toward: target)
    }

    private func look(_ look: GameCue.Look) {
        let point: NSPoint?
        switch look {
        case .panel, .cell: point = panelFrame().map { NSPoint(x: $0.midX, y: $0.midY) }
        case .you: point = NSEvent.mouseLocation
        case .away: point = nil
        }
        guard let point else {
            companion.character.setGaze(nil)
            return
        }
        let frame = companion.characterFrameOnScreen
        companion.character.setGaze(CGVector(dx: (point.x - frame.midX) / 260, dy: (point.y - frame.midY) / 260))
    }

    /// The game closed: whatever waits is dropped, the prop put away and the companion back to itself.
    func reset() {
        waiting?.cancel()
        held?.cancel()
        caption.clear()
        companion.character.setGaze(nil)
        restoreMood()
        limiter = CueLimiter()
    }
}
