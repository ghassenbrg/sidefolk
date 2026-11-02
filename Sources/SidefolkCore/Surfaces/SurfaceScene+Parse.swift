import Foundation

// Reading a scene: every value checked and clipped, each cap counted across the whole tree. A wrong value is dropped and
// noted for the author; going past a cap refuses the whole scene, since half a board would mislead.

extension SurfaceScene {
    public static func parse(_ json: JSONValue, assets: PackAssetReader? = nil, within limit: SceneSize? = nil) throws -> SurfaceScene {
        guard json.jsonString.utf8.count <= maxBytes else { throw refused("is larger than 64 KB") }
        guard let object = json.objectValue, let raw = object["nodes"]?.arrayValue else { throw UserFacingError("That isn't a surface's scene.") }
        let cap = limit ?? SceneSize(width: SurfaceLimits.maxWidth, height: SurfaceLimits.maxHeight)
        let size = json["size"]?.arrayValue?.compactMap(\.doubleValue) ?? []
        let box = SceneSize(width: clamp(size.first, 40...cap.width, cap.width), height: clamp(size.count > 1 ? size[1] : nil, 40...cap.height, cap.height))

        var reader = SceneReader(assets: assets)
        if let styles = object["styles"]?.objectValue {
            guard styles.count <= maxStyles else { throw refused("has more than \(maxStyles) styles") }
            reader.styles = styles
        }
        var scene = SurfaceScene(size: box)
        for (i, item) in raw.enumerated() {
            if let node = try reader.node(item, path: "n\(i)", depth: 0, parent: box) { scene.nodes.append(node) }
        }
        scene.background = SceneReader.color(json["background"])
        scene.title = GameBoard.line(json["title"], 60)
        scene.back = json["back"]?.boolValue ?? false
        scene.over = json["over"]?.boolValue ?? false
        scene.close = json["close"]?.boolValue ?? false
        scene.closeAfter = clamp(json["close_after_ms"]?.doubleValue, 0...30_000, 0) / 1000
        scene.inputAfter = clamp(json["input_after_ms"]?.doubleValue, 0...60_000, 0) / 1000
        scene.after = json["after_ms"]?.doubleValue.flatMap { (100...10_000).contains($0) ? $0 / 1000 : nil }
        scene.afterStill = json["after_still_ms"]?.doubleValue.flatMap { (100...10_000).contains($0) ? $0 / 1000 : nil }
        scene.speaker = json["speaker"]?.stringValue.flatMap { $0.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil ? $0 : nil }
        scene.transition = clamp(json["transition_ms"]?.doubleValue, 0...1000, 0) / 1000
        scene.mirrors = json["mirror"]?.boolValue ?? true
        scene.announce = GameBoard.line(json["announce"], 200)
        scene.outcome = json["outcome"]?.stringValue.flatMap(GameVerdict.init(rawValue:))
        if let t = json["tally"]?.arrayValue?.compactMap(\.intValue), t.count == 2 { scene.tally = t.map { min(max($0, 0), 99_999) } }

        scene.timers = (json["timers"]?.arrayValue ?? []).compactMap { t in
            guard let id = GameBoard.token(t["id"]), let ms = t["ms"]?.doubleValue, (100...3_600_000).contains(ms) else { return nil }
            return SceneTimer(id: id, seconds: ms / 1000)
        }
        guard scene.timers.count <= maxTimers else { throw refused("has more than \(maxTimers) timers") }

        for item in json["keys"]?.arrayValue ?? [] {
            if let key = SceneReader.key(item) { reader.keys.append(key) } else { reader.notes.append("A key was left out.") }
        }
        guard reader.keys.count <= maxKeys else { throw refused("takes more than \(maxKeys) keys") }
        scene.keys = reader.keys
        scene.notes = reader.notes

        scene.runs = try SceneTimeline.compile(json["animations"]?.arrayValue ?? [], react: json["react"], scene: scene, assets: assets)
        scene.keepOnlyKnownTargets()
        guard scene.drawnBytes <= maxDrawnBytes else { throw refused("draws more than \(maxDrawnBytes / 1024 / 1024) MiB of pictures and words at once") }
        return scene
    }

    static func refused(_ why: String) -> UserFacingError { UserFacingError(verbatim: "The extension's scene \(why).") }

    static func clamp(_ value: Double?, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// The areas of the scene, with where they sit in the tree dropped: what a move can be offered by.
    public var areas: [SceneArea] {
        var out: [SceneArea] = []
        func visit(_ node: SceneNode) {
            if let area = node.area { out.append(area) }
            node.children.forEach(visit)
        }
        nodes.forEach(visit)
        return out
    }

    /// What the bitmaps of this scene take at twice their size, four bytes a pixel. A picture counts once, at its largest; tinted, it
    /// is a copy per node. Counted from the sizes the scene asks for, on the reader's side, so a scene past it is simply refused.
    public var drawnBytes: Int {
        func bitmap(_ width: Double, _ height: Double) -> Double { width * height * 16 }
        var total = 0.0
        var pictures: [String: Double] = [:]
        func picture(_ path: String, _ bytes: Double) { pictures[path] = max(pictures[path] ?? 0, bytes) }
        func visit(_ node: SceneNode) {
            let own = bitmap(node.width, node.height)
            switch node.kind {
            case .group, .flip, .entry, .scroll: break
            case .text, .clock, .symbol, .companion, .person: total += own
            case .shape(let shape): if shape.gradient != nil { total += own }
            case .image(let image):
                if image.tint != nil { total += own }
                picture(image.path, own)
                if let dark = image.dark { picture(dark, own) }
            }
            node.children.forEach(visit)
        }
        nodes.forEach(visit)
        for run in runs {
            for frames in run.frames {
                let own = self.node(frames.target).map { bitmap($0.width, $0.height) } ?? 0
                for path in frames.paths { picture(path, own) }
            }
        }
        return Int(min(total + pictures.values.reduce(0, +), Double(Int.max / 2)))
    }

    public func node(_ id: String) -> SceneNode? {
        func find(_ list: [SceneNode]) -> SceneNode? {
            for node in list {
                if node.id == id { return node }
                if let inner = find(node.children) { return inner }
            }
            return nil
        }
        return find(nodes)
    }

    public var entries: [SceneEntry] {
        var out: [SceneEntry] = []
        func visit(_ node: SceneNode) {
            if case .entry(let e) = node.kind { out.append(e) }
            node.children.forEach(visit)
        }
        nodes.forEach(visit)
        return out
    }

    /// An animation naming a node that isn't there does nothing; a highlight or a ghost likewise.
    private mutating func keepOnlyKnownTargets() {
        var known = Set<String>()
        func visit(_ node: SceneNode) {
            known.insert(node.id)
            node.children.forEach(visit)
        }
        nodes.forEach(visit)
        for i in runs.indices {
            runs[i].curves.removeAll { !known.contains($0.target) }
            runs[i].frames.removeAll { !known.contains($0.target) }
        }
    }

    /// How long from the scene's showing until moves are taken: the longest hold of its runs and `input_after_ms`.
    public func inputOpens(reduceMotion: Bool) -> Double {
        max(inputAfter, runs.map { reduceMotion ? $0.stillBlocks : $0.blocks }.max() ?? 0)
    }
}

/// What a surface may ask for and how it is framed, kept in one place for the validator, the reader and the panel.
public enum SurfaceLimits {
    /// The canvas: with the frame's header (`SurfacePolicy.headerHeight`) the panel stays under about 720 pt.
    public static let maxWidth = 720.0
    public static let maxHeight = 676.0
    public static let minSide = 120.0
    public static let maxOverlayWidth = 460.0
    public static let maxOverlayHeight = 420.0
}

/// One pass over the tree, keeping the counts.
struct SceneReader {
    let assets: PackAssetReader?
    var styles: [String: JSONValue] = [:]
    var keys: [SceneKey] = []
    var notes: [String] = []
    private var seen = Set<String>()
    private var nodes = 0, images = 0, areas = 0, people = 0, entries = 0, clocks = 0, text = 0
    private var distinct = Set<String>()

    init(assets: PackAssetReader?) {
        self.assets = assets
    }

    /// `path` names a node that gives no id, so the same place keeps the same id from scene to scene.
    mutating func node(_ raw: JSONValue, path: String, depth: Int, parent: SceneSize) throws -> SceneNode? {
        guard depth < SurfaceScene.maxDepth else { throw SurfaceScene.refused("is nested more than \(SurfaceScene.maxDepth) deep") }
        let j = merged(raw)
        nodes += 1
        guard nodes <= SurfaceScene.maxNodes else { throw SurfaceScene.refused("has more than \(SurfaceScene.maxNodes) nodes") }

        var id = Self.nodeId(j["id"]) ?? path
        if seen.contains(id) {
            notes.append("Two nodes share the id \(id).")
            id = path
        }
        seen.insert(id)

        let width = SurfaceScene.clamp(j["w"]?.doubleValue, 0...2000, 0), height = SurfaceScene.clamp(j["h"]?.doubleValue, 0...2000, 0)
        guard let kind = try kind(j, id: id, depth: depth, parent: parent) else { return nil }
        var node = SceneNode(id: id, kind: kind)
        if case .scroll = kind { node.clips = true }
        node.width = width
        node.height = height
        // A plain group with no size is as large as its parent; a helper works its size out from what it holds.
        if width == 0, height == 0, ["group", nil].contains(j["type"]?.stringValue) { (node.width, node.height) = (parent.width, parent.height) }
        node.x = SurfaceScene.clamp(j["x"]?.doubleValue, SurfaceScene.coordinates, 0)
        node.y = SurfaceScene.clamp(j["y"]?.doubleValue, SurfaceScene.coordinates, 0)
        if let a = j["anchor"]?.arrayValue?.compactMap(\.doubleValue), a.count == 2 {
            node.anchorX = SurfaceScene.clamp(a[0], 0...1, 0.5)
            node.anchorY = SurfaceScene.clamp(a[1], 0...1, 0.5)
        }
        let scale = SurfaceScene.clamp(j["scale"]?.doubleValue, 0...16, 1)
        node.scaleX = SurfaceScene.clamp(j["sx"]?.doubleValue, -16...16, scale)
        node.scaleY = SurfaceScene.clamp(j["sy"]?.doubleValue, -16...16, scale)
        node.rotate = SurfaceScene.clamp(j["rotate"]?.doubleValue, -36_000...36_000, 0)
        node.opacity = SurfaceScene.clamp(j["opacity"]?.doubleValue, 0...1, 1)
        node.z = SurfaceScene.clamp(j["z"]?.doubleValue, -1000...1000, 0)
        node.clips = node.clips || j["clip"]?.boolValue == true
        node.corner = SurfaceScene.clamp(j["corner"]?.doubleValue, 0...1000, 0)
        node.ltr = j["ltr"]?.boolValue ?? false
        node.label = GameBoard.line(j["label"], 120)
        if let s = j["shadow"] {
            node.shadow = SceneShadow(color: Self.color(s["color"]) ?? .rgba(0x0000_0033), radius: SurfaceScene.clamp(s["radius"]?.doubleValue, 0...40, 4),
                                      dx: SurfaceScene.clamp(s["dx"]?.doubleValue, -40...40, 0), dy: SurfaceScene.clamp(s["dy"]?.doubleValue, -40...40, 0))
        }
        let box = SceneSize(width: node.width, height: node.height)
        switch j["type"]?.stringValue {
        case "group", "image", "text", "shape", "symbol", "companion", "person", "clock", "entry", "scroll", nil:
            for (i, child) in (j["children"]?.arrayValue ?? []).enumerated() {
                if let c = try self.node(child, path: "\(id).\(i)", depth: depth + 1, parent: box) { node.children.append(c) }
            }
        case "flip":
            for (i, face) in [j["front"], j["back"]].enumerated() {
                let c = try face.flatMap { try self.node($0, path: "\(id).\(i)", depth: depth + 1, parent: box) }
                var plate = c ?? SceneNode(id: "\(id).\(i)", kind: .group)
                if plate.width == 0 || plate.height == 0 { (plate.width, plate.height) = (box.width, box.height) }
                node.children.append(plate)
            }
        case "row", "column": node.children = try stack(j, id: id, depth: depth, node: &node)
        case "grid": node.children = try grid(j, id: id, depth: depth, node: &node)
        case "keyset": node.children = try keyset(j, id: id, depth: depth, node: &node)
        default: break
        }
        if let a = j["area"] { node.area = try area(a, node: node) }
        return node
    }

    /// A node's own keys over its named style's.
    private func merged(_ raw: JSONValue) -> JSONValue {
        guard let name = raw["style"]?.stringValue, let base = styles[name]?.objectValue, let own = raw.objectValue else { return raw }
        return .object(base.merging(own) { _, mine in mine })
    }

    static func nodeId(_ j: JSONValue?) -> String? {
        guard let s = j?.stringValue, s.range(of: #"^[A-Za-z0-9_.:-]{1,64}$"#, options: .regularExpression) != nil else { return nil }
        return s
    }

    private mutating func kind(_ j: JSONValue, id: String, depth: Int, parent: SceneSize) throws -> SceneNode.Kind? {
        switch j["type"]?.stringValue {
        case "group", "row", "column", "grid", "keyset", nil: return .group
        case "image":
            guard let path = try picture(j["image"], id: id) else { return nil }
            images += 1
            guard images <= SurfaceScene.maxImages else { throw SurfaceScene.refused("draws more than \(SurfaceScene.maxImages) pictures") }
            return .image(SceneImage(path: path, dark: try picture(j["dark"], id: id), fit: j["fit"]?.stringValue.flatMap(SceneImage.Fit.init) ?? .contain,
                                     tint: Self.color(j["tint"])))
        case "text":
            guard let style = try textStyle(j, needsText: true) else {
                notes.append("The text of \(id) was left out.")
                return nil
            }
            return .text(style)
        case "shape":
            return shape(j).map(SceneNode.Kind.shape)
        case "symbol":
            guard let name = ExtensionPage.symbol(j["name"]) else { return nil }
            return .symbol(SceneSymbol(name: name, color: Self.color(j["color"]) ?? .token(.ink), weight: Self.weight(j["weight"], .semibold, &notes),
                                       mono: j["mode"]?.stringValue == "mono", secondary: Self.color(j["secondary"])))
        case "flip":
            return .flip(SceneFlip(axis: j["axis"]?.stringValue.flatMap(SceneFlip.Axis.init) ?? .y,
                                   turns: j["showing"]?.stringValue == "back" ? 1 : 0))
        case "companion", "person":
            people += 1
            guard people <= SurfaceScene.maxPeople else { throw SurfaceScene.refused("places the companion or the person more than \(SurfaceScene.maxPeople) times") }
            let look = SceneFigureLook(face: j["figure"]?.stringValue == "face", bottom: j["align"]?.stringValue == "bottom", duotone: Self.color(j["duotone"]))
            if j["type"]?.stringValue == "person" { return .person(look: look) }
            return .companion(pose: j["pose"]?.stringValue.flatMap(SceneCompanionPose.init) ?? .idle, look: look)
        case "scroll":
            return .scroll(SceneScroll(contentHeight: SurfaceScene.clamp(j["content_h"]?.doubleValue, 0...8000, 0), to: Self.nodeId(j["scroll_to"])))
        case "entry":
            guard let name = GameBoard.token(j["name"]) else { return nil }
            entries += 1
            guard entries <= SurfaceScene.maxEntries else { throw SurfaceScene.refused("has more than \(SurfaceScene.maxEntries) fields") }
            return .entry(SceneEntry(id: name, placeholder: GameBoard.line(j["placeholder"], 60), max: Int(SurfaceScene.clamp(j["max"]?.doubleValue, 1...120, 40)),
                                     locked: j["locked"]?.boolValue ?? false, size: SurfaceScene.clamp(j["size"]?.doubleValue, 9...40, 15),
                                     focus: j["focus"]?.boolValue ?? false, plain: j["plain"]?.boolValue ?? false, weight: Self.weight(j["weight"], .regular, &notes),
                                     design: j["design"]?.stringValue.flatMap(SceneText.Design.init) ?? .standard))
        case "clock":
            clocks += 1
            guard clocks <= SurfaceScene.maxClocks else { throw SurfaceScene.refused("has more than \(SurfaceScene.maxClocks) clocks") }
            guard var style = try textStyle(j, needsText: false) else { return nil }
            // A running clock's digits shouldn't jitter, unless it says otherwise.
            style.tabular = j["tabular"]?.boolValue ?? true
            return .clock(SceneClock(seconds: SurfaceScene.clamp(j["seconds"]?.doubleValue, 0...359_999, 0), running: j["running"]?.boolValue ?? false,
                                     down: j["down"]?.boolValue ?? false, style: style))
        default:
            notes.append("\(id) is of a type this version doesn't know.")
            return nil
        }
    }

    /// A pack path the scene may draw: clean, an image by its type, and in the pack when the pack is known. Otherwise
    /// the node draws nothing and the rest of the scene stands.
    private mutating func picture(_ j: JSONValue?, id: String) throws -> String? {
        guard let raw = j?.stringValue else { return nil }
        guard let path = PackAssets.clean(raw), PackAssets.kind(of: path) == .image, assets?.has(path) ?? true else {
            notes.append("\(id): “\(ExtensionText.clip(raw, 60))” isn't a picture in the pack.")
            return nil
        }
        distinct.insert(path)
        guard distinct.count <= SurfaceScene.maxAssets else { throw SurfaceScene.refused("draws more than \(SurfaceScene.maxAssets) different pictures") }
        return path
    }

    private mutating func textStyle(_ j: JSONValue, needsText: Bool) throws -> SceneText? {
        // Empty is a fine thing to say (a tile not typed in yet); no text at all, or not text, isn't.
        var runs: [SceneText.Run] = []
        var total = 0
        for run in (j["runs"]?.arrayValue ?? []).prefix(16) {
            // Not trimmed: the space between two runs is part of the words.
            guard let words = run["text"]?.stringValue.map({ ExtensionText.withoutStacks(ExtensionText.clean($0)) }), total + words.count <= SurfaceScene.maxTextCharacters else { continue }
            total += words.count
            runs.append(SceneText.Run(text: words, color: Self.color(run["color"]), weight: run["weight"].map { Self.weight($0, .regular, &notes) }))
        }
        let words = runs.isEmpty ? GameBoard.longText(j["text"], SurfaceScene.maxTextCharacters) ?? j["text"]?.stringValue.map { _ in "" } : runs.map(\.text).joined()
        if needsText, words == nil { return nil }
        text += words?.count ?? 0
        guard text <= SurfaceScene.maxAllText else { throw SurfaceScene.refused("holds more than \(SurfaceScene.maxAllText) characters") }
        return SceneText(text: words ?? "", size: SurfaceScene.clamp(j["size"]?.doubleValue, 6...160, 14),
                         weight: Self.weight(j["weight"], .regular, &notes),
                         design: j["design"]?.stringValue.flatMap(SceneText.Design.init) ?? .standard,
                         color: Self.color(j["color"]) ?? .token(.ink),
                         align: j["align"]?.stringValue.flatMap(SceneText.Align.init) ?? .center,
                         vAlign: j["valign"]?.stringValue.flatMap(SceneText.VAlign.init) ?? .center,
                         lines: Int(SurfaceScene.clamp(j["lines"]?.doubleValue, 1...40, 1)),
                         minScale: SurfaceScene.clamp(j["min_scale"]?.doubleValue, 0.4...1, 0.7),
                         italic: j["italic"]?.boolValue ?? false, tabular: j["tabular"]?.boolValue ?? false, strike: j["strike"]?.boolValue ?? false, runs: runs)
    }

    /// A weight this version doesn't know is noted for the author, not silently another.
    private static func weight(_ j: JSONValue?, _ fallback: SceneText.Weight, _ notes: inout [String]) -> SceneText.Weight {
        guard let raw = j?.stringValue else { return fallback }
        if let known = SceneText.Weight(rawValue: raw) { return known }
        notes.append("“\(ExtensionText.clip(raw, 20))” isn't a weight this version knows.")
        return fallback
    }

    private func shape(_ j: JSONValue) -> SceneShape? {
        let form: SceneShape.Form
        switch j["shape"]?.stringValue {
        case "rect", nil: form = .rect
        case "ellipse": form = .ellipse
        case "capsule": form = .capsule
        case "path":
            guard let ops = Self.path(j["path"]?.stringValue) else { return nil }
            form = .path(ops)
        default: return nil
        }
        var gradient: SceneShape.Gradient?
        if let g = j["gradient"], let colors = g["colors"]?.arrayValue?.compactMap({ Self.color($0) }), (2...6).contains(colors.count) {
            let f = g["from"]?.arrayValue?.compactMap(\.doubleValue) ?? [0, 0], t = g["to"]?.arrayValue?.compactMap(\.doubleValue) ?? [0, 1]
            if f.count == 2, t.count == 2 {
                gradient = .init(colors: colors, fromX: SurfaceScene.clamp(f[0], 0...1, 0), fromY: SurfaceScene.clamp(f[1], 0...1, 0),
                                 toX: SurfaceScene.clamp(t[0], 0...1, 0), toY: SurfaceScene.clamp(t[1], 0...1, 1))
            }
        }
        let dash = (j["dash"]?.arrayValue ?? []).prefix(4).compactMap(\.doubleValue).map { SurfaceScene.clamp($0, 0...200, 1) }
        return SceneShape(form: form, fill: Self.color(j["fill"]), gradient: gradient, stroke: Self.color(j["stroke"]),
                          lineWidth: SurfaceScene.clamp(j["line_width"]?.doubleValue, 0...40, 1), dash: dash)
    }

    /// A small path language: `M x y`, `L x y`, `Q cx cy x y`, `C c1x c1y c2x c2y x y`, `Z`. Nothing else, so a path can
    /// point at nothing.
    static func path(_ text: String?) -> [SceneShape.PathOp]? {
        guard let text, text.count <= 4000 else { return nil }
        var ops: [SceneShape.PathOp] = []
        var tokens = text.replacingOccurrences(of: ",", with: " ").matches(of: /[MLQCZ]|-?\d+(?:\.\d+)?/).map { String($0.0) }[...]
        func numbers(_ n: Int) -> [Double]? {
            guard tokens.count >= n else { return nil }
            let found = tokens.prefix(n).compactMap(Double.init)
            guard found.count == n, found.allSatisfy({ SurfaceScene.coordinates.contains($0) }) else { return nil }
            tokens = tokens.dropFirst(n)
            return found
        }
        while let command = tokens.popFirst() {
            guard ops.count < SurfaceScene.maxPathCommands else { return nil }
            switch command {
            case "M":
                guard let n = numbers(2) else { return nil }
                ops.append(.move(n[0], n[1]))
            case "L":
                guard let n = numbers(2) else { return nil }
                ops.append(.line(n[0], n[1]))
            case "Q":
                guard let n = numbers(4) else { return nil }
                ops.append(.quad(n[0], n[1], n[2], n[3]))
            case "C":
                guard let n = numbers(6) else { return nil }
                ops.append(.cubic(n[0], n[1], n[2], n[3], n[4], n[5]))
            case "Z": ops.append(.close)
            default: return nil
            }
        }
        guard case .move? = ops.first else { return nil }
        return ops
    }

    static func color(_ j: JSONValue?) -> SceneColor? {
        guard let j else { return nil }
        if let light = j["light"], let dark = j["dark"] {
            guard let l = hex(light.stringValue), let d = hex(dark.stringValue) else { return nil }
            return .adaptive(light: l, dark: d)
        }
        if let token = j["token"]?.stringValue.flatMap(SceneColor.Token.init(rawValue:)) {
            return .tuned(token, alpha: SurfaceScene.clamp(j["alpha"]?.doubleValue, 0...1, 1), brightness: SurfaceScene.clamp(j["brightness"]?.doubleValue, -1...1, 0))
        }
        guard let s = j.stringValue else { return nil }
        if let value = hex(s) { return .rgba(value) }
        return SceneColor.Token(rawValue: s).map(SceneColor.token)
    }

    private static func hex(_ s: String?) -> UInt32? {
        guard let s, s.hasPrefix("#"), s.count == 7 || s.count == 9, let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
        return s.count == 7 ? v << 8 | 0xFF : v
    }

    // MARK: Areas and keys

    private mutating func area(_ j: JSONValue, node: SceneNode) throws -> SceneArea? {
        guard let id = GameBoard.token(j["id"]) else { return nil }
        // Every interactive node says what it is: without words it can't be reached by VoiceOver, so it isn't offered.
        guard let label = GameBoard.line(j["label"], 120) else {
            notes.append("The area \(id) on \(node.id) has no label for VoiceOver, so it was left out.")
            return nil
        }
        areas += 1
        guard areas <= SurfaceScene.maxAreas else { throw SurfaceScene.refused("has more than \(SurfaceScene.maxAreas) areas") }
        var area = SceneArea(id: id, value: GameBoard.line(j["value"], 24), label: label)
        area.disabled = j["disabled"]?.boolValue ?? false
        area.always = j["always"]?.boolValue ?? false
        area.selected = j["selected"]?.boolValue ?? false
        area.hover = Self.style(j["hover"])
        area.press = Self.style(j["press"])
        for item in (j["highlight"]?.arrayValue ?? []).prefix(40) {
            if let id = Self.nodeId(item) {
                area.highlight.append(id)
            } else if let id = Self.nodeId(item["id"]), var look = Self.style(item) {
                look.absolute = look.opacity != nil
                area.looks[id] = look
            }
        }
        area.submits = GameBoard.token(j["submits"])
        area.sound = j["sound"]?.stringValue.flatMap { PackAssets.clean($0).flatMap { PackAssets.kind(of: $0) == .sound ? $0 : nil } }
        area.timedFrom = j["timed_from_ms"]?.doubleValue.flatMap { (0...60_000).contains($0) ? $0 / 1000 : nil }
        if let d = j["drag"] {
            var mode = SceneDrag.Mode.free
            if d["mode"]?.stringValue == "grid" {
                guard let r = d["rows"]?.intValue, let c = d["columns"]?.intValue, (1...32).contains(r), (1...32).contains(c) else { return area }
                mode = .grid(rows: r, columns: c)
            }
            area.drag = SceneDrag(mode: mode, ghost: Self.nodeId(d["ghost"]), inset: SurfaceScene.clamp(d["inset"]?.doubleValue, 0...40, 0))
        }
        if let k = j["key"], let key = Self.keyMatch(k.stringValue) {
            keys.append(SceneKey(match: key, id: id, area: id, value: area.value, bySeat: j["seat"]?.boolValue ?? false, timedFrom: area.timedFrom,
                                 always: area.always))
        }
        return area
    }

    private static func style(_ j: JSONValue?) -> SceneStyle? {
        guard let j, j.objectValue != nil else { return nil }
        return SceneStyle(scale: j["scale"]?.doubleValue.map { SurfaceScene.clamp($0, 0...4, 1) }, dx: j["dx"]?.doubleValue.map { SurfaceScene.clamp($0, -200...200, 0) },
                          dy: j["dy"]?.doubleValue.map { SurfaceScene.clamp($0, -200...200, 0) }, opacity: j["opacity"]?.doubleValue.map { SurfaceScene.clamp($0, 0...1, 1) },
                          rotate: j["rotate"]?.doubleValue.map { SurfaceScene.clamp($0, -360...360, 0) })
    }

    static func keyMatch(_ s: String?) -> SceneKey.Match? {
        guard let s else { return nil }
        if s == "letter" { return .anyLetter }
        if s == "digit" { return .anyDigit }
        if let named = SceneKey.Named(rawValue: s) { return .named(named) }
        let lower = s.lowercased()
        guard lower.count == 1, let c = lower.first, c.isLetter || c.isNumber || c == "?" else { return nil }
        return .character(lower)
    }

    static func key(_ j: JSONValue) -> SceneKey? {
        guard let match = keyMatch(j["key"]?.stringValue), let id = GameBoard.token(j["id"]) else { return nil }
        return SceneKey(match: match, id: id, area: GameBoard.token(j["area"]), value: GameBoard.line(j["value"], 24), bySeat: j["seat"]?.boolValue ?? false,
                        timedFrom: j["timed_from_ms"]?.doubleValue.flatMap { (0...60_000).contains($0) ? $0 / 1000 : nil }, always: j["always"]?.boolValue ?? false)
    }
}
