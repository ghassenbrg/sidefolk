import CoreGraphics
import Foundation

/// One drawing command of a shape, absolute, in the part's own units. Plain values, so a loaded
/// companion is `Sendable` and builds its paths on the main actor without touching files again.
enum PathOp: Equatable, Sendable {
    case move(CGPoint)
    case line(CGPoint)
    case quad(CGPoint, CGPoint)
    case cubic(CGPoint, CGPoint, CGPoint)
    case close

    static func path(_ ops: [PathOp], _ t: CGAffineTransform = .identity) -> CGPath {
        let path = CGMutablePath()
        for op in ops {
            switch op {
            case .move(let p): path.move(to: p.applying(t))
            case .line(let p): path.addLine(to: p.applying(t))
            case .quad(let c, let p): path.addQuadCurve(to: p.applying(t), control: c.applying(t))
            case .cubic(let c1, let c2, let p): path.addCurve(to: p.applying(t), control1: c1.applying(t), control2: c2.applying(t))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

/// A shape read from a part file, with its fill: a colour, or the companion's style colour
/// (`currentColor`), or none (the body's own shading).
struct PartShape: Equatable, Sendable {
    enum Fill: Equatable, Sendable { case body, accent, color(RGBValue) }
    var ops: [PathOp]
    var fill: Fill
}

/// An sRGB colour as numbers (the definition must be `Sendable` and `Equatable`).
struct RGBValue: Equatable, Sendable {
    var hex: UInt32
    var rgb: RGB { RGB(hex) }

    /// "#RRGGBB" only.
    init?(_ string: String) {
        guard string.count == 7, string.first == "#", let value = UInt32(string.dropFirst(), radix: 16) else { return nil }
        hex = value
    }
}

enum PartError: Error, Equatable, CustomStringConvertible {
    case path(String)
    case svg(String)

    var description: String {
        switch self {
        case .path(let why), .svg(let why): why
        }
    }
}

/// SVG path data ("M10 20 C …"): every command except arcs, absolute and relative, with the
/// shorthand curves; at most `limit` commands. Arcs are refused with a hint to convert them.
enum PathData {
    static let limit = 4000

    static func parse(_ d: String) throws -> [PathOp] {
        var scanner = Tokens(d)
        var ops: [PathOp] = []
        var current = CGPoint.zero, start = CGPoint.zero
        var lastControl: CGPoint?
        var lastCommand: Character = " "
        while let command = try scanner.command(repeating: lastCommand) {
            guard ops.count < limit else { throw PartError.path("more than \(limit) path commands") }
            let relative = command.isLowercase
            func point() throws -> CGPoint {
                let p = CGPoint(x: try scanner.number(), y: try scanner.number())
                return relative ? p + current : p
            }
            var control: CGPoint?
            switch command.lowercased().first! {
            case "m":
                current = try point()
                start = current
                ops.append(.move(current))
                // Coordinates after a moveto are implicit linetos.
                lastCommand = relative ? "l" : "L"
                lastControl = nil
                continue
            case "l":
                current = try point()
                ops.append(.line(current))
            case "h":
                let x = try scanner.number()
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                ops.append(.line(current))
            case "v":
                let y = try scanner.number()
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                ops.append(.line(current))
            case "c", "s":
                let c1: CGPoint
                if command.lowercased() == "s" {
                    c1 = lastControl.map { current * 2 - $0 } ?? current
                } else {
                    c1 = try point()
                }
                let c2 = try point(), end = try point()
                ops.append(.cubic(c1, c2, end))
                control = c2
                current = end
            case "q", "t":
                let c: CGPoint
                if command.lowercased() == "t" {
                    c = lastControl.map { current * 2 - $0 } ?? current
                } else {
                    c = try point()
                }
                let end = try point()
                ops.append(.quad(c, end))
                control = c
                current = end
            case "z":
                ops.append(.close)
                current = start
            case "a":
                throw PartError.path("arcs (A) aren't supported: convert them to curves (in Figma, Flatten; in Illustrator, Simplify)")
            default:
                throw PartError.path("unknown path command \(command)")
            }
            lastControl = control
            lastCommand = command
        }
        guard case .move = ops.first else { throw PartError.path("a path must start with M") }
        return ops
    }

    /// Numbers and command letters of path data.
    private struct Tokens {
        let chars: [Character]
        var i = 0

        init(_ s: String) { chars = Array(s) }

        mutating func skip() {
            while i < chars.count, chars[i].isWhitespace || chars[i] == "," { i += 1 }
        }

        /// The next command letter, or `repeating` when numbers follow (implicit repetition); nil at the end.
        mutating func command(repeating: Character) throws -> Character? {
            skip()
            guard i < chars.count else { return nil }
            if chars[i].isLetter, chars[i] != "e", chars[i] != "E" {
                defer { i += 1 }
                return chars[i]
            }
            guard repeating != " ", repeating.lowercased() != "z" else { throw PartError.path("number without a command") }
            return repeating
        }

        mutating func number() throws -> CGFloat {
            skip()
            let begin = i
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
            var dot = false, digits = false
            while i < chars.count {
                if chars[i].isNumber { digits = true; i += 1 } else if chars[i] == ".", !dot { dot = true; i += 1 } else { break }
            }
            if digits, i < chars.count, chars[i] == "e" || chars[i] == "E" {
                i += 1
                if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
                while i < chars.count, chars[i].isNumber { i += 1 }
            }
            guard digits, let value = Double(String(chars[begin..<i])), value.isFinite, abs(value) < 10_000 else {
                throw PartError.path("expected a number at character \(begin + 1)")
            }
            return CGFloat(value)
        }
    }
}

/// A part file: a small SVG of `path`, `circle`, `ellipse` and `rect` elements, nothing else drawn.
/// Never rendered by a browser engine; only shapes and fills are read. Scripts, images, links,
/// styles and transforms are refused so a part is plainly what it looks like.
final class SVGPart: NSObject, XMLParserDelegate {
    static let maxBytes = 256 * 1024
    static let maxShapes = 24
    private static let refused: Set<String> = ["script", "image", "use", "foreignObject", "style", "a", "iframe", "animate",
                                               "set", "animateTransform", "animateMotion", "pattern", "filter", "mask", "clipPath",
                                               "text"]
    private static let drawn: Set<String> = ["path", "circle", "ellipse", "rect"]
    private(set) var shapes: [PartShape] = []
    private var failure: PartError?
    private var inDefs = 0

    static func read(_ data: Data) throws -> [PartShape] {
        guard data.count <= maxBytes else { throw PartError.svg("bigger than 256 KiB") }
        let reader = SVGPart()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.delegate = reader
        let ok = parser.parse()
        if let failure = reader.failure { throw failure }
        guard ok else { throw PartError.svg("not valid SVG: \(parser.parserError?.localizedDescription ?? "unreadable")") }
        guard !reader.shapes.isEmpty else { throw PartError.svg("no path, circle, ellipse or rect in it") }
        return reader.shapes
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        guard failure == nil else { return }
        if Self.refused.contains(name) { return fail(parser, "<\(name)> isn't allowed in a part") }
        if attributes["transform"] != nil { return fail(parser, "transforms aren't supported: flatten them before exporting") }
        if attributes.keys.contains(where: { $0.lowercased().hasPrefix("on") || $0.hasSuffix("href") }) {
            return fail(parser, "event handlers and links aren't allowed in a part")
        }
        if name == "defs" || name == "symbol" { inDefs += 1 }
        guard inDefs == 0, Self.drawn.contains(name) else { return }
        guard shapes.count < Self.maxShapes else { return fail(parser, "more than \(Self.maxShapes) shapes") }
        do {
            shapes.append(PartShape(ops: try Self.ops(name, attributes), fill: try Self.fill(attributes)))
        } catch let error as PartError {
            fail(parser, "\(name): \(error)")
        } catch {
            fail(parser, "\(name): \(error)")
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "defs" || name == "symbol" { inDefs -= 1 }
    }

    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
        if target != "xml" { fail(parser, "processing instructions aren't allowed") }
    }

    private func fail(_ parser: XMLParser, _ why: String) {
        failure = .svg(why)
        parser.abortParsing()
    }

    private static func ops(_ name: String, _ a: [String: String]) throws -> [PathOp] {
        func number(_ key: String, _ fallback: CGFloat? = nil) throws -> CGFloat {
            guard let text = a[key] else {
                if let fallback { return fallback }
                throw PartError.svg("missing \(key)")
            }
            guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite, abs(value) < 10_000 else {
                throw PartError.svg("\(key) isn't a plain number")
            }
            return CGFloat(value)
        }
        func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> [PathOp] {
            let k: CGFloat = 0.5523
            return [.move(pt(cx + rx, cy)),
                    .cubic(pt(cx + rx, cy + ry * k), pt(cx + rx * k, cy + ry), pt(cx, cy + ry)),
                    .cubic(pt(cx - rx * k, cy + ry), pt(cx - rx, cy + ry * k), pt(cx - rx, cy)),
                    .cubic(pt(cx - rx, cy - ry * k), pt(cx - rx * k, cy - ry), pt(cx, cy - ry)),
                    .cubic(pt(cx + rx * k, cy - ry), pt(cx + rx, cy - ry * k), pt(cx + rx, cy)), .close]
        }
        switch name {
        case "path":
            guard let d = a["d"] else { throw PartError.svg("missing d") }
            return try PathData.parse(d)
        case "circle":
            let r = try number("r")
            return oval(try number("cx", 0), try number("cy", 0), r, r)
        case "ellipse":
            return oval(try number("cx", 0), try number("cy", 0), try number("rx"), try number("ry"))
        default:
            let x = try number("x", 0), y = try number("y", 0), w = try number("width"), h = try number("height")
            let r = min(try number("rx", try number("ry", 0)), w / 2, h / 2)
            guard r > 0 else { return [.move(pt(x, y)), .line(pt(x + w, y)), .line(pt(x + w, y + h)), .line(pt(x, y + h)), .close] }
            return roundedRect(x, y, w, h, r)
        }
    }

    private static func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> [PathOp] {
        [.move(pt(x + r, y)), .line(pt(x + w - r, y)), .quad(pt(x + w, y), pt(x + w, y + r)), .line(pt(x + w, y + h - r)),
         .quad(pt(x + w, y + h), pt(x + w - r, y + h)), .line(pt(x + r, y + h)), .quad(pt(x, y + h), pt(x, y + h - r)),
         .line(pt(x, y + r)), .quad(pt(x, y), pt(x + r, y)), .close]
    }

    private static func fill(_ a: [String: String]) throws -> PartShape.Fill {
        let value = (a["fill"] ?? "").trimmingCharacters(in: .whitespaces)
        switch value.lowercased() {
        case "", "none": return .body
        case "currentcolor": return .accent
        default:
            guard let color = RGBValue(value.uppercased()) else { throw PartError.svg("fill must be #RRGGBB, currentColor or none") }
            return .color(color)
        }
    }
}
