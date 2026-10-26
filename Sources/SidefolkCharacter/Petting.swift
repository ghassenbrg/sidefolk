import CoreGraphics
import Foundation

/// Recognizes stroking: the pointer going back and forth over the companion with no button held,
/// sideways or up and down. Three strokes within a second and a half (back, forth, back) is petting;
/// a pause or leaving the body starts over.
public struct PettingDetector: Sendable {
    private var x = Axis()
    private var y = Axis()
    private var last: (point: CGPoint, time: TimeInterval)?

    public init() {}

    /// Feeds one pointer position (any coordinates); true when this one completes a pet.
    public mutating func add(_ point: CGPoint, inside: Bool, at time: TimeInterval) -> Bool {
        guard inside else {
            self = PettingDetector()
            return false
        }
        defer { last = (point, time) }
        guard let last else { return false }
        if time - last.time > 0.4 {
            self = PettingDetector()
            return false
        }
        let petted = x.add(point.x - last.point.x, at: time) || y.add(point.y - last.point.y, at: time)
        if petted { self = PettingDetector() }
        return petted
    }

    /// Strokes along one axis: each change of direction ends one if it travelled far enough.
    private struct Axis: Sendable {
        private var direction: CGFloat = 0
        private var travel: CGFloat = 0
        private var strokes: [TimeInterval] = []
        static let reach: CGFloat = 7
        static let window: TimeInterval = 1.5

        mutating func add(_ delta: CGFloat, at time: TimeInterval) -> Bool {
            guard abs(delta) > 0.3 else { return false }
            let heading: CGFloat = delta > 0 ? 1 : -1
            if heading == direction {
                travel += abs(delta)
            } else {
                if travel >= Self.reach { strokes.append(time) }
                direction = heading
                travel = abs(delta)
            }
            strokes.removeAll { time - $0 > Self.window }
            // Two finished strokes and a third under way.
            return strokes.count >= 2 && travel >= Self.reach
        }
    }
}

/// A companion thrown with the pointer: it keeps flying a moment, slowing down sideways, and falls
/// to the floor. Positions are in screen points (y up); the host moves its window along them.
public struct Fling: Sendable {
    public let start: CGPoint
    public let velocity: CGVector
    public let floor: CGFloat
    public let duration: TimeInterval
    private let span: ClosedRange<CGFloat>

    /// Faster than this on release (points per second) is a throw, not a drop.
    public static let tossSpeed: CGFloat = 1100
    static let gravity: CGFloat = 2600
    /// Sideways speed decays with this time constant: a short glide, not a slide across the screen.
    static let drag: CGFloat = 0.28

    /// `span` is where the window's origin may go sideways (the screen, less its width).
    public init(from start: CGPoint, velocity: CGVector, floor: CGFloat, span: ClosedRange<CGFloat>) {
        self.start = start
        self.floor = floor
        self.span = span
        // Very fast throws are capped, so it stays on screen and on its feet.
        let speed = hypot(velocity.dx, velocity.dy), cap: CGFloat = 2600
        let k = speed > cap ? cap / speed : 1
        self.velocity = CGVector(dx: velocity.dx * k, dy: velocity.dy * k)
        let height = max(start.y - floor, 0), up = self.velocity.dy
        let fall = (up + sqrt(up * up + 2 * Self.gravity * height)) / Self.gravity
        duration = TimeInterval(min(max(fall, 0.35), 1.2))
    }

    public static func isToss(_ velocity: CGVector) -> Bool { hypot(velocity.dx, velocity.dy) > tossSpeed }

    /// Where the window's origin is `t` seconds into the flight.
    public func position(at t: TimeInterval) -> CGPoint {
        let t = CGFloat(min(max(t, 0), duration)), end = CGFloat(duration)
        let x = start.x + velocity.dx * Self.drag * (1 - exp(-t / Self.drag))
        // A real arc, then pinned to land exactly on the floor at the end.
        let arc = start.y + velocity.dy * t - Self.gravity * t * t / 2
        let landing = start.y + velocity.dy * end - Self.gravity * end * end / 2
        let y = arc - (landing - floor) * (t / end)
        return CGPoint(x: min(max(x, span.lowerBound), span.upperBound), y: max(y, floor))
    }

    /// How hard it lands, 0...1: a soft drop barely squashes, a hard throw makes it dizzy.
    public var impact: CGFloat {
        let fallSpeed = abs(velocity.dy - Self.gravity * CGFloat(duration))
        return min(1, (hypot(velocity.dx, velocity.dy) + fallSpeed) / 4000)
    }
}
