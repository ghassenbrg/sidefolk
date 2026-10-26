import CoreGraphics

/// A facial mark (eye, brow, mouth) drawn as a round-capped stroke along a center line.
///
/// Every mark is the same path skeleton: one move and two cubic segments. Core Animation can only
/// morph paths with matching elements, so keeping one skeleton lets any eye become any other
/// (a dot is a zero-length line whose round caps make a disc; a pill is a short line).
struct Stroke: Equatable, Sendable {
    /// p0, c1, c2, p1, c3, c4, p2, relative to the mark's center.
    var points: [CGPoint]
    var width: CGFloat

    func path(at center: CGPoint) -> CGPath {
        let p = points.map { $0 + center }
        let path = CGMutablePath()
        path.move(to: p[0])
        path.addCurve(to: p[3], control1: p[1], control2: p[2])
        path.addCurve(to: p[6], control1: p[4], control2: p[5])
        return path
    }

    var mirrored: Stroke {
        Stroke(points: points.map { pt(-$0.x, $0.y) }.reversed(), width: width)
    }

    func offset(_ dx: CGFloat, _ dy: CGFloat) -> Stroke {
        Stroke(points: points.map { $0 + pt(dx, dy) }, width: width)
    }

    func scaled(_ s: CGFloat) -> Stroke {
        Stroke(points: points.map { $0 * s }, width: width * s)
    }

    // MARK: Builders

    /// Straight line from a through b to c (b is the joint, so a chevron when not collinear).
    static func polyline(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, width: CGFloat) -> Stroke {
        Stroke(points: [a, a.lerp(b, 1.0 / 3), a.lerp(b, 2.0 / 3), b, b.lerp(c, 1.0 / 3), b.lerp(c, 2.0 / 3), c],
               width: width)
    }

    static func line(_ a: CGPoint, _ b: CGPoint, width: CGFloat) -> Stroke {
        polyline(a, a.lerp(b, 0.5), b, width: width)
    }

    static func dot(_ diameter: CGFloat) -> Stroke {
        Stroke(points: Array(repeating: .zero, count: 7), width: diameter)
    }

    /// A hollow ring, two half circles from the top round to the top again: dizzy eyes.
    static func ring(radius r: CGFloat, width: CGFloat) -> Stroke {
        let k = r * 4 / 3
        return Stroke(points: [pt(0, r), pt(k, r), pt(k, -r), pt(0, -r), pt(-k, -r), pt(-k, r), pt(0, r)], width: width)
    }

    /// Upright capsule of the given outer size.
    static func pill(width: CGFloat, height: CGFloat) -> Stroke {
        let half = max(height - width, 0) / 2
        return line(pt(0, -half), pt(0, half), width: width)
    }

    /// Circular arc across a chord of `width`; `rise` > 0 bulges up (a happy ^), < 0 down (a closed ‿).
    static func arc(width: CGFloat, rise: CGFloat, thickness: CGFloat) -> Stroke {
        let a = width / 2
        guard abs(rise) > 0.01 else { return line(pt(-a, 0), pt(a, 0), width: thickness) }
        let s = abs(rise)
        let radius = (a * a + s * s) / (2 * s)
        let center = pt(0, s - radius)
        let right = atan2(-center.y, a)              // angle of the right end
        let half = .pi / 2 - right                   // each segment's sweep
        let k = 4.0 / 3.0 * tan(half / 4) * radius
        func at(_ t: CGFloat) -> CGPoint { center + pt(cos(t), sin(t)) * radius }
        func tangent(_ t: CGFloat) -> CGPoint { pt(sin(t), -cos(t)) }    // clockwise travel
        let left = .pi - right
        let p0 = at(left), apex = at(.pi / 2), p2 = at(right)
        var pts = [p0, p0 + tangent(left) * k, apex - pt(k, 0), apex,
                   apex + pt(k, 0), p2 - tangent(right) * k, p2]
        // Shift so the mark is centered on its visual middle rather than on the chord.
        pts = pts.map { $0 - pt(0, rise / 2) }
        if rise < 0 { pts = pts.map { pt($0.x, -$0.y) } }
        return Stroke(points: pts, width: thickness)
    }
}

/// The main character's expressions, in canvas units around each eye center.
enum Face {
    static let happy = Stroke.arc(width: 23, rise: 9.5, thickness: 7)
    static let joy = Stroke.arc(width: 25, rise: 11.5, thickness: 7.5)
    static let open = Stroke.dot(15)
    static let oval = Stroke.pill(width: 12.5, height: 17.5)
    static let small = Stroke.dot(11)
    static let closed = Stroke.arc(width: 20, rise: -5.5, thickness: 4.6)
    static let squint = Stroke.arc(width: 17, rise: 2.5, thickness: 5)

    // Brows sit above the eye; hidden unless a pose fades them in.
    static let browRest = Stroke.line(pt(-8, 15), pt(8, 15), width: 3.6)
    /// Left brow, inner end (toward the middle) raised.
    static let browWorried = Stroke.line(pt(-9, 13), pt(7, 18.5), width: 3.6)

    // Mouths, centered under the eyes.
    static let smile = Stroke.arc(width: 10, rise: -3.5, thickness: 3.4)
    static let grin = Stroke.arc(width: 14, rise: -6.5, thickness: 4.4)
    static let ooh = Stroke.dot(7)
    static let wobble = Stroke.arc(width: 10, rise: 2.6, thickness: 3.2)
    static let flat = Stroke.line(pt(-4, 0), pt(4, 0), width: 3)
}
