import Foundation

/// Reads a scene's `animations` into runs of flat curves: what the renderer hands to Core Animation as it stands. Every
/// step's start is worked out here (sequences follow one another, staggered targets step apart), each value's path is
/// complete from its first point to its last, and the node's model is left with the end of the path: so under Reduce
/// Motion, or after the last frame, the end simply shows.
enum SceneTimeline {
    /// One animated span: a target's values over time, with where it starts inside the run.
    private struct Step {
        var target: String
        var start: Double
        var ms: Double
        var ease: SceneEase
        var repeats: Int
        var autoreverse: Bool
        var keys: [(t: Double, values: [SceneProperty: Double])]
        var essential: Bool
        var blocks: Bool
    }

    private struct Compiler {
        var steps: [Step] = []
        var frames: [SceneFrames] = []
        var events: [SceneEvent] = []
        var blockEnd = 0.0
        var stillBlockEnd = 0.0
        var assets: PackAssetReader?

        /// Reads one item at `time`, and returns when it ends. `{sequence}`, `{together}`, `{stagger}`, `{wait_ms}`, an
        /// event (`sound`, `react`, `announce`) or a step on a `target`.
        mutating func item(_ j: JSONValue, at time: Double, depth: Int, inherited: (essential: Bool, blocks: Bool)) throws -> Double {
            guard depth <= 6 else { throw SurfaceScene.refused("nests animations more than 6 deep") }
            let begin = time + SurfaceScene.clamp(j["delay_ms"]?.doubleValue, 0...60_000, 0) / 1000
            guard begin <= SurfaceScene.maxTimeline else { throw SurfaceScene.refused("animates for more than \(Int(SurfaceScene.maxTimeline)) seconds") }
            let flags = (essential: j["essential"]?.boolValue ?? inherited.essential, blocks: j["blocks_input"]?.boolValue ?? inherited.blocks)
            if let list = j["sequence"]?.arrayValue {
                var at = begin
                for item in list { at = try self.item(item, at: at, depth: depth + 1, inherited: flags) }
                return at
            }
            if let list = j["together"]?.arrayValue {
                var end = begin
                for item in list { end = max(end, try self.item(item, at: begin, depth: depth + 1, inherited: flags)) }
                return end
            }
            if let wait = j["wait_ms"]?.doubleValue {
                let end = begin + SurfaceScene.clamp(wait, 0...60_000, 0) / 1000
                note(flags, end, moves: false)
                return end
            }
            var end = begin
            let sound = j["sound"]?.stringValue.flatMap { PackAssets.clean($0).flatMap { PackAssets.kind(of: $0) == .sound ? $0 : nil } }
            let react = SceneReaction.parse(j["react"])
            let announce = GameBoard.line(j["announce"], 200)
            if sound != nil || react != nil || announce != nil {
                guard events.count < SurfaceScene.maxEvents else { throw SurfaceScene.refused("has more than \(SurfaceScene.maxEvents) timed events") }
                events.append(SceneEvent(at: begin, sound: sound, react: react, announce: announce))
            }
            if let frames = j["frames"]?.arrayValue, let target = SceneReader.nodeId(j["target"]) {
                let paths = frames.prefix(64).compactMap { $0.stringValue.flatMap { PackAssets.clean($0) } }.filter { PackAssets.kind(of: $0) == .image && assets?.has($0) ?? true }
                let step = SurfaceScene.clamp(j["frame_ms"]?.doubleValue, 16...5000, 70) / 1000
                let times = paths.indices.map { begin + Double($0) * step }
                self.frames.append(SceneFrames(target: target, times: times, paths: paths, essential: flags.essential))
                end = max(end, begin + Double(paths.count) * step)
                note(flags, end, moves: true)
            }
            let targets: [String]
            var step = 0.0
            if let stagger = j["stagger"] {
                targets = (stagger["targets"]?.arrayValue ?? []).compactMap { SceneReader.nodeId($0) }
                step = SurfaceScene.clamp(stagger["step_ms"]?.doubleValue, 0...5000, 60) / 1000
            } else if let target = SceneReader.nodeId(j["target"]) {
                targets = [target]
            } else {
                targets = []
            }
            guard !targets.isEmpty, j["frames"] == nil else { return end }
            let ms = SurfaceScene.clamp(j["ms"]?.doubleValue, 0...60_000, 250)
            let keys = Self.keys(j)
            guard !keys.isEmpty else { return end }
            let repeats = Int(SurfaceScene.clamp(j["repeat"]?.doubleValue, 1...Double(SurfaceScene.maxRepeats), 1))
            let autoreverse = j["autoreverse"]?.boolValue ?? false
            let ease = j["ease"]?.stringValue.flatMap(SceneEase.init(rawValue:)) ?? .easeInOut
            let lasting = ms / 1000 * Double(repeats) * (autoreverse ? 2 : 1)
            for (i, target) in targets.enumerated() {
                guard steps.count < SurfaceScene.maxSteps else { throw SurfaceScene.refused("has more than \(SurfaceScene.maxSteps) animation steps") }
                let start = begin + step * Double(i)
                steps.append(Step(target: target, start: start, ms: ms / 1000, ease: ease, repeats: repeats, autoreverse: autoreverse, keys: keys,
                                  essential: flags.essential, blocks: flags.blocks))
                end = max(end, start + lasting)
            }
            note(flags, end, moves: true)
            return end
        }

        /// Keeps when moves may be taken: a blocking step holds them, and under Reduce Motion only an essential one still does.
        private mutating func note(_ flags: (essential: Bool, blocks: Bool), _ end: Double, moves: Bool) {
            guard flags.blocks else { return }
            blockEnd = max(blockEnd, end)
            if flags.essential || !moves { stillBlockEnd = max(stillBlockEnd, end) }
        }

        private static func keys(_ j: JSONValue) -> [(t: Double, values: [SceneProperty: Double])] {
            if let to = values(j["to"]), !to.isEmpty { return [(1, to)] }
            return (j["keys"]?.arrayValue ?? []).prefix(32).compactMap { k in
                guard let t = k["t"]?.doubleValue, (0...1).contains(t), let v = values(k), !v.isEmpty else { return nil }
                return (t, v)
            }.sorted { $0.t < $1.t }
        }

        private static func values(_ j: JSONValue?) -> [SceneProperty: Double]? {
            guard let j, j.objectValue != nil else { return nil }
            var out: [SceneProperty: Double] = [:]
            for property in SceneProperty.allCases {
                let key = switch property {
                case .scaleX: "sx"
                case .scaleY: "sy"
                default: property.rawValue
                }
                guard let v = j[key]?.doubleValue, v.isFinite else { continue }
                out[property] = SceneTimeline.bound(v, property)
            }
            return out
        }
    }

    static func bound(_ v: Double, _ p: SceneProperty) -> Double {
        switch p {
        case .x, .y: SurfaceScene.clamp(v, SurfaceScene.coordinates, 0)
        case .scale, .scaleX, .scaleY: SurfaceScene.clamp(v, -16...16, 1)
        case .rotate: SurfaceScene.clamp(v, -36_000...36_000, 0)
        case .opacity: SurfaceScene.clamp(v, 0...1, 1)
        case .flip: SurfaceScene.clamp(v, -400...400, 0)
        case .z: SurfaceScene.clamp(v, -1000...1000, 0)
        }
    }

    /// A top-level item with an `id` is its own run, which keeps going if the next scene sends it unchanged; everything
    /// else goes in one run of its own that plays anew with each scene. `react` is the scene's own reaction, at its start.
    static func compile(_ items: [JSONValue], react: JSONValue?, scene: SurfaceScene, assets: PackAssetReader?) throws -> [SceneRun] {
        guard items.count <= SurfaceScene.maxSteps else { throw SurfaceScene.refused("has more than \(SurfaceScene.maxSteps) animations") }
        var grouped: [(id: String?, items: [JSONValue])] = [(nil, [])]
        for item in items {
            if let id = GameBoard.token(item["id"]) { grouped.append((id, [item])) } else { grouped[0].items.append(item) }
        }
        guard grouped.count <= SurfaceScene.maxRuns else { throw SurfaceScene.refused("has more than \(SurfaceScene.maxRuns) separate animations") }
        var runs: [SceneRun] = []
        var points = 0
        for group in grouped {
            var compiler = Compiler(assets: assets)
            var end = 0.0
            for item in group.items {
                end = max(end, try compiler.item(item, at: 0, depth: 0, inherited: (false, false)))
            }
            if group.id == nil, let reaction = SceneReaction.parse(react) { compiler.events.append(SceneEvent(at: 0, react: reaction)) }
            guard end <= SurfaceScene.maxTimeline else { throw SurfaceScene.refused("animates for more than \(Int(SurfaceScene.maxTimeline)) seconds") }
            let curves = flatten(compiler.steps, scene: scene)
            // A flip is handed over as the samples of its turning, not its points: count what is really built.
            points += curves.reduce(0) { $0 + ($1.property == .flip ? SceneFlipKeys.samples($1) : $1.times.count) }
            guard points <= SurfaceScene.maxPoints else { throw SurfaceScene.refused("animates more than \(SurfaceScene.maxPoints) points") }
            guard !curves.isEmpty || !compiler.frames.isEmpty || !compiler.events.isEmpty else { continue }
            var run = SceneRun(id: group.id, curves: curves, frames: compiler.frames, events: compiler.events.sorted { $0.at < $1.at }, duration: end)
            run.blocks = compiler.blockEnd
            run.stillBlocks = compiler.stillBlockEnd
            runs.append(run)
        }
        return runs
    }

    /// Each target and property as one path: held at its value until a step starts, along the step, repeated or reversed
    /// as asked, then held at its end for the next. A step starting before the last ended cuts it there.
    private static func flatten(_ steps: [Step], scene: SurfaceScene) -> [SceneCurve] {
        var tracks: [String: [SceneProperty: (times: [Double], values: [Double], eases: [SceneEase], essential: Bool)]] = [:]
        for step in steps.sorted(by: { $0.start < $1.start }) {
            guard let node = scene.node(step.target) else { continue }
            let properties = Set(step.keys.flatMap { $0.values.keys })
            for property in properties {
                var track = tracks[step.target]?[property] ?? (times: [0], values: [resting(node, property)], eases: [], essential: false)
                let from: Double
                while let last = track.times.last, last > step.start, track.times.count > 1 {
                    track.times.removeLast()
                    track.values.removeLast()
                    track.eases.removeLast()
                }
                from = track.values.last ?? 0
                if step.start > (track.times.last ?? 0) {
                    track.times.append(step.start)
                    track.values.append(from)
                    track.eases.append(.linear)
                }
                // The keys of one pass: where each value is along it. A property that a key leaves out carries on.
                var path: [(t: Double, v: Double)] = []
                for key in step.keys {
                    if let v = key.values[property] { path.append((key.t, v)) }
                }
                if path.first?.t != 0 { path.insert((0, from), at: 0) }
                var at = step.start
                for pass in 0..<step.repeats {
                    for direction in step.autoreverse ? [false, true] : [false] {
                        let ordered = direction ? path.reversed().map { (t: 1 - $0.t, v: $0.v) } : path
                        for (i, point) in ordered.enumerated() {
                            // A pass starting where the last ended adds no point at its start.
                            if i == 0, pass > 0 || direction, track.times.last == at + point.t * step.ms {
                                if track.values.last != point.v {
                                    track.times.append(at + 0.0001)
                                    track.values.append(point.v)
                                    track.eases.append(.step)
                                }
                                continue
                            }
                            // Its first key says where it starts, from wherever it rested until now.
                            if i == 0, track.times.last == at {
                                if track.values.last != point.v {
                                    track.times.append(at + 0.0001)
                                    track.values.append(point.v)
                                    track.eases.append(.step)
                                }
                                continue
                            }
                            track.times.append(max(at + point.t * step.ms, track.times.last ?? 0))
                            track.values.append(point.v)
                            track.eases.append(property == .z ? .step : step.ease)
                        }
                        at += step.ms
                    }
                }
                track.essential = track.essential || step.essential
                tracks[step.target, default: [:]][property] = track
            }
        }
        return tracks.keys.sorted().flatMap { target in
            tracks[target]!.keys.sorted { $0.rawValue < $1.rawValue }.map { property in
                let t = tracks[target]![property]!
                return SceneCurve(target: target, property: property, times: t.times, values: t.values, eases: t.eases, essential: t.essential)
            }
        }
    }

    static func resting(_ node: SceneNode, _ property: SceneProperty) -> Double {
        switch property {
        case .x: node.x
        case .y: node.y
        case .scale: node.scaleX
        case .scaleX: node.scaleX
        case .scaleY: node.scaleY
        case .rotate: node.rotate
        case .opacity: node.opacity
        case .z: node.z
        case .flip: if case .flip(let f) = node.kind { f.turns } else { 0 }
        }
    }
}

extension SurfaceScene {
    /// The scene as it stands when its animations have ended: what the layers' models hold, so that nothing depends on an
    /// animation finishing. Under Reduce Motion an essential curve still plays, from here to its own end.
    public func settled() -> SurfaceScene {
        var ends: [String: [SceneProperty: Double]] = [:]
        var pictures: [String: String] = [:]
        for run in runs {
            for curve in run.curves { if let last = curve.values.last { ends[curve.target, default: [:]][curve.property] = last } }
            for frames in run.frames { if let last = frames.paths.last { pictures[frames.target] = last } }
        }
        guard !ends.isEmpty || !pictures.isEmpty else { return self }
        func apply(_ list: [SceneNode]) -> [SceneNode] {
            list.map { original in
                var node = original
                if let values = ends[node.id] {
                    for (property, value) in values {
                        switch property {
                        case .x: node.x = value
                        case .y: node.y = value
                        case .scale:
                            node.scaleX = value
                            node.scaleY = value
                        case .scaleX: node.scaleX = value
                        case .scaleY: node.scaleY = value
                        case .rotate: node.rotate = value
                        case .opacity: node.opacity = value
                        case .z: node.z = value
                        case .flip:
                            if case .flip(var f) = node.kind {
                                f.turns = value
                                node.kind = .flip(f)
                            }
                        }
                    }
                }
                if let path = pictures[node.id], case .image(var image) = node.kind {
                    image.path = path
                    image.dark = nil
                    node.kind = .image(image)
                }
                node.children = apply(node.children)
                return node
            }
        }
        var out = self
        out.nodes = apply(nodes)
        return out
    }
}

/// A flip's curve as what is drawn: how far the plate is squashed and which face shows, sampled so it turns evenly.
public struct SceneFlipKeys: Sendable {
    public var times: [Double] = []
    public var squash: [Double] = []
    /// When the face changes, from `t` on.
    public var faceTimes: [(t: Double, back: Bool)] = []

    /// At so many half turns.
    public static func state(_ turns: Double) -> (squash: Double, back: Bool) {
        let whole = Int((turns + 0.5).rounded(.down))
        return (abs(cos(turns * .pi)), !whole.isMultiple(of: 2))
    }

    /// How many keys a curve becomes. Its spans are checked before anything is built, so one turning for ever can't stall the app.
    public static func samples(_ curve: SceneCurve) -> Int {
        var total = 1
        for i in 0..<max(curve.values.count - 1, 0) { total += max(Int(abs(curve.values[i + 1] - curve.values[i]) * 8), 1) }
        return total
    }

    public init(_ curve: SceneCurve) {
        faceTimes = [(0, Self.state(curve.values.first ?? 0).back)]
        for i in 0..<max(curve.times.count - 1, 0) {
            let (t0, t1, v0, v1) = (curve.times[i], curve.times[i + 1], curve.values[i], curve.values[i + 1])
            // Eight samples a half turn reads as a smooth turn; a plain span adds its end only.
            let samples = max(Int(abs(v1 - v0) * 8), 1)
            for s in 0...samples where !(s == 0 && !times.isEmpty) {
                let p = Double(s) / Double(samples)
                let eased = Self.eased(p, curve.eases[i])
                let value = v0 + (v1 - v0) * eased
                let state = Self.state(value)
                let t = t0 + (t1 - t0) * p
                times.append(t)
                squash.append(max(state.squash, 0.02))
                if faceTimes.last?.back != state.back { faceTimes.append((t, state.back)) }
            }
        }
    }

    static func eased(_ p: Double, _ ease: SceneEase) -> Double {
        switch ease {
        case .linear, .step: p
        case .easeIn: p * p
        case .easeOut: 1 - (1 - p) * (1 - p)
        case .easeInOut: p < 0.5 ? 2 * p * p : 1 - 2 * (1 - p) * (1 - p)
        case .spring: min(1 - pow(1 - p, 3) + sin(p * .pi) * 0.12, 1.08)
        }
    }
}
