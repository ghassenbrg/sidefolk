#!/usr/bin/env swift
// Converts the provider logos in Resources/Brand/third-party/lobehub-icons/ (LobeHub Icons SVGs, kept as
// downloaded; see the README there) into the vector PDFs the app draws (D36): one 24 × 24 pt page per
// logo. The "-color" files keep their brand colours; the others are one black shape that the app tints
// as a template, so a black-or-white mark reads in light and dark.
//
// This writes the PDF itself instead of asking macOS to draw the SVG, because macOS gets these files
// wrong: CoreSVG misreads the arc flags that SVGO runs together ("a1 1 0 013 2"), which bends Claude's
// and Codex's marks; it drops `fill-opacity` that rides on `currentColor` (LM Studio); and a PDF
// context keeps no alpha in a gradient (Gemini's overlays turn solid). Here the path data is read as
// written (arcs become curves, nothing is retraced), gradients with transparency get a soft mask, and
// only paths, fills and shadings are ever written, so a bitmap cannot end up in a logo. A feature this
// reader doesn't know (a transform, a stroke, a filter) stops the script instead of drawing it wrong.
// Run from the repository root: swift scripts/provider-logos.swift
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sources = root.appendingPathComponent("Resources/Brand/third-party/lobehub-icons")
let out = root.appendingPathComponent("Resources/Brand/third-party/logos")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// MARK: - Reading the SVG

struct Stop { var offset: Double; var color: [Double]; var opacity: Double }
struct Gradient { var from: (x: Double, y: Double); var to: (x: Double, y: Double); var stops: [Stop] }
struct Shape { var d: String; var fill: String; var evenOdd: Bool; var opacity: Double }

/// The shapes of an SVG in paint order, and its gradients by id.
final class SVGReader: NSObject, XMLParserDelegate {
    private(set) var shapes: [Shape] = []
    private(set) var gradients: [String: Gradient] = [:]
    private var inherited: [String: String] = [:]
    private var gradientID: String?

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes a: [String: String]) {
        switch name {
        case "svg":
            guard a["viewBox"] == "0 0 24 24" else { fatalError("only 24 × 24 viewBoxes are read, not \(a["viewBox"] ?? "none")") }
            inherited = a.filter { ["fill", "fill-rule", "fill-opacity"].contains($0.key) }
        case "title", "defs": break
        case "path":
            let known: Set = ["d", "fill", "fill-rule", "clip-rule", "fill-opacity"]
            if let other = a.keys.first(where: { !known.contains($0) }) { fatalError("a path with \(other) isn't read") }
            let style = inherited.merging(a) { _, own in own }
            shapes.append(Shape(d: a["d"] ?? "", fill: style["fill"] ?? "black", evenOdd: style["fill-rule"] == "evenodd",
                                opacity: Double(style["fill-opacity"] ?? "1") ?? 1))
        case "linearGradient":
            guard a["gradientUnits"] == "userSpaceOnUse", let id = a["id"] else { fatalError("only userSpaceOnUse gradients with an id are read") }
            let point = { (key: String) in Double(a[key] ?? "") ?? 0 }
            gradients[id] = Gradient(from: (point("x1"), point("y1")), to: (point("x2"), point("y2")), stops: [])
            gradientID = id
        case "stop":
            guard let id = gradientID else { fatalError("a stop outside a gradient") }
            gradients[id]?.stops.append(Stop(offset: Double(a["offset"] ?? "0") ?? 0, color: rgb(a["stop-color"] ?? "black"),
                                             opacity: Double(a["stop-opacity"] ?? "1") ?? 1))
        default: fatalError("<\(name)> isn't read")
        }
    }
}

let namedColors = ["black": "#000000", "white": "#ffffff", "gold": "#ffd700", "currentColor": "#000000"]

/// 0...1 red, green, blue. `currentColor` is black: the app tints those logos itself.
func rgb(_ text: String) -> [Double] {
    var hex = namedColors[text] ?? text
    guard hex.hasPrefix("#") else { fatalError("colour \(text) isn't read") }
    hex.removeFirst()
    if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
    guard hex.count == 6, let value = Int(hex, radix: 16) else { fatalError("colour \(text) isn't read") }
    return [Double(value >> 16) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255]
}

// MARK: - Path data to PDF path operators

enum Token { case command(UInt8), number(Double) }

/// Path data split into commands and numbers. An arc's two flags are single digits that may be run
/// together with the number after them.
func tokens(_ d: String) -> [Token] {
    let c = Array(d.utf8)
    func isDigit(_ i: Int) -> Bool { i < c.count && c[i] >= 48 && c[i] <= 57 }
    var result: [Token] = []
    var command: UInt8 = 0
    var argument = 0
    var i = 0
    while i < c.count {
        let byte = c[i]
        if byte == 32 || byte == 44 || byte == 10 || byte == 9 { i += 1; continue }
        if (byte | 32) >= 97 && (byte | 32) <= 122 {
            command = byte
            argument = 0
            result.append(.command(byte))
            i += 1
            continue
        }
        var end = i
        if command | 32 == 97 && (argument % 7 == 3 || argument % 7 == 4) {
            end = i + 1
        } else {
            if c[end] == 43 || c[end] == 45 { end += 1 }
            while isDigit(end) { end += 1 }
            if end < c.count, c[end] == 46 { end += 1; while isDigit(end) { end += 1 } }
            if end < c.count, c[end] | 32 == 101 {
                end += 1
                if end < c.count, c[end] == 43 || c[end] == 45 { end += 1 }
                while isDigit(end) { end += 1 }
            }
        }
        guard end > i, let value = Double(String(decoding: c[i..<end], as: UTF8.self)) else { fatalError("can't read path data at \(i): \(d)") }
        result.append(.number(value))
        argument += 1
        i = end
    }
    return result
}

/// A number the way PDF wants it: plain decimals, no exponent.
func num(_ v: Double) -> String {
    var s = String(format: "%.4f", v)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s == "-0" ? "0" : s
}

typealias Point = (x: Double, y: Double)

/// The cubic curves that draw an SVG arc (SVG 1.1, F.6.5), none longer than a quarter turn.
func arcCurves(from p0: Point, radii: Point, rotation: Double, large: Bool, sweep: Bool, to p1: Point) -> [(Point, Point, Point)] {
    if p0.x == p1.x && p0.y == p1.y { return [] }
    var rx = abs(radii.x), ry = abs(radii.y)
    guard rx > 0, ry > 0 else { return [(p0, p1, p1)] } // a zero radius is a straight line
    let phi = rotation * .pi / 180, cosPhi = cos(phi), sinPhi = sin(phi)
    let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
    let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
    let tooSmall = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if tooSmall > 1 { rx *= tooSmall.squareRoot(); ry *= tooSmall.squareRoot() }
    let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
    let k = (large == sweep ? -1.0 : 1.0) * max(0, numerator / denominator).squareRoot()
    let cx1 = k * rx * y1 / ry, cy1 = -k * ry * x1 / rx
    let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2, cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
    // The arc runs from the start vector to the end vector (both on the unit circle), the way `sweep` says.
    let ux = (x1 - cx1) / rx, uy = (y1 - cy1) / ry, vx = (-x1 - cx1) / rx, vy = (-y1 - cy1) / ry
    let start = atan2(uy, ux)
    var span = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    if !sweep && span > 0 { span -= 2 * .pi }
    if sweep && span < 0 { span += 2 * .pi }
    let pieces = max(1, Int((abs(span) / (.pi / 2) - 1e-9).rounded(.up)))
    let step = span / Double(pieces), handle = 4.0 / 3.0 * tan(step / 4)
    func place(_ p: Point) -> Point {
        (cx + rx * p.x * cosPhi - ry * p.y * sinPhi, cy + rx * p.x * sinPhi + ry * p.y * cosPhi)
    }
    return (0..<pieces).map { n in
        let a = start + Double(n) * step, b = a + step
        let end = n == pieces - 1 ? p1 : place((cos(b), sin(b)))
        return (place((cos(a) - handle * sin(a), sin(a) + handle * cos(a))), place((cos(b) + handle * sin(b), sin(b) - handle * cos(b))), end)
    }
}

/// SVG path data as PDF path operators: moves, lines and cubic curves in absolute coordinates.
func pdfPath(_ d: String) -> String {
    let t = tokens(d)
    var ops: [String] = []
    var current: Point = (0, 0), subpathStart: Point = (0, 0)
    var lastCubic: Point?, lastQuad: Point?
    var command: UInt8 = 0
    var i = 0
    func number() -> Double {
        guard i < t.count, case .number(let v) = t[i] else { fatalError("path data ends early: \(d)") }
        i += 1
        return v
    }
    func line(to p: Point) { ops.append("\(num(p.x)) \(num(p.y)) l"); current = p }
    func curve(_ c1: Point, _ c2: Point, _ p: Point) {
        ops.append("\(num(c1.x)) \(num(c1.y)) \(num(c2.x)) \(num(c2.y)) \(num(p.x)) \(num(p.y)) c")
        current = p
    }
    while i < t.count {
        if case .command(let c) = t[i] {
            command = c
            i += 1
        } else if command == 0 {
            fatalError("path data starts with a number: \(d)")
        }
        let relative = command >= 97
        let origin: Point = relative ? current : (0, 0)
        func point() -> Point { let x = number(), y = number(); return (x + origin.x, y + origin.y) }
        var cubic: Point?, quad: Point?
        switch command | 32 {
        case 109: // m: a move; further pairs are lines
            let p = point()
            ops.append("\(num(p.x)) \(num(p.y)) m")
            current = p
            subpathStart = p
            command = relative ? 108 : 76
        case 108: line(to: point())
        case 104: line(to: (number() + origin.x, current.y))
        case 118: line(to: (current.x, number() + origin.y))
        case 99:
            let c1 = point(), c2 = point(), p = point()
            curve(c1, c2, p)
            cubic = c2
        case 115:
            let reflected = lastCubic.map { (2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current
            let c2 = point(), p = point()
            curve(reflected, c2, p)
            cubic = c2
        case 113, 116: // a quadratic curve is a cubic with its handles two thirds of the way to the control point
            let from = current
            let control: Point = command | 32 == 113 ? point() : (lastQuad.map { (2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current)
            let p = point()
            curve((from.x + 2 * (control.x - from.x) / 3, from.y + 2 * (control.y - from.y) / 3),
                  (p.x + 2 * (control.x - p.x) / 3, p.y + 2 * (control.y - p.y) / 3), p)
            quad = control
        case 97:
            let radii: Point = (number(), number()), rotation = number(), large = number() != 0, sweep = number() != 0
            let from = current, p = point()
            for (c1, c2, end) in arcCurves(from: from, radii: radii, rotation: rotation, large: large, sweep: sweep, to: p) {
                curve(c1, c2, end)
            }
            current = p
        case 122:
            ops.append("h")
            current = subpathStart
        default: fatalError("path command \(Character(UnicodeScalar(command))) isn't read: \(d)")
        }
        lastCubic = cubic
        lastQuad = quad
    }
    return ops.joined(separator: "\n")
}

// MARK: - Writing the PDF

/// A PDF file in memory: numbered objects, written out with their cross-reference table.
struct PDFFile {
    private var bodies: [String] = []

    mutating func add(_ body: String) -> Int {
        bodies.append(body)
        return bodies.count
    }

    mutating func addStream(_ dictionary: String, _ content: String) -> Int {
        add("<< \(dictionary) /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream")
    }

    mutating func set(_ number: Int, _ body: String) { bodies[number - 1] = body }

    var data: Data {
        var text = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, body) in bodies.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(index + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xref = text.utf8.count
        text += "xref\n0 \(bodies.count + 1)\n0000000000 65535 f \n"
        text += offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        text += "trailer\n<< /Size \(bodies.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(text.utf8)
    }
}

/// A PDF function that runs through the gradient's stops, one value (or colour) per stop, flat before
/// the first and after the last.
func stitching(_ stops: [(offset: Double, values: [Double])], _ pdf: inout PDFFile) -> Int {
    var stops = stops
    if let first = stops.first, first.offset > 0 { stops.insert((0, first.values), at: 0) }
    if let last = stops.last, last.offset < 1 { stops.append((1, last.values)) }
    let pieces = zip(stops, stops.dropFirst()).map { from, to in
        pdf.add("<< /FunctionType 2 /Domain [0 1] /C0 [\(from.values.map(num).joined(separator: " "))] /C1 [\(to.values.map(num).joined(separator: " "))] /N 1 >>")
    }
    return pdf.add("<< /FunctionType 3 /Domain [0 1] /Functions [\(pieces.map { "\($0) 0 R" }.joined(separator: " "))] "
        + "/Bounds [\(stops.dropFirst().dropLast().map { num($0.offset) }.joined(separator: " "))] "
        + "/Encode [\(pieces.map { _ in "0 1" }.joined(separator: " "))] >>")
}

/// The page for one SVG: a flip into SVG's y-down space, then each shape in paint order.
func pdf(for svg: URL) throws -> Data {
    let reader = SVGReader()
    let parser = XMLParser(data: try Data(contentsOf: svg))
    parser.delegate = reader
    guard parser.parse() else { fatalError("\(svg.lastPathComponent) isn't well-formed XML: \(parser.parserError?.localizedDescription ?? "")") }

    var pdf = PDFFile()
    let catalog = pdf.add(""), pages = pdf.add(""), page = pdf.add("")
    var states: [String] = [], shadings: [String] = []
    var content = "1 0 0 -1 0 24 cm\n"
    for shape in reader.shapes {
        content += "q\n"
        let fillOperator = shape.evenOdd ? "f*" : "f", clipOperator = shape.evenOdd ? "W*" : "W"
        if shape.fill.hasPrefix("url(#") {
            let id = String(shape.fill.dropFirst(5).dropLast())
            guard let gradient = reader.gradients[id], gradient.stops.count >= 2 else { fatalError("\(svg.lastPathComponent): no gradient \(id)") }
            let coords = "[\(num(gradient.from.x)) \(num(gradient.from.y)) \(num(gradient.to.x)) \(num(gradient.to.y))]"
            let colors = stitching(gradient.stops.map { ($0.offset, $0.color) }, &pdf)
            shadings.append("/Sh\(shadings.count) \(pdf.add("<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords \(coords) /Function \(colors) 0 R /Extend [true true] >>")) 0 R")
            if gradient.stops.contains(where: { $0.opacity < 1 }) {
                // Transparency in a gradient is a soft mask: the same gradient in grey, its brightness the alpha.
                let alphas = stitching(gradient.stops.map { ($0.offset, [$0.opacity]) }, &pdf)
                let grey = pdf.add("<< /ShadingType 2 /ColorSpace /DeviceGray /Coords \(coords) /Function \(alphas) 0 R /Extend [true true] >>")
                let mask = pdf.addStream("/Type /XObject /Subtype /Form /BBox [0 0 24 24] /Group << /S /Transparency /CS /DeviceGray >> "
                    + "/Resources << /Shading << /Alpha \(grey) 0 R >> >>", "/Alpha sh")
                states.append("/GS\(states.count) \(pdf.add("<< /Type /ExtGState /SMask << /Type /Mask /S /Luminosity /G \(mask) 0 R >> >>")) 0 R")
                content += "/GS\(states.count - 1) gs\n"
            }
            content += "\(pdfPath(shape.d))\n\(clipOperator) n\n/Sh\(shadings.count - 1) sh\n"
        } else {
            if shape.opacity < 1 {
                states.append("/GS\(states.count) \(pdf.add("<< /Type /ExtGState /ca \(num(shape.opacity)) >>")) 0 R")
                content += "/GS\(states.count - 1) gs\n"
            }
            content += "\(rgb(shape.fill).map(num).joined(separator: " ")) rg\n\(pdfPath(shape.d))\n\(fillOperator)\n"
        }
        content += "Q\n"
    }
    let contents = pdf.addStream("", content)
    pdf.set(catalog, "<< /Type /Catalog /Pages \(pages) 0 R >>")
    pdf.set(pages, "<< /Type /Pages /Kids [\(page) 0 R] /Count 1 >>")
    pdf.set(page, "<< /Type /Page /Parent \(pages) 0 R /MediaBox [0 0 24 24] /Contents \(contents) 0 R "
        + "/Resources << /ExtGState << \(states.joined(separator: " ")) >> /Shading << \(shadings.joined(separator: " ")) >> >> >>")
    return pdf.data
}

let svgs = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "svg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
for svg in svgs {
    let file = out.appendingPathComponent(svg.deletingPathExtension().lastPathComponent + ".pdf")
    try pdf(for: svg).write(to: file)
    guard let written = CGPDFDocument(file as CFURL), written.numberOfPages == 1 else { fatalError("\(file.lastPathComponent) isn't a valid one-page PDF") }
    print("wrote \(file.path.replacingOccurrences(of: root.path + "/", with: ""))")
}
