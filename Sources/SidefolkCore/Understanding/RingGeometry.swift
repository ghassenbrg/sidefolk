import Foundation

/// Which slice of the ring a point is on (D152), the first straight up and the rest clockwise. The middle and the outside are on none,
/// so a stray release chooses nothing.
public enum RingGeometry {
    /// `dx` to the right and `dy` up, from the ring's centre.
    public static func slice(dx: Double, dy: Double, count: Int, inner: Double, outer: Double) -> Int? {
        guard count > 0 else { return nil }
        let distance = hypot(dx, dy)
        guard distance >= inner, distance <= outer else { return nil }
        let step = 2 * Double.pi / Double(count)
        var angle = atan2(dx, dy) + step / 2
        if angle < 0 { angle += 2 * .pi }
        return Int(angle / step) % count
    }

    /// The middle of a slice, in the same frame.
    public static func centre(of index: Int, count: Int, radius: Double) -> (dx: Double, dy: Double) {
        let angle = 2 * Double.pi * Double(index) / Double(max(count, 1))
        return (sin(angle) * radius, cos(angle) * radius)
    }
}
