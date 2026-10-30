import CoreGraphics

/// Every number the rig needs to hold one still frame. States map to poses; the rig springs
/// from whatever is on screen to the next pose, so any state can follow any other.
struct Pose: Equatable, Sendable {
    // Body, around the floor pivot.
    var lift: CGFloat = 0
    var shift: CGFloat = 0
    var lean: CGFloat = 0
    var squash = CGSize(width: 1, height: 1)

    // Face. The right eye is drawn from `eyeR` as given (build it mirrored when needed).
    var eyeL = Face.happy
    var eyeR = Face.happy
    var browL = Face.browRest
    var browR = Face.browRest.mirrored
    var brows: CGFloat = 0
    var mouth = Face.smile
    var mouthShown: CGFloat = 0
    /// Where the eyes look by default (-1...1); `gazeFollow` says how much the pointer may steer them.
    var look = CGVector.zero
    var gazeFollow: CGFloat = 1

    // Limbs. Arm angles are "raise" in radians: 0 hangs down, positive swings outward and up,
    // negative swings in front of the body.
    var armL: CGFloat = 0.4
    var armR: CGFloat = 0.4
    var feetDangle: CGFloat = 0
    /// Feet brought forward and apart, as when sitting (0 standing).
    var feetSplay: CGFloat = 0

    // Light and ground.
    var earGlow: CGFloat = 0.55
    var groundShadow: CGFloat = 1

    // Soft companions (SoftRig); the robot ignores these.
    /// Ears, antennae and tufts: 0 rests, positive droops outward, negative perks up.
    var earL: CGFloat = 0
    var earR: CGFloat = 0
    /// Soft ears folded back and down along the head (asleep): 0 upright, 1 folded.
    var earFold: CGFloat = 0
    /// The catchlight in bead eyes: 1 for open eyes, 0 when they are arcs or closed.
    var shine: CGFloat = 1
    /// Its signature thing in hand (1) or put away (0).
    var holding: CGFloat = 0
    /// The head drooping, asleep or dozing: tilted (radians, positive toward our right) and sunk this far
    /// around the neck. A body without a head of its own leans and sinks instead.
    var headTilt: CGFloat = 0
    var headDrop: CGFloat = 0

    static func eyes(_ left: Stroke, _ right: Stroke? = nil) -> (Stroke, Stroke) {
        (left, right ?? left.mirrored)
    }

    mutating func setEyes(_ left: Stroke, _ right: Stroke? = nil) {
        (eyeL, eyeR) = Pose.eyes(left, right)
    }

    mutating func setBrows(_ left: Stroke) {
        browL = left
        browR = left.mirrored
        brows = 1
    }

    mutating func setMouth(_ mouth: Stroke) {
        self.mouth = mouth
        mouthShown = 1
    }
}
