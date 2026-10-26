import QuartzCore

/// Everything a state shows on a sprite companion.
struct SpriteLook: Equatable {
    /// One pose holds still; two or more take turns while motion runs.
    var poses: [SpritePose] = [.idle]
    /// How long each pose shows when they take turns.
    var beat: CFTimeInterval = 0.45
    /// Raised off the floor (canvas units), with the ground shadow shrunk to `shadow`.
    var lift: CGFloat = 0
    var shadow: CGFloat = 1
    /// Leans a little toward the pointer.
    var followsPointer = true
    var breath = Breath.calm
}

/// The state table of docs/PRODUCT.md §8 for the legacy crew's poses (DECISIONS D27).
enum SpriteChoreography {
    static func look(for state: CharacterState) -> SpriteLook {
        var look = SpriteLook()
        switch state {
        case .idle: break
        case .sleeping:
            look.poses = [.sleep]
            look.followsPointer = false
            look.breath = .sleepy
        case .listening: look.poses = [.listen]
        case .thinking: look.poses = [.think]
        case .working(.notepad):
            look.poses = [.write1, .write2]
            look.beat = 0.4
        case .working:
            // Typing on the little laptop, whatever the tool: the sprites have no other props.
            look.poses = [.work1, .work2]
            look.beat = 0.3
        case .waiting: look.poses = [.note]   // holds up the card the approval is on
        case .success: look.poses = [.done]
        case .error: look.poses = [.sad]
        case .alert: look.poses = [.alert]
        case .dragging:
            look.poses = [.dangle]
            look.lift = 12
            look.shadow = 0.35
            look.followsPointer = false
        case .celebrating:
            look.poses = [.wave, .done]
            look.beat = 0.5
        }
        return look
    }

    /// Repeating motion beyond breathing and pose turns, mirroring the vector rig's loops.
    @MainActor
    static func loops(for state: CharacterState, loop: CALayer, swing: CALayer) -> [Loop] {
        switch state {
        case .idle:
            return [Loop(layer: loop, key: "sway", animation: Motion.loop("transform.rotation.z", from: -0.012, to: 0.012, duration: 3.4))]
        case .thinking, .waiting:
            return [Loop(layer: loop, key: "sway", animation: Motion.loop("transform.rotation.z", from: -0.025, to: 0.025, duration: 2.2))]
        case .alert:
            // A small bounce every so often: something needs you.
            let bounce = Motion.cycle("transform.translation.y", [0, 7, 0, 0], duration: 1.4, times: [0, 0.15, 0.32, 1])
            return [Loop(layer: loop, key: "bounce", animation: bounce)]
        case .dragging:
            // Hangs from where it is held and swings a little.
            return [Loop(layer: swing, key: "dangle", animation: Motion.loop("transform.rotation.z", from: -0.07, to: 0.07, duration: 0.75))]
        case .celebrating:
            let hop = Motion.cycle("transform", [
                Motion.transform(.identity),
                Motion.transform(CGAffineTransform(scaleX: 1.06, y: 0.93)),
                Motion.transform(CGAffineTransform(translationX: 0, y: 16).scaledBy(x: 0.96, y: 1.05)),
                Motion.transform(.identity), Motion.transform(.identity),
            ], duration: 1.0, times: [0, 0.12, 0.42, 0.72, 1])
            return [Loop(layer: loop, key: "hop", animation: hop)]
        default:
            return []
        }
    }
}
