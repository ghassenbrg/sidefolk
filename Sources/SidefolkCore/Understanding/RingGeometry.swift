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

/// When a slice under the pointer counts (D152). The ring opens under a hand that may be on its way somewhere else, with ⌥ held because
/// that's how Finder copies, so where the pointer already is chooses nothing, however the ring had to shift at a screen's edge: it has to move
/// first, onto a slice, and stay there a moment.
public struct RingAim: Sendable {
    public static let leastMove = 14.0
    public static let leastOpen: TimeInterval = 0.4
    public static let leastRest: TimeInterval = 0.15

    private let openedAt: TimeInterval
    private let start: (x: Double, y: Double)
    private var moved = false
    private var slice: Int?
    private var since: TimeInterval = 0

    public init(openedAt: TimeInterval, x: Double, y: Double) {
        self.openedAt = openedAt
        start = (x, y)
    }

    /// The pointer is here, on that slice if any. Returns the slice to light: nothing until it has moved.
    public mutating func follow(x: Double, y: Double, slice index: Int?, at now: TimeInterval) -> Int? {
        if hypot(x - start.x, y - start.y) >= Self.leastMove { moved = true }
        let shown = moved ? index : nil
        if shown != slice {
            slice = shown
            since = now
        }
        return shown
    }

    /// The slice a release now would choose, if any.
    public func ready(at now: TimeInterval) -> Int? {
        guard now - openedAt >= Self.leastOpen, now - since >= Self.leastRest else { return nil }
        return slice
    }
}
