import Foundation

/// `species.json`, format 1. Points are `[x, y]` in the 200 × 200 canvas, y up, feet on y = 20,
/// centred on x = 100 (docs/research/lively-companions.md has the whole format). Decoding is strict:
/// an unknown key anywhere is an error, so a typo never silently changes the companion.
struct SpeciesFile: Decodable {
    var format: Int
    var id: String
    var name: String
    var description: String?
    var author: String?
    var body: BodyFile
    var feet: FeetFile
    var arms: ArmsFile
    var face: FaceFile
    var ears: [EarFile]?
    var gear: [GearFile]?
    var collar: CollarFile?
    var marks: [String: Point]?

    struct BodyFile: Decodable {
        var colors: [String]
        var edge: String?
        var torso: ShapeFile
        var head: ShapeFile?
        var neck: Point
        var scale: Double?
    }

    struct FeetFile: Decodable {
        var at: [Point]
        var size: Point
        var colors: [String]?
    }

    struct ArmsFile: Decodable {
        var shoulders: [Point]
        var shape: ShapeFile
    }

    struct FaceFile: Decodable {
        var eyes: [Point]
        var mouth: Point
        var nose: NoseFile?
        var scale: Double?
        var cheeks: Bool?
        var temper: String?
    }

    struct NoseFile: Decodable {
        var center: Point
        var size: Point
        var color: String?
    }

    struct EarFile: Decodable {
        var part: String
        var base: Point
        var angle: Double?
        var side: String
        var floppiness: Double?
    }

    struct GearFile: Decodable {
        var part: String
        var mount: String
    }

    struct CollarFile: Decodable {
        var center: Point
        var halfWidth: Double
        var sag: Double?
        var height: Double?
        var tail: Double?
    }

    /// `[x, y]`, finite.
    struct Point: Decodable {
        var x: CGFloat
        var y: CGFloat
        var cg: CGPoint { CGPoint(x: x, y: y) }

        init(from decoder: Decoder) throws {
            let values = try decoder.singleValueContainer().decode([Double].self)
            guard values.count == 2, values.allSatisfy(\.isFinite) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "expected [x, y]"))
            }
            x = CGFloat(values[0])
            y = CGFloat(values[1])
        }
    }

    /// One of: `{"roundish": {center, size, top?, squareness?}}`, `{"ellipse": {center, radius}}`,
    /// `{"blob": [[x, y], …]}` (a smooth curve through the points), `{"path": "M … Z"}` (SVG path
    /// data in canvas units, y up) or `{"part": "parts/torso.svg"}` (an SVG drawn on a 200 × 200
    /// artboard, y down as usual in SVG).
    enum ShapeFile: Decodable {
        case roundish(center: Point, size: Point, top: Double?, squareness: Double?)
        case ellipse(center: Point, radius: Point)
        case blob([Point])
        case path(String)
        case part(String)

        private struct Roundish: Decodable { var center: Point, size: Point, top: Double?, squareness: Double? }
        private struct Ellipse: Decodable { var center: Point, radius: Point }
        private enum Keys: String, CodingKey { case roundish, ellipse, blob, path, part }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            guard c.allKeys.count == 1, let key = c.allKeys.first else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "a shape is one of roundish, ellipse, blob, path or part"))
            }
            switch key {
            case .roundish:
                let r = try c.decode(Roundish.self, forKey: .roundish)
                self = .roundish(center: r.center, size: r.size, top: r.top, squareness: r.squareness)
            case .ellipse:
                let e = try c.decode(Ellipse.self, forKey: .ellipse)
                self = .ellipse(center: e.center, radius: e.radius)
            case .blob: self = .blob(try c.decode([Point].self, forKey: .blob))
            case .path: self = .path(try c.decode(String.self, forKey: .path))
            case .part: self = .part(try c.decode(String.self, forKey: .part))
            }
        }
    }

    // MARK: Strict keys

    private static let shapeKeys: Schema = .object(["roundish": .object(["center": .any, "size": .any, "top": .any, "squareness": .any]),
                                                    "ellipse": .object(["center": .any, "radius": .any]),
                                                    "blob": .any, "path": .any, "part": .any])
    static let schema: Schema = .object([
        "format": .any, "id": .any, "name": .any, "description": .any, "author": .any,
        "body": .object(["colors": .any, "edge": .any, "torso": shapeKeys, "head": shapeKeys, "neck": .any, "scale": .any]),
        "feet": .object(["at": .any, "size": .any, "colors": .any]),
        "arms": .object(["shoulders": .any, "shape": shapeKeys]),
        "face": .object(["eyes": .any, "mouth": .any, "nose": .object(["center": .any, "size": .any, "color": .any]),
                         "scale": .any, "cheeks": .any, "temper": .any]),
        "ears": .list(.object(["part": .any, "base": .any, "angle": .any, "side": .any, "floppiness": .any])),
        "gear": .list(.object(["part": .any, "mount": .any])),
        "collar": .object(["center": .any, "halfWidth": .any, "sag": .any, "height": .any, "tail": .any]),
        "marks": .object(["zzz": .any, "dots": .any, "exclaim": .any, "question": .any, "sparkles": .any, "sweat": .any,
                          "waves": .any, "confetti": .any, "ticks": .any]),
    ])

    indirect enum Schema: Sendable {
        case any
        case object([String: Schema])
        case list(Schema)

        /// The first key `json` has that the schema doesn't, as a dotted path.
        func unknownKey(in json: Any, at path: String = "") -> String? {
            switch (self, json) {
            case (.object(let keys), let object as [String: Any]):
                for key in object.keys.sorted() {
                    let here = path.isEmpty ? key : "\(path).\(key)"
                    guard let inner = keys[key] else { return here }
                    if let found = inner.unknownKey(in: object[key]!, at: here) { return found }
                }
            case (.list(let item), let array as [Any]):
                for (i, element) in array.enumerated() {
                    if let found = item.unknownKey(in: element, at: "\(path)[\(i)]") { return found }
                }
            default: break
            }
            return nil
        }
    }

    // MARK: Resolving

    /// Checks every value against its range and reads the parts, into plain values.
    func resolve(part: (String) throws -> [PartShape]) throws -> CompanionBody {
        typealias Invalid = CustomCompanions.Invalid
        guard format == CustomCompanions.formatVersion else { throw Invalid("format must be \(CustomCompanions.formatVersion)") }
        guard id.range(of: #"^[a-z][a-z0-9-]{1,31}$"#, options: .regularExpression) != nil else {
            throw Invalid("id: 2–32 lowercase letters, digits and dashes, starting with a letter")
        }
        guard CharacterSpecies(rawValue: id) == nil else { throw Invalid("id: \(id) is a companion Sidefolk already has") }
        try text(name, "name", 1...30)
        if let description { try text(description, "description", 0...200) }
        if let author { try text(author, "author", 0...60) }

        func point(_ p: Point, _ key: String) throws -> CGPoint {
            guard (-40...240).contains(p.x), (-40...240).contains(p.y) else { throw Invalid("\(key): outside the canvas") }
            return p.cg
        }
        func extent(_ p: Point, _ key: String) throws -> CGSize {
            guard (0.5...220).contains(p.x), (0.5...220).contains(p.y) else { throw Invalid("\(key): sizes are 0.5 to 220") }
            return CGSize(width: p.x, height: p.y)
        }
        func number(_ value: Double?, _ key: String, _ range: ClosedRange<Double>, _ fallback: Double) throws -> CGFloat {
            let value = value ?? fallback
            guard range.contains(value) else { throw Invalid("\(key): \(range.lowerBound) to \(range.upperBound)") }
            return CGFloat(value)
        }
        func color(_ s: String, _ key: String) throws -> RGBValue {
            guard let c = RGBValue(s.uppercased()) else { throw Invalid("\(key): colours are written #RRGGBB") }
            return c
        }
        func shape(_ s: ShapeFile, _ key: String) throws -> [PathOp] {
            let ops: [PathOp]
            switch s {
            case let .roundish(center, size, top, squareness):
                let c = try point(center, key + ".center"), z = try extent(size, key + ".size")
                ops = Self.ops(Shapes.roundishPoints(center: c, width: z.width, height: z.height,
                                                     top: try number(top, key + ".top", 0.4...1.2, 1),
                                                     squareness: try number(squareness, key + ".squareness", 1.5...4, 2.2)))
            case let .ellipse(center, radius):
                let c = try point(center, key + ".center"), r = try extent(radius, key + ".radius")
                ops = Self.ops(stride(from: 0.0, to: 2 * .pi, by: .pi / 12).map { c + pt(cos($0) * r.width, sin($0) * r.height) })
            case .blob(let points):
                guard (3...96).contains(points.count) else { throw Invalid("\(key).blob: 3 to 96 points") }
                ops = Self.ops(try points.enumerated().map { try point($1, "\(key).blob[\($0)]") })
            case .path(let d):
                do { ops = try PathData.parse(d) } catch let error as PartError { throw Invalid("\(key).path: \(error)") }
            case .part(let file):
                // Drawn on a 200 × 200 artboard, y down: turned the canvas way up.
                let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 200)
                ops = try part(file).flatMap { $0.ops }.map { $0.applying(flip) }
            }
            let box = PathOp.path(ops).boundingBoxOfPath
            guard !box.isNull, box.width > 1, box.height > 1, CGRect(x: -40, y: -40, width: 280, height: 280).contains(box) else {
                throw Invalid("\(key): the shape is empty or outside the canvas")
            }
            return ops
        }

        guard (2...6).contains(body.colors.count) else { throw Invalid("body.colors: 2 to 6 colours, light to shadow") }
        guard feet.at.count == 2 else { throw Invalid("feet.at: two feet") }
        guard arms.shoulders.count == 2 else { throw Invalid("arms.shoulders: two shoulders") }
        guard face.eyes.count == 2 else { throw Invalid("face.eyes: two eyes") }
        guard (ears ?? []).count <= 4 else { throw Invalid("ears: at most 4") }
        guard (gear ?? []).count <= 8 else { throw Invalid("gear: at most 8 pieces") }
        let temper = try Self.temper(face.temper ?? "calm")

        return CompanionBody(
            colors: try body.colors.enumerated().map { try color($1, "body.colors[\($0)]") },
            edge: try body.edge.map { try color($0, "body.edge") },
            torso: try shape(body.torso, "body.torso"),
            head: try body.head.map { try shape($0, "body.head") },
            neck: try point(body.neck, "body.neck"),
            scale: try number(body.scale, "body.scale", 0.6...1.1, 1),
            feet: try feet.at.enumerated().map { try point($1, "feet.at[\($0)]") },
            foot: try extent(feet.size, "feet.size"),
            footColors: try feet.colors.map { colors in
                guard (2...6).contains(colors.count) else { throw Invalid("feet.colors: 2 to 6 colours") }
                return try colors.enumerated().map { try color($1, "feet.colors[\($0)]") }
            },
            shoulders: try arms.shoulders.enumerated().map { try point($1, "arms.shoulders[\($0)]") },
            arm: try shape(arms.shape, "arms.shape"),
            eyes: try face.eyes.enumerated().map { try point($1, "face.eyes[\($0)]") },
            mouth: try point(face.mouth, "face.mouth"),
            nose: try face.nose.map { nose in
                let c = try point(nose.center, "face.nose.center"), z = try extent(nose.size, "face.nose.size")
                return CGRect(x: c.x - z.width / 2, y: c.y - z.height / 2, width: z.width, height: z.height)
            },
            noseColor: try face.nose?.color.map { try color($0, "face.nose.color") },
            faceScale: try number(face.scale, "face.scale", 0.6...1.8, 1),
            cheeks: face.cheeks ?? false,
            temper: temper,
            ears: try (ears ?? []).enumerated().map { i, ear in
                guard ear.side == "left" || ear.side == "right" else { throw Invalid("ears[\(i)].side: left or right") }
                return CompanionBody.Ear(shapes: try part(ear.part), base: try point(ear.base, "ears[\(i)].base"),
                                         angle: try number(ear.angle, "ears[\(i)].angle", -1.2...1.2, 0),
                                         side: ear.side == "left" ? -1 : 1,
                                         floppiness: try number(ear.floppiness, "ears[\(i)].floppiness", 0...1, 0.6))
            },
            gear: try (gear ?? []).enumerated().map { i, worn in
                guard ["head", "face", "body", "back"].contains(worn.mount) else { throw Invalid("gear[\(i)].mount: head, face, body or back") }
                return CompanionBody.Worn(shapes: try part(worn.part), mount: worn.mount)
            },
            collar: try collar.map { c in
                CompanionBody.CollarSpec(center: try point(c.center, "collar.center"),
                                         halfWidth: try number(c.halfWidth, "collar.halfWidth", 8...80, 30),
                                         sag: try number(c.sag, "collar.sag", 0...12, 4.5),
                                         height: try number(c.height, "collar.height", 6...30, 17),
                                         tail: try number(c.tail, "collar.tail", 0.5...3, 1.45))
            },
            marks: try (marks ?? [:]).mapValues { p in
                guard abs(p.x) <= 60, abs(p.y) <= 60 else { throw Invalid("marks: offsets are -60 to 60") }
                return p.cg
            })
    }

    private func text(_ value: String, _ key: String, _ length: ClosedRange<Int>) throws {
        guard length.contains(value.count), !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw CustomCompanions.Invalid("\(key): \(length.lowerBound) to \(length.upperBound) characters of plain text")
        }
    }

    private static func temper(_ name: String) throws -> Temper {
        switch name {
        case "calm": .calm
        case "smiling": .smiling
        case "cheerful": .cheerful
        case "beaming": .beaming
        case "content": .content
        case "giddy": .giddy
        case "stern": .stern
        case "winking": .winking
        default: throw CustomCompanions.Invalid("face.temper: calm, smiling, cheerful, beaming, content, giddy, stern or winking")
        }
    }

    /// A smooth closed curve through `points`, as Mochi's own shapes are drawn (Catmull-Rom).
    private static func ops(_ points: [CGPoint]) -> [PathOp] {
        let n = points.count
        var ops: [PathOp] = [.move(points[0])]
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n], p1 = points[i], p2 = points[(i + 1) % n], p3 = points[(i + 2) % n]
            ops.append(.cubic(p1 + (p2 - p0) * (1.0 / 6), p2 - (p3 - p1) * (1.0 / 6), p2))
        }
        return ops + [.close]
    }
}

extension PathOp {
    func applying(_ t: CGAffineTransform) -> PathOp {
        switch self {
        case .move(let p): .move(p.applying(t))
        case .line(let p): .line(p.applying(t))
        case .quad(let c, let p): .quad(c.applying(t), p.applying(t))
        case .cubic(let a, let b, let p): .cubic(a.applying(t), b.applying(t), p.applying(t))
        case .close: .close
        }
    }
}
