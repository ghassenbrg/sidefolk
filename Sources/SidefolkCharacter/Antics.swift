import QuartzCore

/// A part of the body an antic moves. Each maps to rig layers whose model transform is always the
/// identity (the gesture layer, arm loops, ear trails, the head's tilt layer), so an antic's keys
/// are the whole transform there: live they become one keyframe animation, offscreen they are set.
enum Part: Hashable, CaseIterable {
    /// Everything, around the floor point (squash and stretch).
    case body
    /// The face's features together; the eyes alone.
    case face, eyes
    /// The head and what rides on it, around the neck (soft companions; the robot has none).
    case head
    case armL, armR
    /// Ears, antennae and sprouts on each side (soft companions).
    case earL, earR

    var mirrored: Part {
        switch self {
        case .armL: .armR
        case .armR: .armL
        case .earL: .earR
        case .earR: .earL
        default: self
        }
    }
}

/// A rig layer an antic moves, and how its `turn` reads there: arms turn by "raise" (outward and
/// up), ears by "outward", both mirrored per side and scaled by how floppy an ear is.
struct Mover {
    let layer: CALayer
    var turn: CGFloat = 1
}

/// One pose of a part: squash and stretch, a nudge and a turn, around the part's own pivot.
struct Key: Equatable {
    var sx: CGFloat = 1
    var sy: CGFloat = 1
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var turn: CGFloat = 0

    static let rest = Key()

    static func squash(_ sx: CGFloat, _ sy: CGFloat, up dy: CGFloat = 0) -> Key { Key(sx: sx, sy: sy, dy: dy) }
    static func turn(_ a: CGFloat) -> Key { Key(turn: a) }
    static func nudge(_ dx: CGFloat, _ dy: CGFloat) -> Key { Key(dx: dx, dy: dy) }

    var mirrored: Key { Key(sx: sx, sy: sy, dx: -dx, dy: dy, turn: -turn) }

    func transform(turnScale: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: dx, y: dy).rotated(by: turn * turnScale).scaledBy(x: sx, y: sy)
    }

    /// Component-wise, the way Core Animation interpolates these simple transforms.
    func lerp(_ other: Key, _ t: CGFloat) -> Key {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        return Key(sx: mix(sx, other.sx), sy: mix(sy, other.sy), dx: mix(dx, other.dx), dy: mix(dy, other.dy),
                   turn: mix(turn, other.turn))
    }
}

extension Key {
    /// Whether `body` (its resting outline, canvas units) stays inside the window under this key,
    /// which turns and stretches it around the floor point.
    func keeps(_ body: CGRect) -> Bool {
        let t = transform(turnScale: 1)
        let room = CGRect(x: 0, y: 0, width: 200, height: 200).insetBy(dx: 2, dy: 2)
        return [pt(body.minX, body.minY), pt(body.maxX, body.minY), pt(body.minX, body.maxY), pt(body.maxX, body.maxY)]
            .allSatisfy { room.contains(Canvas.pivot + ($0 - Canvas.pivot).applying(t)) }
    }

    /// This key, toned down until `body` stays in the window: a tumble curls up smaller, any other
    /// move goes only part of the way.
    func fitted(_ body: CGRect) -> Key {
        guard !body.isNull, !keeps(body) else { return self }
        if abs(turn) > 1 {
            var key = self
            while !key.keeps(body) && key.sx > 0.5 {
                key.sx -= 0.02
                key.sy -= 0.02
            }
            return key
        }
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<12 {
            let mid = (low + high) / 2
            if Key.rest.lerp(self, mid).keeps(body) { low = mid } else { high = mid }
        }
        return Key.rest.lerp(self, low)
    }
}

/// A part's keys over the antic, at `times` (0...1 of its duration; evenly spaced when omitted).
struct Track {
    var part: Part
    var keys: [Key]
    var times: [Double]

    init(_ part: Part, _ keys: [Key], at times: [Double]? = nil) {
        self.part = part
        self.keys = keys
        self.times = times ?? keys.indices.map { Double($0) / Double(max(keys.count - 1, 1)) }
    }

    /// The key at `t` (0...1), eased in and out between keys like the live animation.
    func key(at t: Double) -> Key {
        guard let first = keys.first else { return .rest }
        if t <= times[0] { return first }
        for i in 1..<keys.count where t <= times[i] {
            let span = times[i] - times[i - 1]
            let u = span > 0 ? (t - times[i - 1]) / span : 1
            return keys[i - 1].lerp(keys[i], CGFloat(Ease.inOut(u)))
        }
        return keys[keys.count - 1]
    }
}

/// A face for a moment, on top of the state's own (each body draws it in its own strokes).
enum Mood: Equatable {
    /// > <, squeezed shut (booped).
    case squeeze
    /// ^ ^ and a ω: content (petted).
    case bliss
    /// Eyes shut, mouth wide open.
    case yawn
    /// Wide eyes, a small o, ears up.
    case surprised
    /// Small unfocused eyes, a wobbly mouth.
    case dizzy
    /// Half-closed eyes (lying down, sleepy).
    case drowsy
    /// One eye wider than the other, a small o: what's that?
    case curious
    /// Squinting before a sneeze.
    case sniff
    /// Happy arcs and a grin.
    case joy
    /// One eye squeezed (scratching that side).
    case wince
}

/// A one-shot bit of life: tracks on the rig's motion layers, plus face and gaze beats.
struct Antic {
    var duration: CFTimeInterval
    var tracks: [Track] = []
    /// At each time (0...1), this face; nil goes back to the state's own.
    var faces: [(at: Double, mood: Mood?)] = []
    /// At each time, look this way (-1...1); nil goes back to wherever the pointer had it.
    var looks: [(at: Double, look: CGVector?)] = []
    /// Answers to the person run at the display's pace; idle moments are capped lower.
    var snappy = false
    /// The face beats are mirrored too (asymmetric moods swap eyes).
    var mirrored = false

    var flipped: Antic {
        var copy = self
        copy.tracks = tracks.map { Track($0.part.mirrored, $0.keys.map(\.mirrored), at: $0.times) }
        copy.looks = looks.map { ($0.at, $0.look.map { CGVector(dx: -$0.dx, dy: $0.dy) }) }
        copy.mirrored.toggle()
        return copy
    }

    /// The same moment, toned down wherever this body would leave the window (tall ears, a hat, a
    /// held magnifier): its whole-body keys go only as far as `body`, its resting outline, allows.
    func fitted(to body: CGRect) -> Antic {
        // The parts move too: a nudged head, raised arms and perked ears reach past the outline at rest.
        var dx: CGFloat = 0, dy: CGFloat = 0
        for track in tracks {
            for key in track.keys {
                switch track.part {
                case .head: (dx, dy) = (max(dx, abs(key.dx) + abs(key.turn) * 40), max(dy, key.dy + abs(key.turn) * 20))
                case .armL where key.turn > 1, .armR where key.turn > 1: (dx, dy) = (max(dx, 10), max(dy, 4))
                case .earL where key.turn < 0, .earR where key.turn < 0: dy = max(dy, 3)
                default: break
                }
            }
        }
        let reach = body.isNull ? body : CGRect(x: body.minX - dx, y: body.minY, width: body.width + 2 * dx, height: body.height + dy)
        var copy = self
        copy.tracks = tracks.map { $0.part == .body ? Track(.body, $0.keys.map { $0.fitted(reach) }, at: $0.times) : $0 }
        return copy
    }

    /// The face at `t` (0...1): the last beat at or before it.
    func mood(at t: Double) -> Mood? {
        faces.last { $0.at <= t }?.mood
    }

    /// Whether a look beat applies at `t`, and which.
    func look(at t: Double) -> CGVector?? {
        looks.last { $0.at <= t }.map(\.look)
    }
}

/// Cubic-bezier ease in and out (0.42, 0, 0.58, 1), as `CAMediaTimingFunction(.easeInEaseOut)`.
enum Ease {
    static func inOut(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        // Solve bezier x(s) = x for s by Newton's method, then return y(s).
        func bx(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * 0.42 + 3 * (1 - s) * s * s * 0.58 + s * s * s }
        func by(_ s: Double) -> Double { 3 * (1 - s) * s * s + s * s * s }
        func dbx(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * 0.42 + 6 * (1 - s) * s * (0.58 - 0.42) + 3 * s * s * (1 - 0.58) }
        var s = x
        for _ in 0..<8 {
            let d = dbx(s)
            guard abs(d) > 1e-6 else { break }
            s = min(max(s - (bx(s) - x) / d, 0), 1)
        }
        return by(s)
    }
}

// MARK: The library

/// The antics, as data. Body keys squash around the floor (sy < 1 is down, dy lifts), arm turns
/// raise the hands, ear turns push them outward; everything returns to rest by the end.
enum Antics {
    static func make(_ antic: CharacterAntic) -> Antic {
        switch antic {
        case .earTwitch: earTwitch
        case .stretch: stretch
        case .yawn: yawn
        case .scratch: scratch
        case .hop: hop
        case .wiggle: wiggle
        case .peek: peek
        case .glance: glance
        case .sneeze: sneeze
        case .doubleTake: doubleTake
        case .boop: boop
        case .pet: pet
        case .startle: startle
        case .cheer: cheer
        case .land: land
        case .spin: spin
        case .dizzy: dizzy
        case .wave: wave
        case .dance: dance
        case .bow: bow
        case .nod: nod
        case .giggle: giggle
        case .breathe: breathe
        }
    }

    /// Both ears by the same "outward" values (a flop), or swinging the same way (`swing`).
    private static func ears(_ outward: [CGFloat], at times: [Double]? = nil, swing: Bool = false) -> [Track] {
        [Track(.earL, outward.map { .turn($0) }, at: times),
         Track(.earR, outward.map { .turn(swing ? -$0 : $0) }, at: times)]
    }

    private static func arms(_ raise: [CGFloat], at times: [Double]? = nil) -> [Track] {
        [Track(.armL, raise.map { .turn($0) }, at: times), Track(.armR, raise.map { .turn($0) }, at: times)]
    }

    /// One ear flicks: a rabbit hearing something. Cheap, so it is the most frequent.
    static let earTwitch = Antic(duration: 0.5, tracks: [
        Track(.earR, [.rest, .turn(0.24), .turn(-0.08), .turn(0.12), .turn(-0.03), .rest], at: [0, 0.16, 0.38, 0.58, 0.8, 1]),
    ])

    /// Reaches up tall with both arms, eyes shut, then lets go with a little shake.
    static let stretch = Antic(duration: 2.4, tracks: [
        Track(.body, [.rest, .squash(1.04, 0.95), .squash(0.93, 1.09, up: 2), .squash(0.93, 1.09, up: 2), .squash(1.05, 0.95),
                      .squash(0.99, 1.01), .rest], at: [0, 0.12, 0.35, 0.65, 0.8, 0.9, 1]),
        Track(.head, [.rest, .rest, .nudge(0, 2), .nudge(0, 2), .rest, .rest], at: [0, 0.12, 0.35, 0.65, 0.8, 1]),
    ] + arms([0, -0.2, 1.6, 1.7, 0.3, 0], at: [0, 0.12, 0.35, 0.65, 0.82, 1])
      + ears([0, 0, -0.12, -0.12, 0.3, -0.1, 0], at: [0, 0.12, 0.35, 0.65, 0.78, 0.9, 1]),
    faces: [(0.15, .bliss), (0.8, nil)])

    /// Mouth wide, head back, one paw to the mouth, then a sleepy blink.
    static let yawn = Antic(duration: 2.6, tracks: [
        Track(.body, [.rest, .squash(0.98, 1.04, up: 1), .squash(0.98, 1.05, up: 1), .squash(1.03, 0.97), .rest],
              at: [0, 0.3, 0.6, 0.8, 1]),
        Track(.head, [.rest, Key(dy: 2, turn: 0.04), Key(dy: 2.5, turn: 0.05), .turn(-0.02), .rest], at: [0, 0.3, 0.6, 0.8, 1]),
        Track(.armR, [.rest, .turn(-1.2), .turn(-1.3), .turn(-0.3), .rest], at: [0, 0.3, 0.6, 0.8, 1]),
    ] + ears([0, 0.1, 0.14, 0.05, 0], at: [0, 0.3, 0.6, 0.8, 1]),
    faces: [(0.12, .yawn), (0.72, .drowsy), (0.94, nil)])

    /// Head tilted, a paw up to the cheek scratching fast, that ear twitching along, one eye shut.
    static let scratch = Antic(duration: 2.0, tracks: [
        Track(.head, [.rest, .turn(-0.08), .turn(-0.08), .rest], at: [0, 0.15, 0.85, 1]),
        Track(.body, [.rest, .turn(-0.02), .turn(-0.02), .rest], at: [0, 0.15, 0.85, 1]),
        Track(.armR, [.rest, .turn(1.9), .turn(2.08), .turn(1.9), .turn(2.08), .turn(1.9), .turn(2.08), .turn(1.9), .rest],
              at: [0, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 1]),
        Track(.earR, [.rest, .turn(0.14), .turn(-0.06), .turn(0.14), .turn(-0.06), .turn(0.14), .rest],
              at: [0, 0.3, 0.42, 0.54, 0.66, 0.78, 1]),
    ], faces: [(0.18, .wince), (0.84, nil)])

    /// A small happy hop: crouch, up, land, ears flopping.
    static let hop = Antic(duration: 0.75, tracks: [
        Track(.body, [.rest, .squash(1.08, 0.9), .squash(0.97, 1.03, up: 11), .squash(0.98, 1.02, up: 10), .squash(1.07, 0.92), .rest],
              at: [0, 0.15, 0.42, 0.55, 0.8, 1]),
    ] + arms([0, -0.1, 0.6, 0.5, 0, 0], at: [0, 0.15, 0.42, 0.55, 0.8, 1])
      + ears([0, -0.1, -0.05, 0.1, 0.38, -0.12, 0], at: [0, 0.15, 0.42, 0.6, 0.8, 0.9, 1]),
    faces: [(0.1, .joy), (0.95, nil)])

    /// A shimmy side to side.
    static let wiggle = Antic(duration: 1.2, tracks: [
        Track(.body, [.rest, .turn(0.05), .turn(-0.05), .turn(0.045), .turn(-0.04), .turn(0.02), .rest]),
    ] + ears([0, -0.12, 0.12, -0.1, 0.08, -0.03, 0], swing: true),
    faces: [(0.05, .joy), (0.95, nil)])

    /// Leans toward what you are doing (to its left; flipped toward the other side) and looks.
    static let peek = Antic(duration: 3.2, tracks: [
        Track(.body, [.rest, Key(dx: 5, turn: -0.06), Key(dx: 5, turn: -0.06), .rest], at: [0, 0.2, 0.8, 1]),
        Track(.head, [.rest, .turn(-0.1), .turn(-0.07), .turn(-0.1), .rest], at: [0, 0.2, 0.5, 0.8, 1]),
    ] + ears([0, -0.14, -0.14, 0], at: [0, 0.2, 0.8, 1]),
    faces: [(0.15, .curious), (0.85, nil)],
    looks: [(0.05, CGVector(dx: 1, dy: -0.25)), (0.88, nil)])

    /// Only the eyes, toward something (flipped for the other side); Life aims it.
    static let glance = Antic(duration: 2.6, looks: [(0, CGVector(dx: 1, dy: -0.2)), (1, nil)])

    /// Ah… ah… CHOO: head back and squinting, then a sudden forward squash, ears flung out.
    static let sneeze = Antic(duration: 1.8, tracks: [
        Track(.body, [.rest, .squash(0.98, 1.03, up: 1), .squash(0.97, 1.05, up: 2), .squash(1.12, 0.86), .squash(0.98, 1.02), .rest],
              at: [0, 0.3, 0.55, 0.62, 0.8, 1]),
        Track(.head, [.rest, Key(dy: 1.5, turn: 0.03), Key(dy: 3, turn: 0.05), Key(dy: -3, turn: -0.04), .turn(0.02), .rest],
              at: [0, 0.3, 0.55, 0.62, 0.8, 1]),
    ] + ears([0, -0.05, -0.1, 0.45, -0.15, 0], at: [0, 0.3, 0.55, 0.64, 0.8, 1]),
    faces: [(0.1, .sniff), (0.58, .squeeze), (0.85, nil)], snappy: true)

    /// Looks away, back, away again… then snaps back wide-eyed with a tiny jump.
    static let doubleTake = Antic(duration: 1.8, tracks: [
        Track(.body, [.rest, .rest, .squash(0.95, 1.06, up: 5), .squash(1.03, 0.97), .rest], at: [0, 0.55, 0.64, 0.78, 1]),
    ] + ears([0, 0, -0.25, -0.2, 0], at: [0, 0.55, 0.64, 0.85, 1]),
    faces: [(0.56, .surprised), (0.95, nil)],
    looks: [(0, CGVector(dx: -0.9, dy: 0)), (0.3, CGVector(dx: 0, dy: 0)), (0.42, CGVector(dx: -0.9, dy: 0)),
            (0.56, CGVector(dx: 0.9, dy: 0.15)), (1, nil)], snappy: true)

    // MARK: Answers

    /// Clicked: squashed by the poke, eyes squeezed, ears flopping.
    static let boop = Antic(duration: 0.55, tracks: [
        Track(.body, [.rest, .squash(1.1, 0.88), .squash(0.96, 1.05), .squash(1.02, 0.98), .rest], at: [0, 0.18, 0.45, 0.7, 1]),
        Track(.face, [.rest, .nudge(0, -2), .nudge(0, 1), .rest], at: [0, 0.18, 0.45, 1]),
    ] + ears([0, 0.25, -0.12, 0.05, 0], at: [0, 0.2, 0.5, 0.75, 1]),
    faces: [(0, .squeeze), (0.75, nil)], snappy: true)

    /// Stroked: leans into the hand (on its left; flipped for the other side), ears back, content.
    static let pet = Antic(duration: 1.8, tracks: [
        Track(.body, [.rest, Key(sx: 1.03, sy: 0.97, turn: 0.04), Key(sx: 1.03, sy: 0.97, turn: 0.025),
                      Key(sx: 1.03, sy: 0.97, turn: 0.045), Key(sx: 1.02, sy: 0.98, turn: 0.03), .rest],
              at: [0, 0.18, 0.4, 0.6, 0.8, 1]),
        Track(.head, [.rest, .turn(0.08), .turn(0.05), .turn(0.08), .turn(0.05), .rest], at: [0, 0.18, 0.4, 0.6, 0.8, 1]),
    ] + ears([0, 0.3, 0.34, 0.3, 0.34, 0], at: [0, 0.18, 0.4, 0.6, 0.8, 1]),
    faces: [(0, .bliss), (0.9, nil)], snappy: true)

    /// A notification arrived: a jump, tall and wide-eyed, ears straight up.
    static let startle = Antic(duration: 0.9, tracks: [
        Track(.body, [.rest, .squash(0.93, 1.07, up: 4), .squash(0.96, 1.04, up: 4), .squash(1.08, 0.92), .rest],
              at: [0, 0.12, 0.35, 0.6, 1]),
    ] + arms([0, 1.4, 1.2, 0.2, 0], at: [0, 0.12, 0.35, 0.6, 1])
      + ears([0, -0.3, -0.25, 0.15, 0], at: [0, 0.12, 0.35, 0.65, 1]),
    faces: [(0, .surprised), (0.85, nil)], snappy: true)

    /// Something got done: two hops with the arms up.
    static let cheer = Antic(duration: 1.5, tracks: [
        Track(.body, [.rest, .squash(1.06, 0.92), .squash(0.97, 1.03, up: 11), .squash(1.06, 0.93), .squash(0.97, 1.03, up: 10),
                      .squash(1.05, 0.94), .rest], at: [0, 0.1, 0.3, 0.5, 0.7, 0.88, 1]),
    ] + arms([0, 2.0, 2.2, 1.9, 2.2, 1.0, 0], at: [0, 0.1, 0.3, 0.5, 0.7, 0.88, 1])
      + ears([0, 0, -0.1, 0.35, -0.05, 0.3, 0], at: [0, 0.1, 0.3, 0.5, 0.7, 0.88, 1]),
    faces: [(0, .joy), (0.92, nil)], snappy: true)

    /// Dropped onto the floor: squash on impact, overshoot, settle.
    static let land = Antic(duration: 0.6, tracks: [
        Track(.body, [.rest, .squash(1.14, 0.84), .squash(0.96, 1.05), .squash(1.02, 0.98), .rest], at: [0, 0.15, 0.45, 0.7, 1]),
    ] + arms([0, 0.5, -0.1, 0], at: [0, 0.15, 0.5, 1])
      + ears([0, 0.45, -0.18, 0.08, 0], at: [0, 0.18, 0.48, 0.72, 1]),
    snappy: true)

    /// Tossed: one tumble around its middle while it flies, curled up a little and lifted so its
    /// ears stay in the window upside down.
    static let spin: Antic = {
        let steps = 12, middle: CGFloat = 62
        let keys = (0...steps).map { i -> Key in
            let a = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let curl = sin(a / 2)
            // Turning around the middle = turning around the feet, then moving back.
            return Key(sx: 1 - 0.12 * curl, sy: 1 - 0.12 * curl, dx: middle * sin(a), dy: middle * (1 - cos(a)) + 34 * curl, turn: a)
        }
        // The last key turns a full circle: the same transform as rest, reached going forward.
        return Antic(duration: 0.7, tracks: [Track(.body, keys)] + ears([0, 0.4, 0.4, 0.4, 0]),
                     faces: [(0, .squeeze), (0.95, nil)], snappy: true)
    }()

    /// After a toss: wobbling, eyes rolling, head swaying.
    static let dizzy: Antic = {
        let circle = (0...16).map { i -> Key in
            let a = Double(i) / 8 * .pi
            let fade = i == 0 || i == 16 ? 0 : 1.0
            return .nudge(CGFloat(cos(a) * 2.6 * fade), CGFloat(sin(a) * 2 * fade))
        }
        return Antic(duration: 2.2, tracks: [
            Track(.body, [.rest, .turn(0.06), .turn(-0.05), .turn(0.04), .turn(-0.03), .turn(0.015), .rest]),
            Track(.head, [.rest, .turn(-0.06), .turn(0.06), .turn(-0.045), .turn(0.03), .rest]),
            Track(.eyes, circle),
        ] + ears([0, 0.15, -0.15, 0.12, -0.08, 0.04, 0], swing: true),
        faces: [(0, .dizzy), (0.9, nil)])
    }()

    // MARK: Tricks and play (D44)

    /// Hello! One paw up, waving side to side, head tilted, a big smile.
    static let wave = Antic(duration: 1.7, tracks: [
        Track(.armR, [.rest, .turn(2.1), .turn(2.5), .turn(2.0), .turn(2.5), .turn(2.0), .turn(2.4), .rest],
              at: [0, 0.18, 0.32, 0.46, 0.6, 0.74, 0.86, 1]),
        Track(.head, [.rest, .turn(-0.07), .turn(-0.07), .rest], at: [0, 0.18, 0.86, 1]),
        Track(.body, [.rest, .squash(0.98, 1.02, up: 1), .squash(0.98, 1.02, up: 1), .rest], at: [0, 0.18, 0.86, 1]),
    ] + ears([0, -0.12, 0.05, -0.1, 0.05, -0.1, 0], at: [0, 0.18, 0.32, 0.46, 0.6, 0.8, 1]),
    faces: [(0.05, .joy), (0.92, nil)], snappy: true)

    /// A little dance: bouncing on the beat, swaying side to side, paws up in turn, a twirl of the ears.
    static let dance: Antic = {
        let beats = 8
        let times = (0...beats).map { Double($0) / Double(beats) }
        let body = times.indices.map { i -> Key in
            guard i > 0, i < beats else { return .rest }
            let side: CGFloat = i.isMultiple(of: 2) ? -1 : 1
            return i.isMultiple(of: 2) ? Key(sx: 1.05, sy: 0.94, turn: 0.06 * side) : Key(sx: 0.97, sy: 1.03, dy: 6, turn: 0.06 * side)
        }
        let left = times.indices.map { i -> Key in i == 0 || i == beats ? .rest : .turn(i % 4 == 1 ? 2.0 : i % 4 == 3 ? 0.4 : 1.1) }
        let right = times.indices.map { i -> Key in i == 0 || i == beats ? .rest : .turn(i % 4 == 3 ? 2.0 : i % 4 == 1 ? 0.4 : 1.1) }
        let ears = times.indices.map { i -> CGFloat in i == 0 || i == beats ? 0 : (i.isMultiple(of: 2) ? 0.2 : -0.15) }
        return Antic(duration: 3.2, tracks: [Track(.body, body, at: times), Track(.armL, left, at: times), Track(.armR, right, at: times),
                                             Track(.head, times.indices.map { i in i == 0 || i == beats ? .rest : .turn(i.isMultiple(of: 2) ? 0.06 : -0.06) },
                                                   at: times)]
            + Self.ears(ears, at: times, swing: true),
            faces: [(0.04, .joy), (0.95, nil)], snappy: true)
    }()

    /// A deep, polite bow: down low, eyes closed, a pause, and back up.
    static let bow = Antic(duration: 1.9, tracks: [
        Track(.body, [.rest, .squash(1.06, 0.86), .squash(1.06, 0.86), .squash(0.98, 1.02), .rest], at: [0, 0.3, 0.62, 0.82, 1]),
        Track(.head, [.rest, Key(dy: -6, turn: 0), Key(dy: -6, turn: 0), .rest], at: [0, 0.3, 0.62, 1]),
        Track(.face, [.rest, .nudge(0, -4), .nudge(0, -4), .rest], at: [0, 0.3, 0.62, 1]),
    ] + arms([0, -0.3, -0.3, 0.2, 0], at: [0, 0.3, 0.62, 0.82, 1])
      + ears([0, 0.12, 0.12, -0.06, 0], at: [0, 0.3, 0.62, 0.84, 1]),
    faces: [(0.22, .bliss), (0.78, .joy), (0.96, nil)], snappy: true)

    /// Yes, yes: two small nods.
    static let nod = Antic(duration: 1.0, tracks: [
        Track(.head, [.rest, .nudge(0, -3), .rest, .nudge(0, -3), .rest], at: [0, 0.22, 0.45, 0.68, 1]),
        Track(.face, [.rest, .nudge(0, -3), .rest, .nudge(0, -3), .rest], at: [0, 0.22, 0.45, 0.68, 1]),
    ] + ears([0, 0.08, 0, 0.08, 0], at: [0, 0.22, 0.45, 0.68, 1]),
    faces: [(0.05, .joy), (0.9, nil)], snappy: true)

    /// Tickled: it squirms and laughs, eyes squeezed, shaking from side to side.
    static let giggle: Antic = {
        let steps = 10
        let times = (0...steps).map { Double($0) / Double(steps) }
        let body = times.indices.map { i -> Key in
            i == 0 || i == steps ? .rest : Key(sx: 1.03, sy: 0.97, dx: i.isMultiple(of: 2) ? -2.5 : 2.5, turn: i.isMultiple(of: 2) ? -0.035 : 0.035)
        }
        return Antic(duration: 1.4, tracks: [Track(.body, body, at: times)]
            + arms(times.indices.map { i in i == 0 || i == steps ? 0 : (i.isMultiple(of: 2) ? -0.5 : -0.35) }, at: times)
            + ears(times.indices.map { i in i == 0 || i == steps ? 0 : (i.isMultiple(of: 2) ? 0.22 : -0.12) }, at: times, swing: true),
            faces: [(0, .squeeze), (0.25, .joy), (0.5, .squeeze), (0.75, .joy), (0.95, nil)], snappy: true)
    }()

    /// One slow breath for the breathing exercise: in for four seconds (growing a little, ears rising, eyes
    /// closed), held for one, out for six. The only moment longer than a few seconds: the person asked for it.
    static let breathe = Antic(duration: 11, tracks: [
        Track(.body, [.rest, .squash(1.05, 1.07, up: 2), .squash(1.05, 1.07, up: 2), .squash(0.99, 0.99), .rest],
              at: [0, 0.36, 0.45, 0.9, 1]),
        Track(.head, [.rest, .nudge(0, 2), .nudge(0, 2), .rest], at: [0, 0.36, 0.45, 1]),
    ] + arms([0, 0.5, 0.5, 0, 0], at: [0, 0.36, 0.45, 0.9, 1])
      + ears([0, -0.18, -0.18, 0.06, 0], at: [0, 0.36, 0.45, 0.9, 1]),
    faces: [(0.04, .bliss), (0.97, nil)])
}
