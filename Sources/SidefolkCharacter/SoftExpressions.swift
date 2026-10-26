import CoreGraphics

/// Ink faces (Mochi and the folks), in Mochi's face units around each eye or the mouth.
enum Ink {
    static let bead = Stroke.pill(width: 10.5, height: 13)
    static let wide = Stroke.pill(width: 11.5, height: 15)
    static let small = Stroke.dot(7.5)
    static let happy = Stroke.arc(width: 12, rise: 5, thickness: 3.2)
    static let joy = Stroke.arc(width: 13, rise: 6.5, thickness: 3.6)
    static let closed = Stroke.arc(width: 11.5, rise: -3.8, thickness: 2.8)
    static let squint = Stroke.arc(width: 11, rise: 1.8, thickness: 3)
    /// ">"; the right eye mirrors it into "<".
    static let giddy = Stroke.polyline(pt(-4.5, 4.5), pt(4.5, 0), pt(-4.5, -4.5), width: 3)

    static let smile = Stroke.arc(width: 7.5, rise: -2.8, thickness: 2.4)
    static let grin = Stroke.arc(width: 10, rise: -4.8, thickness: 3.4)
    static let ooh = Stroke.dot(5)
    static let wobble = Stroke.arc(width: 7.5, rise: 2, thickness: 2.2)
    static let flat = Stroke.line(pt(-3, 0), pt(3, 0), width: 2.2)
    /// "ω": two small arcs from one skeleton.
    static let cat = Stroke(points: [pt(-5, 1), pt(-5, -2.6), pt(0, -2.6), pt(0, 0.6), pt(0, -2.6), pt(5, -2.6), pt(5, 1)], width: 2.2)

    /// Left brows; the right one mirrors.
    static let browRest = Stroke.line(pt(-5, 11), pt(5, 11), width: 2.4)
    static let browStern = Stroke.line(pt(-5.5, 12.5), pt(5, 9.5), width: 2.6)
    static let browWorried = Stroke.line(pt(-5.5, 9.5), pt(5, 12.5), width: 2.4)
}

/// Turns the shared choreography (written for the robot's glowing visor) into a soft face's
/// expression, ears included.
enum SoftExpressions {
    static func adapt(_ look: inout Look, for state: CharacterState, face: SoftFace) {
        switch face.kind {
        case .ink: ink(&look.pose, state, face.temper)
        case .screen: screen(&look.pose)
        }
        look.pose.scaleFace(face.scale)
        (look.pose.earL, look.pose.earR) = ears(state)
    }

    /// Ears, antennae and sprouts: they perk up for news, droop for trouble and sleep.
    static func ears(_ state: CharacterState) -> (CGFloat, CGFloat) {
        switch state {
        case .idle, .waiting, .working: (0, 0)
        case .listening: (0.28, -0.3)      // one ear up, the other relaxed
        case .thinking: (-0.12, 0.3)
        case .sleeping: (0.3, 0.24)
        case .success, .celebrating: (-0.15, -0.15)
        case .alert: (-0.28, -0.28)
        case .error: (0.65, 0.6)
        case .dragging: (0.35, 0.35)
        }
    }

    /// The robot's light strokes fit Spark's screen; it rests with open ovals instead of smiles.
    private static func screen(_ pose: inout Pose) {
        if pose.eyeL == Face.happy { pose.setEyes(Stroke.pill(width: 13.5, height: 22)) }
    }

    private static func ink(_ pose: inout Pose, _ state: CharacterState, _ temper: Temper) {
        let looksAway = pose.look, follow = pose.gazeFollow
        var face = Pose()
        face.mouthShown = 0
        switch state {
        case .idle, .listening, .working, .waiting:
            rest(&face, temper)
            if state == .listening, face.eyeL == Ink.bead { face.setEyes(Ink.wide) }
            if case .working(let prop) = state, [.binoculars, .card, .clock, .bell].contains(prop), face.eyeL == Ink.bead {
                face.setEyes(Ink.wide)
            }
            if state == .waiting { face.setMouth(Ink.smile) }
        case .sleeping:
            face.setEyes(Ink.closed)
            face.shine = 0
        case .thinking:
            face.setEyes(Ink.squint, Ink.bead)
            face.setMouth(Ink.flat.offset(3, 0))
        case .success:
            face.setEyes(Ink.happy)
            face.setMouth(Ink.smile)
            face.shine = 0
        case .error:
            face.setEyes(Ink.small)
            face.setBrows(Ink.browWorried)
            face.setMouth(Ink.wobble)
            face.shine = 0
        case .alert, .dragging:
            face.setEyes(Ink.wide)
            face.setMouth(Ink.ooh)
        case .celebrating:
            face.setEyes(Ink.giddy)
            face.setMouth(Ink.grin)
            face.shine = 0
        }
        pose.eyeL = face.eyeL
        pose.eyeR = face.eyeR
        pose.browL = face.browL
        pose.browR = face.browR
        pose.brows = face.brows
        pose.mouth = face.mouth
        pose.mouthShown = face.mouthShown
        pose.shine = face.shine
        pose.look = looksAway
        pose.gazeFollow = follow
    }

    /// The face a companion wears when nothing in particular is happening.
    private static func rest(_ face: inout Pose, _ temper: Temper) {
        face.browL = Ink.browRest
        face.browR = Ink.browRest.mirrored
        switch temper {
        case .calm:
            face.setEyes(Ink.bead)
        case .smiling:
            face.setEyes(Ink.bead)
            face.setMouth(Ink.smile)
        case .cheerful:
            face.setEyes(Ink.happy)
            face.setMouth(Ink.smile)
            face.shine = 0
        case .beaming:
            face.setEyes(Ink.happy)
            face.setMouth(Ink.grin)
            face.shine = 0
        case .content:
            face.setEyes(Ink.closed)
            face.setMouth(Ink.cat)
            face.shine = 0
        case .giddy:
            face.setEyes(Ink.giddy)
            face.setMouth(Ink.grin)
            face.shine = 0
        case .stern:
            face.setEyes(Ink.bead)
            face.setBrows(Ink.browStern)
            face.setMouth(Ink.flat)
        case .winking:
            face.setEyes(Ink.bead, Ink.happy.mirrored)
            face.setMouth(Ink.smile)
        }
    }
}

extension Pose {
    /// Strokes are drawn for Mochi's face; larger faces scale them about each mark's middle.
    mutating func scaleFace(_ s: CGFloat) {
        guard s != 1 else { return }
        eyeL = eyeL.scaled(s)
        eyeR = eyeR.scaled(s)
        browL = browL.scaled(s)
        browR = browR.scaled(s)
        mouth = mouth.scaled(s)
    }
}
