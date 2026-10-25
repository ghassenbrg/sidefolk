import CoreGraphics

func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }

    func rotated(_ angle: CGFloat) -> CGPoint {
        CGPoint(x: x * cos(angle) - y * sin(angle), y: x * sin(angle) + y * cos(angle))
    }

    func lerp(_ other: CGPoint, _ t: CGFloat) -> CGPoint { self + (other - self) * t }
}

enum Paths {
    static func ellipse(_ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    static func circle(_ center: CGPoint, _ r: CGFloat) -> CGPath { ellipse(center, r, r) }

    static func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        let r = min(radius, rect.width / 2, rect.height / 2)
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    /// Smooth closed curve through `points` (uniform Catmull-Rom as cubic Béziers).
    static func blob(_ points: [CGPoint]) -> CGPath {
        let n = points.count
        let path = CGMutablePath()
        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n], p1 = points[i]
            let p2 = points[(i + 1) % n], p3 = points[(i + 2) % n]
            path.addCurve(to: p2, control1: p1 + (p2 - p0) * (1.0 / 6), control2: p2 - (p3 - p1) * (1.0 / 6))
        }
        path.closeSubpath()
        return path
    }

    static func polyline(_ points: [CGPoint], closed: Bool = false) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        if closed { path.closeSubpath() }
        return path
    }

    static func transformed(_ path: CGPath, _ transform: CGAffineTransform) -> CGPath {
        var t = transform
        return path.copy(using: &t) ?? path
    }

    static func translated(_ path: CGPath, _ dx: CGFloat, _ dy: CGFloat) -> CGPath {
        transformed(path, CGAffineTransform(translationX: dx, y: dy))
    }

    /// Four-point twinkle star with concave sides.
    static func sparkle(_ center: CGPoint, _ r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let pinch = r * 0.16
        let tips = [pt(0, r), pt(r, 0), pt(0, -r), pt(-r, 0)]
        let inner = [pt(pinch, pinch), pt(pinch, -pinch), pt(-pinch, -pinch), pt(-pinch, pinch)]
        path.move(to: center + tips[0])
        for i in 0..<4 {
            path.addQuadCurve(to: center + tips[(i + 1) % 4], control: center + inner[i])
        }
        path.closeSubpath()
        return path
    }
}
