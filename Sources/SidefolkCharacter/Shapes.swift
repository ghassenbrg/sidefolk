import CoreGraphics

/// The character lives in a 200×200 canvas (y up) and stands on y = 20.
/// Every rig layer uses these coordinates; the view scales the whole canvas to fit.
enum Canvas {
    static let size = CGSize(width: 200, height: 200)
    static let floor: CGFloat = 20
    static let pivot = pt(100, 20)

    static let eyeL = pt(79, 97)
    static let eyeR = pt(121, 97)
    static let mouth = pt(100, 78)
    static let earL = pt(39, 99)
    static let earR = pt(161, 99)
    static let shoulderL = pt(49, 69)
    static let shoulderR = pt(151, 69)
    static let footL = pt(82, 27)
    static let footR = pt(118, 27)
    static let visor = CGRect(x: 54, y: 68, width: 92, height: 58)
}

/// Static silhouettes of the character's parts, in canvas units.
@MainActor
enum Shapes {
    /// One chubby mass: a broad dome over a slightly narrower, rounder base.
    static let body: CGPath = {
        let cx: CGFloat = 100, top: CGFloat = 146, bottom: CGFloat = 30, mid: CGFloat = 98
        let rx: CGFloat = 62
        let p = CGMutablePath()
        p.move(to: pt(cx, top))
        p.addCurve(to: pt(cx + rx, mid), control1: pt(cx + rx * 0.64, top), control2: pt(cx + rx, mid + (top - mid) * 0.62))
        p.addCurve(to: pt(cx, bottom), control1: pt(cx + rx, mid - (mid - bottom) * 0.6), control2: pt(cx + rx * 0.6, bottom))
        p.addCurve(to: pt(cx - rx, mid), control1: pt(cx - rx * 0.6, bottom), control2: pt(cx - rx, mid - (mid - bottom) * 0.6))
        p.addCurve(to: pt(cx, top), control1: pt(cx - rx, mid + (top - mid) * 0.62), control2: pt(cx - rx * 0.64, top))
        p.closeSubpath()
        return p
    }()

    static let visor = Paths.roundedRect(Canvas.visor, 25)

    /// The ring of shell that frames the visor, a little larger than the glass.
    static let visorRim = Paths.roundedRect(Canvas.visor.insetBy(dx: -3, dy: -3), 28)

    /// The swoosh on top of the head: rises from the left and curls over to a tip on the right.
    /// Its base sits inside the body so the shell hides the join.
    static let fin: CGPath = {
        let p = CGMutablePath()
        p.move(to: pt(73, 132))
        p.addCurve(to: pt(91, 171), control1: pt(70, 152), control2: pt(78, 167))
        p.addCurve(to: pt(140, 165), control1: pt(106, 177), control2: pt(130, 176))
        p.addCurve(to: pt(117, 146), control1: pt(137, 156), control2: pt(127, 149))
        p.addCurve(to: pt(104, 132), control1: pt(110, 144), control2: pt(105, 139))
        p.closeSubpath()
        return p
    }()

    /// A stubby mitten hanging from a shoulder at the origin, hand at the bottom.
    static let arm: CGPath = {
        let p = CGMutablePath()
        p.move(to: pt(-8, 4))
        p.addCurve(to: pt(-11, -14), control1: pt(-10, -2), control2: pt(-12, -8))
        p.addCurve(to: pt(0, -25), control1: pt(-11, -21), control2: pt(-6, -25))
        p.addCurve(to: pt(11, -14), control1: pt(6, -25), control2: pt(11, -21))
        p.addCurve(to: pt(8, 4), control1: pt(12, -8), control2: pt(10, -2))
        p.addCurve(to: pt(-8, 4), control1: pt(4, 8), control2: pt(-4, 8))
        p.closeSubpath()
        return p
    }()

    static func foot(_ center: CGPoint) -> CGPath { Paths.ellipse(center, 14, 9.5) }

    static func earPod(_ center: CGPoint) -> CGPath { Paths.ellipse(center, 13.5, 25) }

    /// The parts that never move relative to the body, merged into one outline.
    static let trunk: CGPath = {
        body.union(fin)
            .union(earPod(Canvas.earL))
            .union(earPod(Canvas.earR))
            .union(foot(Canvas.footL))
            .union(foot(Canvas.footR))
    }()
}
