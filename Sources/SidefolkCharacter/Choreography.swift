import QuartzCore

/// Everything a state shows: a pose, marks around it, a held prop and how it breathes.
struct Look {
    var pose = Pose()
    var effects: Set<Effect> = []
    var prop: CharacterProp = .none
    var blinks = true
    var breath = Breath.calm
}

enum Breath {
    case calm, sleepy
}

/// The state table of docs/PRODUCT.md §8 as poses.
enum Choreography {
    static func look(for state: CharacterState) -> Look {
        var look = Look()
        switch state {
        case .idle:
            break

        case .sleeping:
            look.pose.squash = CGSize(width: 1.14, height: 0.8)
            look.pose.lean = 0.05
            look.pose.setEyes(Face.closed)
            look.pose.armL = -0.15
            look.pose.armR = -0.15
            look.pose.earGlow = 0.1
            look.pose.look = CGVector(dx: 0, dy: -0.3)
            look.pose.gazeFollow = 0
            look.effects = [.zzz]
            look.blinks = false
            look.breath = .sleepy

        case .listening:
            look.pose.setEyes(Face.oval)
            look.pose.look = CGVector(dx: 0.25, dy: 0.12)
            look.pose.lean = -0.04
            look.pose.armL = 0.3
            look.pose.armR = 0.55
            look.pose.earGlow = 1
            look.effects = [.waves]

        case .thinking:
            look.pose.setEyes(Face.oval.scaled(0.92), Face.squint)
            look.pose.look = CGVector(dx: 0.4, dy: 0.8)
            look.pose.gazeFollow = 0.2
            look.pose.setMouth(Face.flat.offset(4, 0))
            look.pose.armR = -2.3
            look.pose.armL = 0.15
            look.pose.earGlow = 0.75
            look.effects = [.dots]

        case .working(let prop):
            look.prop = prop
            look.pose.earGlow = 0.7
            Props.adjust(&look.pose, for: prop)

        case .waiting:
            look.prop = .card
            look.pose.earGlow = 0.8
            Props.adjust(&look.pose, for: .card)
            look.pose.setMouth(Face.smile.scaled(0.8))

        case .success:
            look.pose.setEyes(Face.joy)
            look.pose.setMouth(Face.smile)
            look.pose.armL = 1.0
            look.pose.armR = 1.0
            look.pose.earGlow = 0.9
            look.effects = [.sparkles]

        case .error:
            look.pose.setEyes(Face.small)
            look.pose.setBrows(Face.browWorried)
            look.pose.setMouth(Face.wobble)
            look.pose.look = CGVector(dx: 0, dy: -0.25)
            look.pose.gazeFollow = 0.3
            look.pose.armL = -0.45
            look.pose.armR = -0.45
            look.pose.lean = 0.03
            look.pose.earGlow = 0.25
            look.effects = [.sweat]

        case .alert:
            look.pose.setEyes(Face.oval.scaled(1.05))
            look.pose.setMouth(Face.ooh)
            look.pose.armR = 2.4
            look.pose.armL = 0.3
            look.pose.lean = -0.03
            look.pose.earGlow = 1
            look.effects = [.exclaim, .ticks]

        case .dragging:
            look.pose.lift = 12
            look.pose.squash = CGSize(width: 0.95, height: 1.06)
            look.pose.setEyes(Face.open)
            look.pose.setMouth(Face.ooh)
            look.pose.armL = 2.6
            look.pose.armR = 2.6
            look.pose.feetDangle = 1
            look.pose.groundShadow = 0.35
            look.pose.earGlow = 0.8
            look.pose.gazeFollow = 0.5

        case .celebrating:
            look.pose.setEyes(Face.joy)
            look.pose.setMouth(Face.grin)
            look.pose.armL = 2.4
            look.pose.armR = 2.4
            look.pose.earGlow = 1
            look.effects = [.confetti, .sparkles]
        }
        return look
    }

    /// Repeating motion for a state, beyond breathing and prop loops.
    @MainActor
    static func loops(for state: CharacterState, rig: Rig) -> [Loop] {
        switch state {
        case .idle:
            return [Loop(layer: rig.loop, key: "sway",
                         animation: Motion.loop("transform.rotation.z", from: -0.012, to: 0.012, duration: 3.4))]
        case .listening:
            return rig.earLights.map {
                Loop(layer: $0, key: "pulse", animation: Motion.loop("opacity", from: 0.55, to: 1, duration: 0.9))
            }
        case .thinking, .waiting:
            return [Loop(layer: rig.loop, key: "sway",
                         animation: Motion.loop("transform.rotation.z", from: -0.025, to: 0.025, duration: 2.2))]
        case .working(let prop):
            switch prop {
            case .laptop, .none:
                return [rig.armL, rig.armR].enumerated().map { i, arm in
                    Loop(layer: arm.loop, key: "type",
                         animation: Motion.loop("transform.rotation.z", from: -0.1, to: 0.12, duration: 0.17, phase: Double(i) * 0.17))
                }
            case .binoculars:
                let scan = Motion.cycle("transform.translation.x", [0, 0, -14, -14, 0], duration: 4.4,
                                        times: [0, 0.3, 0.45, 0.8, 0.95])
                let turn = Motion.cycle("transform.rotation.z", [0, 0, 0.03, 0.03, 0], duration: 4.4,
                                        times: [0, 0.3, 0.45, 0.8, 0.95])
                return [Loop(layer: rig.scan, key: "scan", animation: scan),
                        Loop(layer: rig.loop, key: "turn", animation: turn)]
            default:
                return []
            }
        case .alert:
            let wave = Motion.loop("transform.rotation.z", from: -0.15, to: 0.35, duration: 0.32)
            return [Loop(layer: rig.armR.loop, key: "wave", animation: wave)]
        case .dragging:
            let top = pt(100, 160)
            func swing(_ angle: CGFloat) -> NSValue {
                let local = top - Canvas.pivot
                return Motion.transform(CGAffineTransform(translationX: local.x, y: local.y).rotated(by: angle)
                    .translatedBy(x: -local.x, y: -local.y))
            }
            let dangle = Motion.cycle("transform", [swing(-0.07), swing(0.07), swing(-0.07)], duration: 1.5)
            let kick = Motion.loop("transform.rotation.z", from: -0.12, to: 0.12, duration: 0.42)
            return [Loop(layer: rig.loop, key: "dangle", animation: dangle),
                    Loop(layer: rig.armL.loop, key: "kick", animation: kick)]
        case .celebrating:
            let hop = Motion.cycle("transform", [
                Motion.transform(.identity),
                Motion.transform(CGAffineTransform(scaleX: 1.06, y: 0.93)),
                Motion.transform(CGAffineTransform(translationX: 0, y: 16).scaledBy(x: 0.96, y: 1.05)),
                Motion.transform(.identity), Motion.transform(.identity),
            ], duration: 0.9, times: [0, 0.12, 0.42, 0.72, 1])
            let cheerL = Motion.loop("transform.rotation.z", from: -0.25, to: 0.15, duration: 0.45)
            let cheerR = Motion.loop("transform.rotation.z", from: 0.25, to: -0.15, duration: 0.45)
            return [Loop(layer: rig.loop, key: "hop", animation: hop),
                    Loop(layer: rig.armL.loop, key: "cheer", animation: cheerL),
                    Loop(layer: rig.armR.loop, key: "cheer", animation: cheerR)]
        default:
            return []
        }
    }

    /// A one-shot flourish when entering a state.
    static func entrance(for state: CharacterState) -> CharacterGesture? {
        switch state {
        case .success, .alert: .hop
        case .error: .shake
        default: nil
        }
    }
}
