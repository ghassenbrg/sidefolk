import QuartzCore

/// A companion's body as `Director` drives it: the robot's `RobotRig` (D2) or a `SoftRig` built
/// from a `Species` (Mochi, Spark, the folks). All draw in the same 200×200 canvas (y up, feet on
/// y = 20), and nest the same transform layers, so one choreography, one set of gestures, props,
/// effects and badges, and one view serve every companion.
///
/// Nesting, outside in: `stage` › body pose › `loop` (the state's repeating motion) › `gesture`
/// (one-shot moves) › `breath`; the face sits under `breath` with `faceGesture` › `scan` › `blink`.
@MainActor
protocol Figure: AnyObject {
    var stage: CALayer { get }
    var loop: CALayer { get }
    var gesture: CALayer { get }
    var breath: CALayer { get }
    var faceGesture: CALayer { get }
    var scan: CALayer { get }
    /// Squashed vertically for a blink; anchored on the eye line.
    var blink: CALayer { get }
    var armL: Limb { get }
    var armR: Limb { get }
    var propBack: CALayer { get }
    var propFront: CALayer { get }
    /// Effects that ride on the body, and those that float on the stage.
    var bodyFX: CALayer { get }
    var stageFX: CALayer { get }
    var badges: CALayer { get }

    /// The body at rest, in canvas units: what bubbles and panels attach to.
    var restingFrame: CGRect { get }
    /// Layers that pulse while listening (the robot's ear lights, Spark's headphones).
    var listeningLights: [CALayer] { get }
    /// The colour marks are drawn in (zZz, waves, thought dots).
    var markLight: Light { get }
    /// How far each effect sits from where it sits beside the robot's head.
    func markOffset(_ effect: Effect) -> CGPoint

    /// The state's pose and expression for this body (the shared choreography, then its own face).
    func look(for state: CharacterState) -> Look
    func apply(_ pose: Pose, _ transit: Transit)
    func setGaze(_ gaze: CGVector?, _ transit: Transit)
    /// The outline that catches clicks for the current pose, in canvas units.
    func silhouette(extra: CGRect?) -> CGPath
    /// Repeating motion of its own in `state` (ears swaying), on top of the shared loops.
    func loops(for state: CharacterState) -> [Loop]
    /// Ears and antennae trail behind a one-shot move.
    func follow(_ gesture: CharacterGesture)
    func dress(_ style: CharacterStyle)
    /// Speaking: the mouth opens by `openness` (0...1) over whatever the pose shows; nil gives the
    /// pose its own mouth back.
    func talk(_ openness: CGFloat?, _ transit: Transit)
    /// The layers an antic moves for `part` (none when the body has no such part).
    func movers(_ part: Part) -> [Mover]
    /// `pose` with a moment's face (and ears) on top, in this body's own strokes.
    func express(_ mood: Mood, on pose: Pose, mirrored: Bool) -> Pose
}

extension Figure {
    /// An open mouth as one stroke: a round "o" that grows taller as the voice gets louder, built
    /// from the same skeleton as every other mark, so it morphs from and back to any mouth.
    static func talkingMouth(_ openness: CGFloat, width: CGFloat) -> Stroke {
        Stroke.pill(width: width, height: width * (1 + 1.1 * openness))
    }
}
