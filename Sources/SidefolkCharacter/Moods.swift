import CoreGraphics

/// Faces for moments and the postures of a quiet companion, as changes to a state's pose.
/// Ink faces (Mochi, the folks) use `Ink` strokes at the face's scale; light faces (the robot's
/// visor, Spark's screen) use the robot's `Face` strokes.
enum Moods {
    static func apply(_ mood: Mood, to pose: Pose, ink: Bool, scale: CGFloat, mirrored: Bool) -> Pose {
        var p = pose
        let wide = ink ? Ink.wide : Face.oval.scaled(1.05)
        let bead = ink ? Ink.bead : Face.oval
        func eyes(_ left: Stroke, _ right: Stroke? = nil) {
            let (l, r) = Pose.eyes(left, right)
            (p.eyeL, p.eyeR) = mirrored ? (r.mirrored, l.mirrored) : (l, r)
        }
        func mouth(_ stroke: Stroke) { p.setMouth(stroke) }
        switch mood {
        case .squeeze:
            eyes(ink ? Ink.giddy : Face.squint)
            mouth(ink ? Ink.ooh.scaled(0.8) : Face.ooh)
            p.shine = 0
        case .bliss:
            eyes(ink ? Ink.happy : Face.happy)
            mouth(ink ? Ink.cat : Face.smile)
            p.shine = 0
            p.earL = max(p.earL, 0.3)
            p.earR = max(p.earR, 0.3)
        case .yawn:
            eyes(ink ? Ink.closed : Face.closed)
            mouth(Stroke.pill(width: ink ? 8 : 11, height: ink ? 10.5 : 14))
            p.shine = 0
        case .surprised:
            eyes(wide)
            mouth(ink ? Ink.ooh : Face.ooh)
            p.shine = 1
            p.earL = min(p.earL, -0.25)
            p.earR = min(p.earR, -0.25)
        case .dizzy:
            eyes(ink ? Stroke.ring(radius: 3.6, width: 2.2) : Stroke.ring(radius: 6.5, width: 3.6))
            mouth(ink ? Ink.wobble : Face.wobble)
            p.shine = 0
        case .drowsy:
            eyes(Stroke.arc(width: ink ? 11 : 19, rise: ink ? -1.2 : -2, thickness: ink ? 3.2 : 4.6))
            p.shine = 0
            p.earL = max(p.earL, 0.18)
            p.earR = max(p.earR, 0.18)
        case .curious:
            eyes(wide, bead.scaled(0.85))
            mouth(ink ? Stroke.dot(3.6) : Stroke.dot(5))
            p.shine = 1
        case .sniff:
            eyes(ink ? Ink.squint : Face.squint)
            mouth(ink ? Stroke.dot(3.4) : Stroke.dot(5))
            p.shine = 0
        case .joy:
            eyes(ink ? Ink.joy : Face.joy)
            mouth(ink ? Ink.grin : Face.grin)
            p.shine = 0
        case .wince:
            eyes(bead, (ink ? Ink.giddy : Face.squint).mirrored)
            p.shine = 1
        }
        if scale != 1 {
            // Only the new strokes are scaled; the pose's own are already at the face's size.
            for (stroke, kept) in [(\Pose.eyeL, pose.eyeL), (\Pose.eyeR, pose.eyeR), (\Pose.mouth, pose.mouth)]
            where p[keyPath: stroke] != kept {
                p[keyPath: stroke] = p[keyPath: stroke].scaled(scale)
            }
        }
        return p
    }

    /// Sitting lowers the body around the floor and brings the feet forward, its thing still in hand;
    /// lying down settles it low on its feet, head resting to one side, eyes half-closed, soft ears lying
    /// half back, hands empty.
    static func posture(_ posture: CharacterPosture, on pose: Pose, express: (Mood, Pose) -> Pose) -> Pose {
        var p = pose
        switch posture {
        case .stand:
            return pose
        case .sit:
            p.squash = CGSize(width: 1.04, height: 0.92)
            p.feetSplay = 1
            if pose.holding == 0 {
                p.armL = -0.1
                p.armR = -0.1
            }
        case .lie:
            // Settled low on its feet, head resting a little to one side: lower, never squashed.
            p.lift = -6
            p.feetSplay = 1.4
            p.lean = 0.02
            p.headTilt = 0.12
            p.headDrop = 3
            // It puts its thing down to lie down (Scout's magnifier would stick out of the window).
            p.holding = 0
            p.armL = -0.25
            p.armR = -0.25
            p.look = CGVector(dx: p.look.dx, dy: p.look.dy - 0.15)
            p = express(.drowsy, p)
            p.earFold = 0.3
        }
        return p
    }
}
