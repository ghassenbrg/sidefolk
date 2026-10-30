import AppKit
import QuartzCore

/// What a pose change asks of the layers: at once, or with a spring.
extension Transit {
    var isInstant: Bool {
        if case .instant = self { return true }
        return false
    }

    var isSpring: Bool {
        if case .spring = self { return true }
        return false
    }
}

/// Where a foot goes for a pose: dangling when lifted, forward and apart when sitting, and staying on the
/// floor when the body sinks onto it (asleep, lying down).
enum Feet {
    static func transform(_ pose: Pose, side: CGFloat) -> CGAffineTransform {
        let drop = pose.feetDangle, splay = pose.feetSplay, sink = min(pose.lift, 0)
        return CGAffineTransform(translationX: side * (drop * 1.5 + splay * 5), y: -drop * 4 - splay * 3 - sink)
            .rotated(by: side * (drop * 0.35 - splay * 0.1))
            .scaledBy(x: 1 + splay * 0.14, y: 1 + splay * 0.14)
    }
}
