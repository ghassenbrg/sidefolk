import Foundation

/// What a surface shows (docs/EXTENSIONS.md › Scenes, D99): a tree of pictures from the pack, text and shapes, with
/// animations Sidefolk runs by itself, areas and keys that send typed moves, and a size up to 720 × 676 points. Coordinates
/// run from the top left of the node's parent; positions are the box's top left.
///
/// ```swift
/// Scene(width: 300, height: 200) {
///     Node.image("cup.png").size(80, 100).at(110, 40).id("cup")
///         .area("pick", label: L("Pick the cup"))
/// }
/// .animating(.move("cup", y: 10, ms: 300))
/// ```
public struct Scene {
    public var width: Double
    public var height: Double
    public var nodes: [Node]
    public var animations: [Anim] = []
    public var keys: [[String: Any]] = []
    public var timers: [[String: Any]] = []
    public var styles: [String: [String: Any]] = [:]
    public var extra: [String: Any] = [:]

    public init(width: Double, height: Double, @SceneBuilder _ nodes: () -> [Node] = { [] }) {
        self.width = width
        self.height = height
        self.nodes = nodes()
    }

    public var json: [String: Any] {
        var out = extra
        out["size"] = [width, height]
        out["nodes"] = nodes.map(\.json)
        if !animations.isEmpty { out["animations"] = animations.map(\.json) }
        if !keys.isEmpty { out["keys"] = keys }
        if !timers.isEmpty { out["timers"] = timers }
        if !styles.isEmpty { out["styles"] = styles }
        return out
    }

    private func with(_ change: (inout Scene) -> Void) -> Scene {
        var copy = self
        change(&copy)
        return copy
    }

    /// Animations, run from when the scene shows.
    public func animating(_ list: Anim...) -> Scene { with { $0.animations += list } }
    public func animating(_ list: [Anim]) -> Scene { with { $0.animations += list } }
    /// A key the scene takes: a letter, a digit, `return`, `space`, `delete`, `left`, `right`, `up`, `down`, `escape`, or a
    /// class of them, `letter` or `digit`. With `area`, it presses that area; otherwise the move is `.key(id:…)`.
    public func key(_ key: String, id: String, area: String? = nil, value: String? = nil, seat: Bool = false, timedFromMs: Double? = nil,
                    always: Bool = false) -> Scene {
        with {
            var k: [String: Any] = ["key": key, "id": id]
            if let area { k["area"] = area }
            if let value { k["value"] = value }
            if seat { k["seat"] = true }
            if let timedFromMs { k["timed_from_ms"] = timedFromMs }
            if always { k["always"] = true }
            $0.keys.append(k)
        }
    }
    /// A clock Sidefolk keeps: when it ends the move is `.timer(id)`. The same id on the next scene keeps it running.
    public func timer(_ id: String, ms: Double) -> Scene { with { $0.timers.append(["id": id, "ms": ms]) } }
    /// Keys named in `Node.style(_:)`, so a large board stays small.
    public func style(_ name: String, _ values: [String: Any]) -> Scene { with { $0.styles[name] = values } }

    public func background(_ color: Color) -> Scene { with { $0.extra["background"] = color.json } }
    /// The frame's second line, beside the extension's name.
    public func title(_ text: String) -> Scene { with { $0.extra["title"] = text } }
    /// Shows Back in the frame; pressing it sends `.back`.
    public func withBack() -> Scene { with { $0.extra["back"] = true } }
    /// Show this scene so long (100–10000 ms), then Sidefolk asks for the next with `.next`. The extension keeps no clock.
    public func after(ms: Int) -> Scene { with { $0.extra["after_ms"] = ms } }
    /// No moves for so long, besides areas marked `always`.
    public func inputAfter(ms: Int) -> Scene { with { $0.extra["input_after_ms"] = ms } }
    /// A node that changed since the last scene eases to its new place (up to 1000 ms).
    public func transition(ms: Int) -> Scene { with { $0.extra["transition_ms"] = ms } }
    /// Never mirrored in a right-to-left language (a picture that reads the same everywhere).
    public func neverMirrored() -> Scene { with { $0.extra["mirror"] = false } }
    /// What VoiceOver hears as it shows.
    public func announcing(_ text: String) -> Scene { with { $0.extra["announce"] = text } }
    /// The companion reacts as the scene shows, from Sidefolk's fixed lists.
    public func react(_ reaction: Reaction) -> Scene { with { $0.extra["react"] = reaction.json } }
    /// It ended: Sidefolk stops its clocks and writes its one Activity row, with how it went for the person in Sidefolk's own words.
    public func over(outcome: String? = nil, tally: [Int]? = nil) -> Scene {
        with {
            $0.extra["over"] = true
            if let outcome { $0.extra["outcome"] = outcome }
            if let tally { $0.extra["tally"] = tally }
        }
    }
    /// Puts the surface away, up to 30 s after it shows.
    public func closing(afterMs: Int = 0) -> Scene {
        with {
            $0.extra["close"] = true
            $0.extra["close_after_ms"] = afterMs
        }
    }
}

@resultBuilder
public enum SceneBuilder {
    public static func buildBlock(_ parts: [Node]...) -> [Node] { parts.flatMap { $0 } }
    public static func buildExpression(_ node: Node) -> [Node] { [node] }
    public static func buildExpression(_ nodes: [Node]) -> [Node] { nodes }
    public static func buildOptional(_ part: [Node]?) -> [Node] { part ?? [] }
    public static func buildEither(first: [Node]) -> [Node] { first }
    public static func buildEither(second: [Node]) -> [Node] { second }
    public static func buildArray(_ parts: [[Node]]) -> [Node] { parts.flatMap { $0 } }
}

/// A colour: from the theme by name, a verdict by name, or a plain value (which may differ in the dark).
public struct Color: @unchecked Sendable {
    public let json: Any
    public static let ink = Color(json: "ink"), inkMuted = Color(json: "ink_muted"), inkFaint = Color(json: "ink_faint")
    public static let surface = Color(json: "surface"), surfaceSunken = Color(json: "surface_sunken"), surfaceRaised = Color(json: "surface_raised")
    public static let line = Color(json: "line"), well = Color(json: "well"), link = Color(json: "link"), clear = Color(json: "clear")
    public static let accent = Color(json: "accent"), onAccent = Color(json: "on_accent"), accentSoft = Color(json: "accent_soft")
    public static let success = Color(json: "success"), successSoft = Color(json: "success_soft")
    public static let warning = Color(json: "warning"), warningSoft = Color(json: "warning_soft"), info = Color(json: "info")
    /// What a result means for the person: never colour alone, always with a symbol or a word.
    public static let win = Color(json: "win"), loss = Color(json: "loss"), draw = Color(json: "draw")
    /// `#RRGGBB` or `#RRGGBBAA`.
    public static func hex(_ value: String) -> Color { Color(json: value) }
    public static func adaptive(light: String, dark: String) -> Color { Color(json: ["light": light, "dark": dark]) }
}

/// One thing in a scene. Build with the statics, place with the modifiers.
public struct Node {
    public var values: [String: Any]
    public init(_ values: [String: Any]) { self.values = values }
    public var json: [String: Any] { values }

    private func with(_ change: (inout [String: Any]) -> Void) -> Node {
        var copy = values
        change(&copy)
        return Node(copy)
    }

    // MARK: Kinds

    /// A picture from the pack, by its path inside the assets folder. `dark`: another one in dark mode. `tint`: drawn as a
    /// stencil in that colour. `fit`: `contain` (the default), `cover` or `fill`.
    public static func image(_ path: String, dark: String? = nil, fit: String = "contain", tint: Color? = nil) -> Node {
        var v: [String: Any] = ["type": "image", "image": path, "fit": fit]
        if let dark { v["dark"] = dark }
        if let tint { v["tint"] = tint.json }
        return Node(v)
    }

    /// Words. `{companion}` in them is the person's companion's name, filled in by Sidefolk when it draws: you never see it.
    /// `weight`: regular, medium, semibold, bold, heavy; `design`: default, rounded, serif, mono; `align`: leading, center,
    /// trailing; `valign`: top, center, bottom. It shrinks to `minScale` if it doesn't fit its box. Give it a size with `.size`.
    public static func text(_ words: String, size: Double = 14, weight: String = "regular", design: String = "default", color: Color = .ink,
                            align: String = "center", valign: String = "center", lines: Int = 1, minScale: Double = 0.7) -> Node {
        Node(["type": "text", "text": words, "size": size, "weight": weight, "design": design, "color": color.json, "align": align, "valign": valign,
              "lines": lines, "min_scale": minScale])
    }

    public static func rect(fill: Color? = nil, stroke: Color? = nil, lineWidth: Double = 1, corner: Double = 0, dash: [Double] = []) -> Node {
        shape("rect", fill, stroke, lineWidth, dash).corner(corner)
    }
    public static func ellipse(fill: Color? = nil, stroke: Color? = nil, lineWidth: Double = 1) -> Node { shape("ellipse", fill, stroke, lineWidth, []) }
    public static func capsule(fill: Color? = nil, stroke: Color? = nil, lineWidth: Double = 1) -> Node { shape("capsule", fill, stroke, lineWidth, []) }
    /// `M x y`, `L x y`, `Q cx cy x y`, `C c1x c1y c2x c2y x y`, `Z`, in the node's box.
    public static func path(_ path: String, fill: Color? = nil, stroke: Color? = nil, lineWidth: Double = 1, dash: [Double] = []) -> Node {
        shape("path", fill, stroke, lineWidth, dash).with { $0["path"] = path }
    }
    private static func shape(_ form: String, _ fill: Color?, _ stroke: Color?, _ width: Double, _ dash: [Double]) -> Node {
        var v: [String: Any] = ["type": "shape", "shape": form, "line_width": width]
        if let fill { v["fill"] = fill.json }
        if let stroke { v["stroke"] = stroke.json }
        if !dash.isEmpty { v["dash"] = dash }
        return Node(v)
    }
    /// A gradient fill, from one point of the box to another (0–1).
    public func gradient(_ colors: [Color], from: (Double, Double) = (0, 0), to: (Double, Double) = (0, 1)) -> Node {
        with { $0["gradient"] = ["colors": colors.map(\.json), "from": [from.0, from.1], "to": [to.0, to.1]] }
    }

    /// An SF Symbol.
    public static func symbol(_ name: String, color: Color = .ink) -> Node { Node(["type": "symbol", "name": name, "color": color.json]) }

    public static func group(@SceneBuilder _ children: () -> [Node]) -> Node { Node(["type": "group", "children": children().map(\.json)]) }

    /// Children one after another; each child needs a size. `align` (`start`, `center`, `end`) across, `pack` along.
    public static func row(gap: Double = 0, align: String = "center", pack: String = "start", @SceneBuilder _ items: () -> [Node]) -> Node {
        Node(["type": "row", "gap": gap, "align": align, "pack": pack, "items": items().map(\.json)])
    }
    public static func column(gap: Double = 0, align: String = "center", pack: String = "start", @SceneBuilder _ items: () -> [Node]) -> Node {
        Node(["type": "column", "gap": gap, "align": align, "pack": pack, "items": items().map(\.json)])
    }
    /// Cells of one size, row by row; a child with no size takes the cell's.
    public static func grid(columns: Int, cell: (Double, Double), gap: (Double, Double) = (0, 0), @SceneBuilder _ items: () -> [Node]) -> Node {
        Node(["type": "grid", "columns": columns, "cell": [cell.0, cell.1], "gap": [gap.0, gap.1], "items": items().map(\.json)])
    }

    /// A keyboard: rows of `KeyCap`, each row centred. A press, on screen or on the keyboard, is `.click(area: name, value: key)`.
    public static func keyset(name: String, rows: [[KeyCap]], key: (Double, Double) = (32, 40), gap: (Double, Double) = (4, 4), corner: Double = 8,
                              size: Double = 16, fill: Color? = nil, ink: Color? = nil, lip: Double = 2, lipColor: Color? = nil, sound: String? = nil) -> Node {
        var v: [String: Any] = ["type": "keyset", "name": name, "rows": rows.map { $0.map(\.json) }, "key": [key.0, key.1], "gap": [gap.0, gap.1],
                                "corner": corner, "size": size, "lip": lip]
        if let fill { v["fill"] = fill.json }
        if let ink { v["ink"] = ink.json }
        if let lipColor { v["lip_color"] = lipColor.json }
        if let sound { v["sound"] = sound }
        return Node(v)
    }

    /// Two faces on one turning plate; `Anim.flip` turns it, in half turns (1 shows the back).
    public static func flip(front: Node, back: Node, showing: String = "front", axis: String = "y") -> Node {
        Node(["type": "flip", "front": front.json, "back": back.json, "showing": showing, "axis": axis])
    }

    /// The person's companion, drawn by Sidefolk in a pose: `idle`, `listening`, `thinking`, `waiting`, `success`, `alert`,
    /// `celebrating`. You place it; you can't read it.
    public static func companion(pose: String = "idle") -> Node { Node(["type": "companion", "pose": pose]) }
    /// The person, by their Mac account's picture or a friendly stand-in. The same rule.
    public static func person() -> Node { Node(["type": "person"]) }

    /// A one-line field typed with the person's input method; Return sends `.entry(id:text:)`.
    public static func entry(name: String, placeholder: String? = nil, max: Int = 40, locked: Bool = false, size: Double = 15) -> Node {
        var v: [String: Any] = ["type": "entry", "name": name, "max": max, "locked": locked, "size": size]
        if let placeholder { v["placeholder"] = placeholder }
        return Node(v)
    }

    /// Time as `m:ss`, counting on (or down) once a second while running, in a text's style.
    public static func clock(seconds: Double, running: Bool = true, down: Bool = false, size: Double = 14, weight: String = "semibold",
                             design: String = "rounded", color: Color = .ink, align: String = "center") -> Node {
        Node(["type": "clock", "seconds": seconds, "running": running, "down": down, "size": size, "weight": weight, "design": design, "color": color.json, "align": align])
    }

    // MARK: Place and look

    public func id(_ id: String) -> Node { with { $0["id"] = id } }
    public func at(_ x: Double, _ y: Double) -> Node { with { $0["x"] = x; $0["y"] = y } }
    public func size(_ w: Double, _ h: Double) -> Node { with { $0["w"] = w; $0["h"] = h } }
    public func style(_ name: String) -> Node { with { $0["style"] = name } }
    /// The point scale and rotation act around, 0–1 in the box; the middle by default.
    public func anchor(_ x: Double, _ y: Double) -> Node { with { $0["anchor"] = [x, y] } }
    public func scale(_ s: Double) -> Node { with { $0["scale"] = s } }
    public func scale(x: Double, y: Double) -> Node { with { $0["sx"] = x; $0["sy"] = y } }
    public func rotate(_ degrees: Double) -> Node { with { $0["rotate"] = degrees } }
    public func opacity(_ o: Double) -> Node { with { $0["opacity"] = o } }
    public func z(_ z: Double) -> Node { with { $0["z"] = z } }
    public func corner(_ r: Double) -> Node { with { $0["corner"] = r } }
    public func clip() -> Node { with { $0["clip"] = true } }
    public func shadow(_ color: Color = .hex("#00000033"), radius: Double = 4, dx: Double = 0, dy: Double = 2) -> Node {
        with { $0["shadow"] = ["color": color.json, "radius": radius, "dx": dx, "dy": dy] }
    }
    /// Its contents never mirror in a right-to-left language.
    public func leftToRight() -> Node { with { $0["ltr"] = true } }
    /// What VoiceOver reads for a thing that can't be pressed.
    public func label(_ words: String) -> Node { with { $0["label"] = words } }
    public func children(@SceneBuilder _ children: () -> [Node]) -> Node { with { $0["children"] = children().map(\.json) } }

    /// Makes this node clickable: the move is `.click(area: id, value: value)`. `label` is what VoiceOver reads and is
    /// required: without words it isn't offered. `hover` and `press` are how it looks meanwhile; `highlight` are other nodes
    /// that take `hover` too; `always` works while an animation holds other moves; `key` is a key that presses it (`seat` by
    /// its place on the keyboard); `sound` plays on the press; `timedFromMs` times the press from a moment of the scene.
    public func area(_ id: String, value: String? = nil, label: String, disabled: Bool = false, hover: AreaLook? = .init(scale: 1.03),
                     press: AreaLook? = .init(scale: 0.97), highlight: [String] = [], always: Bool = false, key: String? = nil, seat: Bool = false,
                     sound: String? = nil, timedFromMs: Double? = nil, drag: Drag? = nil) -> Node {
        with {
            var a: [String: Any] = ["id": id, "label": label, "disabled": disabled, "always": always]
            if let value { a["value"] = value }
            if let hover { a["hover"] = hover.json }
            if let press { a["press"] = press.json }
            if !highlight.isEmpty { a["highlight"] = highlight }
            if let key { a["key"] = key }
            if seat { a["seat"] = true }
            if let sound { a["sound"] = sound }
            if let timedFromMs { a["timed_from_ms"] = timedFromMs }
            if let drag { a["drag"] = drag.json }
            $0["area"] = a
        }
    }
}

/// How an area looks while hovered or pressed.
public struct AreaLook {
    public var scale: Double?, dx: Double?, dy: Double?, opacity: Double?
    public init(scale: Double? = nil, dx: Double? = nil, dy: Double? = nil, opacity: Double? = nil) {
        self.scale = scale
        self.dx = dx
        self.dy = dy
        self.opacity = opacity
    }
    var json: [String: Any] {
        var out: [String: Any] = [:]
        if let scale { out["scale"] = scale }
        if let dx { out["dx"] = dx }
        if let dy { out["dy"] = dy }
        if let opacity { out["opacity"] = opacity }
        return out
    }
}

/// Dragging on an area: over a grid of cells (`.dragCells`), or freely (`.dragPoints`, in canvas points). `ghost` is a node
/// that follows: stretched from the first cell to the one under the pointer, or moved with it.
public struct Drag {
    var json: [String: Any]
    public static func free(ghost: String? = nil) -> Drag { Drag(json: ghost.map { ["mode": "free", "ghost": $0] } ?? ["mode": "free"]) }
    public static func cells(rows: Int, columns: Int, ghost: String? = nil) -> Drag {
        var j: [String: Any] = ["mode": "grid", "rows": rows, "columns": columns]
        if let ghost { j["ghost"] = ghost }
        return Drag(json: j)
    }
}

/// One key of a `Node.keyset`.
public struct KeyCap {
    var json: [String: Any]
    /// `key` is what is sent and typed; `label` what it shows if different (⌫), `spoken` what VoiceOver reads, `typed` the
    /// keyboard's key if different (`delete`, `return`); `fill` and `ink` a mark's colours; `faded` a used key.
    public init(_ key: String, label: String? = nil, spoken: String? = nil, typed: String? = nil, fill: Color? = nil, ink: Color? = nil, faded: Bool = false,
                disabled: Bool = false, width: Double? = nil) {
        var j: [String: Any] = ["key": key, "faded": faded, "disabled": disabled]
        if let label { j["label"] = label }
        if let spoken { j["spoken"] = spoken }
        if let typed { j["typed"] = typed }
        if let fill { j["fill"] = fill.json }
        if let ink { j["ink"] = ink.json }
        if let width { j["w"] = width }
        json = j
    }
}

/// The companion's reaction, from Sidefolk's fixed lists: no words, nothing it can drive. A value off a list is dropped.
public struct Reaction {
    var json: [String: Any]
    /// `move`: think, cheer, celebrate, sulk, bow, nod, shrug, giggle, wince, gasp, tease, sweat, dizzy, ready, shuffle, hop, spin,
    /// wave, dance, accent:wave, accent:hop, accent:spin, accent:bow, pump, flick, roll. `effect`: confetti, sparkles, hearts, question,
    /// exclaim, sweat, stars, frost, flame. `prop`: hat, crown, magnifier, cards, sealed_card, gem, none, balloons(n). `look`: panel, you, away.
    public init(move: String? = nil, effect: String? = nil, prop: String? = nil, look: String? = nil) {
        var j: [String: Any] = [:]
        if let move { j["move"] = move }
        if let effect { j["effect"] = effect }
        if let prop { j["prop"] = prop }
        if let look { j["look"] = look }
        json = j
    }
}

/// An animation Sidefolk runs by itself. Values are where the node ends; it starts from wherever the last step left it.
public struct Anim {
    public var json: [String: Any]
    public init(_ json: [String: Any]) { self.json = json }

    private func with(_ change: (inout [String: Any]) -> Void) -> Anim {
        var copy = json
        change(&copy)
        return Anim(copy)
    }

    /// Any of `x`, `y`, `scale`, `sx`, `sy`, `rotate` (degrees), `opacity`, `flip` (half turns), `z`, reached in `ms`.
    /// `ease`: linear, in, out, in_out, spring.
    public static func to(_ target: String, _ values: [String: Double], ms: Double = 250, ease: String = "in_out") -> Anim {
        Anim(["target": target, "to": values, "ms": ms, "ease": ease])
    }
    public static func move(_ target: String, x: Double? = nil, y: Double? = nil, ms: Double = 250, ease: String = "in_out") -> Anim {
        var v: [String: Double] = [:]
        if let x { v["x"] = x }
        if let y { v["y"] = y }
        return to(target, v, ms: ms, ease: ease)
    }
    public static func scale(_ target: String, _ s: Double, ms: Double = 250, ease: String = "in_out") -> Anim { to(target, ["scale": s], ms: ms, ease: ease) }
    public static func fade(_ target: String, _ o: Double, ms: Double = 250, ease: String = "in_out") -> Anim { to(target, ["opacity": o], ms: ms, ease: ease) }
    public static func rotate(_ target: String, _ degrees: Double, ms: Double = 250, ease: String = "in_out") -> Anim { to(target, ["rotate": degrees], ms: ms, ease: ease) }
    /// To this many half turns: an odd number lands on the back.
    public static func flip(_ target: String, _ halfTurns: Double, ms: Double = 600, ease: String = "out") -> Anim { to(target, ["flip": halfTurns], ms: ms, ease: ease) }
    /// Values at points along the way; `t` from 0 to 1 in each.
    public static func keys(_ target: String, _ frames: [[String: Double]], ms: Double, ease: String = "linear") -> Anim {
        Anim(["target": target, "keys": frames, "ms": ms, "ease": ease])
    }
    /// A picture from the pack after another, as dice tumbling; the last one stays.
    public static func frames(_ target: String, _ paths: [String], stepMs: Double = 70) -> Anim {
        Anim(["target": target, "frames": paths, "frame_ms": stepMs])
    }
    /// One after another.
    public static func sequence(_ steps: [Anim]) -> Anim { Anim(["sequence": steps.map(\.json)]) }
    /// All at once.
    public static func together(_ steps: [Anim]) -> Anim { Anim(["together": steps.map(\.json)]) }
    /// The same step on many nodes, each `stepMs` after the last.
    public static func stagger(_ targets: [String], stepMs: Double = 60, _ values: [String: Double], ms: Double = 250, ease: String = "in_out") -> Anim {
        Anim(["stagger": ["targets": targets, "step_ms": stepMs], "to": values, "ms": ms, "ease": ease])
    }
    public static func wait(ms: Double) -> Anim { Anim(["wait_ms": ms]) }
    /// A sound from the pack at this point.
    public static func sound(_ path: String) -> Anim { Anim(["sound": path]) }
    /// The companion reacts at this point.
    public static func react(_ reaction: Reaction) -> Anim { Anim(["react": reaction.json]) }
    public static func announce(_ words: String) -> Anim { Anim(["announce": words]) }

    /// Two nodes change places along `y` lane: one passing in front (`z` up, a little larger, lower), one behind.
    public static func swap(_ a: String, fromX ax: Double, _ b: String, fromX bx: Double, restY: Double, ms: Double = 400) -> Anim {
        .together([
            .keys(a, [["t": 0, "x": ax, "y": restY, "scale": 1, "z": 2], ["t": 0.5, "x": (ax + bx) / 2, "y": restY + 9, "scale": 1.1, "z": 2],
                      ["t": 1, "x": bx, "y": restY, "scale": 1, "z": 0]], ms: ms, ease: "in_out"),
            .keys(b, [["t": 0, "x": bx, "y": restY, "scale": 1, "z": 1], ["t": 0.5, "x": (ax + bx) / 2, "y": restY - 9, "scale": 0.9, "z": 1],
                      ["t": 1, "x": ax, "y": restY, "scale": 1, "z": 0]], ms: ms, ease: "in_out"),
        ])
    }

    public func delay(ms: Double) -> Anim { with { $0["delay_ms"] = ms } }
    public func repeating(_ count: Int, autoreverse: Bool = false) -> Anim { with { $0["repeat"] = count; $0["autoreverse"] = autoreverse } }
    /// Keeps moving under Reduce Motion, because it is the point (a shuffle). Everything else goes straight to its end.
    public func essential() -> Anim { with { $0["essential"] = true } }
    /// Moves wait until it has played.
    public func blocksInput() -> Anim { with { $0["blocks_input"] = true } }
    /// Named: the next scene sending the same animation under this name carries on instead of starting again.
    public func named(_ id: String) -> Anim { with { $0["id"] = id } }
}
