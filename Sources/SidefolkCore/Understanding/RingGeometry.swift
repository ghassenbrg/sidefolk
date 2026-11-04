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

    /// A click counts where it's let go on the slice that's lit: anywhere else is how a click is taken back.
    public static func clickCounts(at slice: Int?, lit: Int?) -> Bool {
        slice != nil && slice == lit
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
    static let stillWithin = 3.0

    private let openedAt: TimeInterval
    private let start: (x: Double, y: Double)
    private var moved = false
    private var slice: Int?
    private var since: TimeInterval = 0
    private var anchor: (x: Double, y: Double)

    public init(openedAt: TimeInterval, x: Double, y: Double) {
        self.openedAt = openedAt
        start = (x, y)
        anchor = (x, y)
    }

    /// The pointer is here, on that slice if any. Returns the slice to light: nothing until it has moved.
    public mutating func follow(x: Double, y: Double, slice index: Int?, at now: TimeInterval) -> Int? {
        if hypot(x - start.x, y - start.y) >= Self.leastMove { moved = true }
        let shown = moved ? index : nil
        // Resting means resting, near where it began: slow steady steps are still a hand on its way, however often they're sampled.
        if shown != slice || hypot(x - anchor.x, y - anchor.y) > Self.stillWithin {
            slice = shown
            since = now
            anchor = (x, y)
        }
        return shown
    }

    /// The ring turned to its other set: whatever was under the pointer isn't what was seen there.
    public mutating func turned(at now: TimeInterval) {
        slice = nil
        since = now
    }

    /// The slice a release now would choose, if any.
    public func ready(at now: TimeInterval) -> Int? {
        guard now - openedAt >= Self.leastOpen, now - since >= Self.leastRest else { return nil }
        return slice
    }
}
