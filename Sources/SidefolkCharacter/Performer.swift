import QuartzCore

/// What `CharacterView` needs from whoever draws the companion: the vector `Director` (D2) or the
/// `SpriteDirector` (D27). Both draw into the same 200×200 canvas (y up, feet on y = 20), so the
/// view's scaling, hit testing and the app's layout stay the same whichever companion is shown.
@MainActor
protocol Performer: AnyObject {
    /// Root of the canvas. The host scales and centers it.
    var stage: CALayer { get }
    var state: CharacterState { get }
    /// Whether the blink scheduler should run in the current state.
    var blinks: Bool { get }
    var reducedMotion: Bool { get set }
    /// Pixels per canvas unit on screen.
    var contentsScale: CGFloat { get set }
    /// The outline that catches clicks, in canvas units.
    var silhouette: CGPath { get }
    /// The body at rest, in canvas units: what bubbles and panels attach to.
    var restingFrame: CGRect { get }

    func show(_ state: CharacterState, animated: Bool)
    func play(_ gesture: CharacterGesture)
    func blink(twice: Bool)
    /// Something happened nearby: move again for a while, then settle (D20).
    func wake()
    func setGaze(_ gaze: CGVector?)
    func setBadges(_ badges: Set<CharacterBadge>, animated: Bool)
    /// Hidden or covered: no loops and no timers until visible again.
    func setPaused(_ hidden: Bool)
}

extension CharacterLook {
    /// A performer for this look. `live` false: still frames only, for offscreen renders.
    @MainActor
    func performer(live: Bool) -> any Performer {
        switch self {
        case .sidefolk(let accent): Director(live: live, accent: accent)
        case .sprites(let art): SpriteDirector(art: art, live: live)
        }
    }
}
