import Foundation

// The layout helpers: a row, a column, a grid and a set of keys, each read here into plain nodes with places, so the
// renderer knows only boxes. They save the extension work and nothing else: anything they make it could send by hand.

extension SceneReader {
    /// Children one after another along the axis: each at the end of the last plus the gap, placed across by `align`, and
    /// the run as a whole by `pack` when the group has a size. A child's own x and y add to the place it gets.
    mutating func stack(_ j: JSONValue, id: String, depth: Int, node: inout SceneNode) throws -> [SceneNode] {
        let horizontal = j["type"]?.stringValue == "row"
        let gap = SurfaceScene.clamp(j["gap"]?.doubleValue, 0...400, 0)
        let box = SceneSize(width: node.width, height: node.height)
        var children: [SceneNode] = []
        for (i, raw) in (j["items"]?.arrayValue ?? []).enumerated() {
            if let child = try self.node(raw, path: "\(id).\(i)", depth: depth + 1, parent: box) { children.append(child) }
        }
        let along = children.map { horizontal ? $0.width : $0.height }.reduce(0, +) + gap * Double(max(children.count - 1, 0))
        let across = children.map { horizontal ? $0.height : $0.width }.max() ?? 0
        if node.width == 0 { node.width = horizontal ? along : across }
        if node.height == 0 { node.height = horizontal ? across : along }
        let room = horizontal ? node.width : node.height, thick = horizontal ? node.height : node.width
        var at = Self.place(j["pack"]?.stringValue, along, room)
        let align = j["align"]?.stringValue
        for i in children.indices {
            let size = horizontal ? children[i].height : children[i].width
            let cross = Self.place(align ?? "center", size, thick)
            if horizontal {
                children[i].x += at
                children[i].y += cross
                at += children[i].width + gap
            } else {
                children[i].y += at
                children[i].x += cross
                at += children[i].height + gap
            }
        }
        return children
    }

    private static func place(_ how: String?, _ size: Double, _ room: Double) -> Double {
        switch how {
        case "center": (room - size) / 2
        case "end": room - size
        default: 0
        }
    }

    /// Cells of one size, row by row; a child with no size of its own takes the cell's.
    mutating func grid(_ j: JSONValue, id: String, depth: Int, node: inout SceneNode) throws -> [SceneNode] {
        let columns = Int(SurfaceScene.clamp(j["columns"]?.doubleValue, 1...64, 1))
        let cell = j["cell"]?.arrayValue?.compactMap(\.doubleValue) ?? []
        let (cw, ch) = (SurfaceScene.clamp(cell.first, 1...800, 40), SurfaceScene.clamp(cell.count > 1 ? cell[1] : nil, 1...800, 40))
        let gaps = j["gap"]?.arrayValue?.compactMap(\.doubleValue) ?? [j["gap"]?.doubleValue ?? 0]
        let (gx, gy) = (SurfaceScene.clamp(gaps.first, 0...200, 0), SurfaceScene.clamp(gaps.count > 1 ? gaps[1] : gaps.first, 0...200, 0))
        var children: [SceneNode] = []
        let box = SceneSize(width: cw, height: ch)
        for (i, raw) in (j["items"]?.arrayValue ?? []).enumerated() {
            guard var child = try self.node(raw, path: "\(id).\(i)", depth: depth + 1, parent: box) else { continue }
            if child.width == 0 { child.width = cw }
            if child.height == 0 { child.height = ch }
            child.x += Double(i % columns) * (cw + gx)
            child.y += Double(i / columns) * (ch + gy)
            children.append(child)
        }
        let rows = (children.count + columns - 1) / max(columns, 1)
        if node.width == 0 { node.width = Double(columns) * cw + Double(columns - 1) * gx }
        if node.height == 0 { node.height = Double(rows) * ch + Double(max(rows - 1, 0)) * gy }
        return children
    }

    /// A keyboard: rows of keys, each row centred, each key a cap on a darker lip with its letter, an area with its
    /// words for VoiceOver and the same key on the keyboard. `{key, label, fill, ink, w, disabled, faded}` per key; the
    /// move is a click on the set's `name` with the key as its value.
    mutating func keyset(_ j: JSONValue, id: String, depth: Int, node: inout SceneNode) throws -> [SceneNode] {
        guard let name = GameBoard.token(j["name"]) else { return [] }
        let key = j["key"]?.arrayValue?.compactMap(\.doubleValue) ?? []
        let (kw, kh) = (SurfaceScene.clamp(key.first, 8...200, 32), SurfaceScene.clamp(key.count > 1 ? key[1] : nil, 8...200, 40))
        let gaps = j["gap"]?.arrayValue?.compactMap(\.doubleValue) ?? [j["gap"]?.doubleValue ?? 4]
        let (gx, gy) = (SurfaceScene.clamp(gaps.first, 0...40, 4), SurfaceScene.clamp(gaps.count > 1 ? gaps[1] : gaps.first, 0...40, 4))
        let rows = (j["rows"]?.arrayValue ?? []).prefix(12).map { row in (row.arrayValue ?? []).prefix(24).map { $0 } }
        func width(_ k: JSONValue) -> Double { SurfaceScene.clamp(k["w"]?.doubleValue, 8...400, kw) }
        let widths = rows.map { $0.map(width).reduce(0, +) + gx * Double(max($0.count - 1, 0)) }
        if node.width == 0 { node.width = widths.max() ?? 0 }
        if node.height == 0 { node.height = Double(rows.count) * kh + Double(max(rows.count - 1, 0)) * gy }

        let corner = SurfaceScene.clamp(j["corner"]?.doubleValue, 0...40, 8)
        let size = SurfaceScene.clamp(j["size"]?.doubleValue, 6...60, 16)
        let lip = SurfaceScene.clamp(j["lip"]?.doubleValue, 0...8, 2)
        let plain = j["fill"].flatMap { Self.color($0) } ?? .token(.surfaceRaised)
        let edge = j["lip_color"].flatMap { Self.color($0) } ?? .token(.line)
        let ink = j["ink"].flatMap { Self.color($0) } ?? .token(.ink)
        var out: [SceneNode] = []
        var y = 0.0
        for (r, row) in rows.enumerated() {
            var x = (node.width - widths[r]) / 2
            for (c, k) in row.enumerated() {
                guard let value = GameBoard.line(k["key"], 12) else { continue }
                let w = width(k)
                let capId = "\(id).\(r).\(c)"
                let locked = k["disabled"]?.boolValue ?? false
                let fill = k["fill"].flatMap { Self.color($0) } ?? plain
                let word = GameBoard.line(k["label"], 12) ?? value
                let cap: JSONValue = .object([
                    "type": "group", "id": .string(capId), "x": .number(x), "y": .number(y), "w": .number(w), "h": .number(kh),
                    "opacity": k["faded"]?.boolValue == true ? 0.45 : 1,
                    "children": .array([
                        .object(["type": "shape", "w": .number(w), "h": .number(kh), "corner": .number(corner), "fill": Self.json(edge)]),
                        .object(["type": "shape", "w": .number(w), "h": .number(kh - lip), "corner": .number(corner), "fill": Self.json(fill), "id": .string(capId + ".face")]),
                        .object(["type": "text", "w": .number(w), "h": .number(kh - lip), "text": .string(word), "size": .number(size), "weight": "bold",
                                 "design": "rounded", "color": k["ink"].map { $0 } ?? Self.json(ink), "min_scale": 0.5]),
                    ]),
                    "area": .object([
                        "id": .string(name), "value": .string(value), "label": .string(GameBoard.line(k["spoken"], 60) ?? word), "disabled": .bool(locked),
                        "press": ["dy": .number(lip), "scale": 0.98], "hover": ["scale": 1.03],
                    ].merging(j["sound"].map { ["sound": $0] } ?? [:]) { own, _ in own }),
                ])
                if let made = try self.node(cap, path: capId, depth: depth + 1, parent: SceneSize(width: w, height: kh)) { out.append(made) }
                // The key on the keyboard presses the same cap; named keys (⌫, ↵) come as their own names.
                if !locked, k["no_key"]?.boolValue != true, let match = Self.keyMatch(k["typed"]?.stringValue ?? value) {
                    keys.append(SceneKey(match: match, id: name, area: name, value: value))
                }
                x += w + gx
            }
            y += kh + gy
        }
        return out
    }

    private static func json(_ color: SceneColor) -> JSONValue {
        switch color {
        case .rgba(let v): .string("#" + String(format: "%08X", v))
        case .token(let t): .string(t.rawValue)
        case .adaptive(let l, let d): .object(["light": .string("#" + String(format: "%08X", l)), "dark": .string("#" + String(format: "%08X", d))])
        case .tuned(let t, let alpha, let brightness): .object(["token": .string(t.rawValue), "alpha": .number(alpha), "brightness": .number(brightness)])
        }
    }
}

// MARK: Right to left

extension SurfaceScene {
    /// This scene as it is drawn in a language that reads right to left: every box measured from the far side, its curves
    /// with it, text aligned the other way, rotations turned. A node marked `ltr` is placed mirrored but its contents stay,
    /// which keeps a picture or a puzzle the same in every language; so does a scene with `mirror` off.
    public func mirrored() -> SurfaceScene {
        guard mirrors else { return self }
        var scene = self
        var flipped: [String: (width: Double, parent: Double)] = [:]
        func flip(_ list: [SceneNode], parentWidth: Double, active: Bool) -> [SceneNode] {
            list.map { original in
                var node = original
                if active {
                    node.x = parentWidth - node.x - node.width
                    node.anchorX = 1 - node.anchorX
                    node.rotate = -node.rotate
                    flipped[node.id] = (node.width, parentWidth)
                    switch node.kind {
                    case .text(var text):
                        text.align = text.align == .leading ? .trailing : text.align == .trailing ? .leading : .center
                        node.kind = .text(text)
                    case .clock(var clock):
                        clock.style.align = clock.style.align == .leading ? .trailing : clock.style.align == .trailing ? .leading : .center
                        node.kind = .clock(clock)
                    case .shape(var shape):
                        shape.mirror(width: node.width)
                        node.kind = .shape(shape)
                    default: break
                    }
                }
                node.children = flip(node.children, parentWidth: node.width, active: active && !node.ltr)
                return node
            }
        }
        scene.nodes = flip(nodes, parentWidth: size.width, active: true)
        for r in scene.runs.indices {
            for c in scene.runs[r].curves.indices {
                let target = scene.runs[r].curves[c].target
                guard let place = flipped[target] else { continue }
                switch scene.runs[r].curves[c].property {
                case .x: scene.runs[r].curves[c].values = scene.runs[r].curves[c].values.map { place.parent - $0 - place.width }
                case .rotate: scene.runs[r].curves[c].values = scene.runs[r].curves[c].values.map { -$0 }
                default: break
                }
            }
        }
        return scene
    }

    /// Whether a node's contents read left to right after `mirrored()`: a grid's column or a dragged point on it comes back
    /// to the extension in its own terms.
    public func isMirrored(_ id: String) -> Bool {
        guard mirrors else { return false }
        func find(_ list: [SceneNode], _ active: Bool) -> Bool? {
            for node in list {
                // A node marked `ltr` keeps its own contents as they are: its columns and points too.
                if node.id == id { return active && !node.ltr }
                if let inner = find(node.children, active && !node.ltr) { return inner }
            }
            return nil
        }
        return find(nodes, true) ?? false
    }
}

extension SceneShape {
    mutating func mirror(width: Double) {
        guard case .path(let ops) = form else {
            if var g = gradient {
                g.fromX = 1 - g.fromX
                g.toX = 1 - g.toX
                gradient = g
            }
            return
        }
        form = .path(ops.map { op in
            switch op {
            case .move(let x, let y): .move(width - x, y)
            case .line(let x, let y): .line(width - x, y)
            case .quad(let cx, let cy, let x, let y): .quad(width - cx, cy, width - x, y)
            case .cubic(let a, let b, let c, let d, let x, let y): .cubic(width - a, b, width - c, d, width - x, y)
            case .close: .close
            }
        })
    }
}
