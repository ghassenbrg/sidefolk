import AppKit
import SidefolkCharacter
import SidefolkCore

/// Plays a surface's reactions on the companion (D99): a mood from a fixed list on the rig every companion has, a prop or a short
/// effect drawn above it, a glance. Paced by `CueLimiter`, honoured only while the surface is on screen, and none of it can move the
/// companion's window, open a bubble, take focus or say words.
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

    init(companion: CompanionWindowController, caption: CompanionCaption) {
        self.companion = companion
        self.caption = caption
    }

    /// A surface's reaction: from the fixed lists, with no words and no sound of Sidefolk's.
    func react(_ reaction: SceneReaction) {
        let now = Date()
        if let look = reaction.look { self.look(look) }
        switch reaction.move {
        case .cue(let move)?:
            switch limiter.move(move, at: now) {
            case .now: perform(move, toward: reaction.look)
            case .after(let wait):
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(wait))
                    guard let self, self.limiter.takeWaiting(move, at: Date()) else { return }
                    self.perform(move, toward: reaction.look)
                }
            }
        case .pump?: companion.character.perform(.pump)
        case .flick?: companion.character.perform(.flick)
        case .roll?: companion.character.perform(.roll)
        case nil: break
        }
        if let effect = reaction.effect { caption.flash(effect) }
        if let prop = reaction.prop { caption.hold(prop) }
    }

    /// The companion's moves for each reaction: moments every 2D and 3D companion has, its own sulk, shrug, tease and
    /// ready among them, and the short accents for fast choreography.
    static func moment(_ move: CompanionCue.Move) -> CharacterAntic? {
        switch move {
        case .cheer: .cheer
        case .bow: .bow
        case .nod: .nod
        case .sweat: .scratch
        case .shrug: .shrug
        case .sulk: .sulk
        case .giggle: .giggle
        case .wince: .wince
        case .gasp: .gasp
        case .tease: .tease
        case .dizzy: .dizzy
        case .ready: .ready
        case .shuffle, .dance: .dance
        case .hop: .hop
        case .spin: .spin
        case .wave: .wave
        case .accentWave: .waveQuick
        case .accentHop: .hopQuick
        case .accentSpin: .spinQuick
        case .accentBow: .bowQuick
        case .think, .celebrate: nil
        }
    }

    /// Moves that are states held for a moment rather than one-shot moments.
    static func state(_ move: CompanionCue.Move) -> (CharacterState, TimeInterval)? {
        switch move {
        case .think: (.thinking, 2.4)
        case .celebrate: (.celebrating, 2.2)
        default: nil
        }
    }

    private func perform(_ move: CompanionCue.Move, toward look: SceneReaction.Look?) {
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

    private func look(_ look: SceneReaction.Look) {
        let point: NSPoint?
        switch look {
        case .panel: point = panelFrame().map { NSPoint(x: $0.midX, y: $0.midY) }
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

    /// The surface closed: whatever waits is dropped, the prop put away and the companion back to itself.
    func reset() {
        waiting?.cancel()
        held?.cancel()
        caption.clear()
        companion.character.setGaze(nil)
        restoreMood()
        limiter = CueLimiter()
    }
}
