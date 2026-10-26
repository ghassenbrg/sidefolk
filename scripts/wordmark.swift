#!/usr/bin/env swift
// The Sidefolk wordmark, built the way the reference lettering is drawn: heavy round-capped strokes,
// rings and round dots, outlined and merged into one filled path per letter. No font, no tracing.
// Run from the repository root:
//
//   swift scripts/wordmark.swift               writes Resources/Brand/masters/wordmark.svg
//   swift scripts/wordmark.swift --check <dir> overlay and difference against the reference, per-letter
//                                              match, written to <dir>/wordmark-fit.png
//   swift scripts/wordmark.swift --fit [S e …] re-calibrates the numbers below against the reference
//                                              (after changing a construction) and prints them
//
// Every number is in the reference image's pixels (Resources/Brand/reference/wordmark-reference.png,
// 638 × 196, y down). They were calibrated with --fit: coordinate descent on the difference between
// this construction's coverage and the reference's, then shared widths were made equal so the stems
// read as one weight.
import AppKit
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let referenceURL = root.appendingPathComponent("Resources/Brand/reference/wordmark-reference.png")
let masterURL = root.appendingPathComponent("Resources/Brand/masters/wordmark.svg")
let navy = "#0F2D5B", aqua = "#2ED4D9"

// MARK: Construction

enum Shape {
    case stroke(CGPath, Double)
    case fill(CGPath)
}

enum Op {
    case add(Shape)
    case cut(Shape)
}

struct Letter {
    var name: String
    var color: String
    var p: [Double]
    /// How far --fit may move each number at first; 0 keeps it as is.
    var steps: [Double]
    /// What --fit adds to the difference for shapes the construction must keep away from.
    var rule: ([Double]) -> Double = { _ in 0 }
    var build: ([Double]) -> [Op]
}

func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGPath {
    let p = CGMutablePath()
    p.move(to: pt(x0, y0))
    p.addLine(to: pt(x1, y1))
    return p
}
func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry), transform: nil)
}
/// Part of an ellipse, from angle a0 to a1 (radians, y down: 0 is right, π/2 is down).
func arc(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ a0: Double, _ a1: Double) -> CGPath {
    let p = CGMutablePath()
    p.addArc(center: .zero, radius: 1, startAngle: a0, endAngle: a1, clockwise: a1 < a0,
             transform: CGAffineTransform(translationX: cx, y: cy).scaledBy(x: rx, y: ry))
    return p
}
/// The body of a stroke whose width changes evenly between two round ends that other strokes already
/// draw: the four-sided piece between the lines tangent to both ends. Leaving the ends out keeps their
/// outlines from being drawn twice (merging coincident arcs shreds them into slivers).
func taper(_ x0: Double, _ y0: Double, _ r0: Double, _ x1: Double, _ y1: Double, _ r1: Double) -> CGPath {
    let d = hypot(x1 - x0, y1 - y0)
    let phi = atan2(y1 - y0, x1 - x0), alpha = acos(max(-1, min(1, (r0 - r1) / d)))
    func on(_ x: Double, _ y: Double, _ r: Double, _ a: Double) -> CGPoint { pt(x + r * cos(a), y + r * sin(a)) }
    let p = CGMutablePath()
    p.addLines(between: [on(x0, y0, r0, phi + alpha), on(x1, y1, r1, phi + alpha), on(x1, y1, r1, phi - alpha), on(x0, y0, r0, phi - alpha)])
    p.closeSubpath()
    return p
}
/// A smooth curve through nodes, each (x, y, direction, handle in, handle out).
func spline(_ p: [Double], from start: Int, nodes count: Int) -> CGPath {
    let path = CGMutablePath()
    path.move(to: pt(p[start], p[start + 1]))
    for i in 1..<count {
        let a = start + (i - 1) * 5, b = start + i * 5
        path.addCurve(to: pt(p[b], p[b + 1]),
                      control1: pt(p[a] + p[a + 4] * cos(p[a + 2]), p[a + 1] + p[a + 4] * sin(p[a + 2])),
                      control2: pt(p[b] - p[b + 3] * cos(p[b + 2]), p[b + 1] - p[b + 3] * sin(p[b + 2])))
    }
    return path
}

/// A point on the spline above and its direction there; t runs from 0 at the first node to count - 1.
func splineFrame(_ p: [Double], from start: Int, nodes count: Int, at t: Double) -> (CGPoint, CGPoint) {
    let i = min(Int(t), count - 2), u = t - Double(i), s = 1 - u
    let a = start + i * 5, b = a + 5
    let p0 = pt(p[a], p[a + 1]), p3 = pt(p[b], p[b + 1])
    let p1 = pt(p[a] + p[a + 4] * cos(p[a + 2]), p[a + 1] + p[a + 4] * sin(p[a + 2]))
    let p2 = pt(p[b] - p[b + 3] * cos(p[b + 2]), p[b + 1] - p[b + 3] * sin(p[b + 2]))
    let x = p0.x * s * s * s + 3 * p1.x * s * s * u + 3 * p2.x * s * u * u + p3.x * u * u * u
    let y = p0.y * s * s * s + 3 * p1.y * s * s * u + 3 * p2.y * s * u * u + p3.y * u * u * u
    let dx = 3 * s * s * (p1.x - p0.x) + 6 * s * u * (p2.x - p1.x) + 3 * u * u * (p3.x - p2.x)
    let dy = 3 * s * s * (p1.y - p0.y) + 6 * s * u * (p2.y - p1.y) + 3 * u * u * (p3.y - p2.y)
    let length = hypot(dx, dy)
    return (pt(x, y), pt(dx / length, dy / length))
}
/// A point on an ellipse and its direction there, travelling towards smaller angles (as arc() does
/// from a0 to a1 when a1 < a0).
func ellipseFrame(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, at a: Double) -> (CGPoint, CGPoint) {
    let dx = rx * sin(a), dy = -ry * cos(a), length = hypot(dx, dy)
    return (pt(cx + rx * cos(a), cy + ry * sin(a)), pt(dx / length, dy / length))
}
/// A curve that leaves another stroke's centre line along it and rejoins it along it further on.
/// Stroked at the same width, it adds weight on one side of a curve while both edges stay smooth where
/// it parts from the stroke and where it meets it again.
func branch(_ from: (CGPoint, CGPoint), _ to: (CGPoint, CGPoint), _ out: Double, _ back: Double) -> CGPath {
    let path = CGMutablePath()
    path.move(to: from.0)
    path.addCurve(to: to.0, control1: pt(from.0.x + from.1.x * out, from.0.y + from.1.y * out),
                  control2: pt(to.0.x - to.1.x * back, to.0.y - to.1.y * back))
    return path
}

/// The smallest radius of curvature along a single cubic curve.
func tightest(_ curve: CGPath) -> Double {
    var points: [CGPoint] = []
    curve.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: points = [e.points[0]]
        case .addCurveToPoint: points += [e.points[0], e.points[1], e.points[2]]
        default: break
        }
    }
    let p = points
    return stride(from: 0.0, through: 1.0, by: 0.02).map { (t: Double) -> Double in
        let s = 1 - t
        let dx = 3 * s * s * (p[1].x - p[0].x) + 6 * s * t * (p[2].x - p[1].x) + 3 * t * t * (p[3].x - p[2].x)
        let dy = 3 * s * s * (p[1].y - p[0].y) + 6 * s * t * (p[2].y - p[1].y) + 3 * t * t * (p[3].y - p[2].y)
        let ddx = 6 * s * (p[2].x - 2 * p[1].x + p[0].x) + 6 * t * (p[3].x - 2 * p[2].x + p[1].x)
        let ddy = 6 * s * (p[2].y - 2 * p[1].y + p[0].y) + 6 * t * (p[3].y - 2 * p[2].y + p[1].y)
        return pow(dx * dx + dy * dy, 1.5) / max(1e-9, abs(dx * ddy - dy * ddx))
    }.min()!
}

/// One weight for every stem and the k's arms; the rays are lighter.
let stem = 33.2, ray = 19.2

/// The S's two tighter turns, branching off its main stroke around the counters.
func sTurns(_ p: [Double]) -> [CGPath] {
    func at(_ t: Double) -> (CGPoint, CGPoint) { splineFrame(p, from: 0, nodes: 7, at: t) }
    return [branch(at(p[36]), at(p[37]), p[38], p[39]), branch(at(p[40]), at(p[41]), p[42], p[43])]
}

var letters: [Letter] = [
    // S: one stroke from the top terminal over the top, down the spine and round to the bottom
    // terminal. In each turn a tighter curve of the same width branches off inside it and rejoins it,
    // so the counters end in round tips and the turns carry a little more weight than the spine, as in
    // the reference.
    Letter(name: "S", color: navy,
           p: [90.767, 77.72, 4.046, 0, 3.74, 67.514, 69.821, 3.139, 10.839, 19.331, 33.902, 94.05, 1.564, 15.848,
               12.608, 64.884, 116.16, 0.285, 20.901, 23.259, 97.462, 140.772, 1.59, 17.08, 20.033, 57.169, 164.105,
               3.281, 12.274, 9.154, 33.122, 152.515, -1.402, 6.316, 0, 32.303, 1.124, 2.85, 24.492, 24.629, 3.114,
               4.736, 24.872, 24.517],
           steps: [1, 1, 0.05, 0, 1, 1, 1, 0.05, 1, 1, 1, 1, 0.05, 1, 1, 1, 1, 0.05, 1, 1, 1, 1, 0.05, 1, 1, 1, 1, 0.05, 1, 1,
                   1, 1, 0.05, 1, 0, 0.5, 0.05, 0.05, 1, 1, 0.05, 0.05, 1, 1],
           // A turn no tighter than half the width plus 5 px leaves the counter a round 5 px end.
           rule: { p in sTurns(p).reduce(0) { $0 + max(0, p[35] / 2 + 5 - tightest($1)) * 500 } }) { p in
        [.add(.stroke(spline(p, from: 0, nodes: 7), p[35]))] + sTurns(p).map { .add(.stroke($0, p[35])) }
    },
    // i: a round-capped stem and a round dot.
    Letter(name: "i", color: navy, p: [135.80, 104.70, 162.91, 136.04, 64.99, 18.49, 17.53], steps: [1, 1, 1, 1, 1, 0.5, 0.5]) { p in
        [.add(.stroke(line(p[0], p[1], p[0], p[2]), stem)), .add(.fill(ellipse(p[3], p[4], p[5], p[6])))]
    },
    // d: a ring for the bowl, its counter meeting the stem.
    Letter(name: "d", color: navy, p: [229.81, 68.95, 162.76, 193.28, 133.96, 38.44, 45.43, 200.03, 133.50, 14.54, 16.01],
           steps: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]) { p in
        [.add(.fill(ellipse(p[3], p[4], p[5], p[6]))), .cut(.fill(ellipse(p[7], p[8], p[9], p[10]))),
         .add(.stroke(line(p[0], p[1], p[0], p[2]), stem))]
    },
    // e: a ring that starts at the bar's right end and goes up, round and down to the lower terminal,
    // and a lighter bar. A curve of the same width branches off the ring on the left and rejoins it
    // before the terminal, giving the bottom its weight with smooth edges. A tapered stroke joins the
    // bar's end to the ring's start, so the right side runs straight down into the bar's tighter corner.
    Letter(name: "e", color: navy,
           p: [290.886, 134.12, 29.606, 32.902, 25.773, -0.579, -5.56, 274.552, 134.276, 319.984, 129.577, 17.723,
               -3.423, -5.41, 19.34, 17.542],
           steps: [1, 1, 1, 1, 0.5, 0.05, 0.05, 1, 1, 1, 1, 0.5, 0.05, 0.05, 1, 1]) { p in
        func at(_ a: Double) -> (CGPoint, CGPoint) { ellipseFrame(p[0], p[1], p[2], p[3], at: a) }
        return [.add(.stroke(arc(p[0], p[1], p[2], p[3], p[5], p[6]), p[4])),
                .add(.stroke(branch(at(p[12]), at(p[13]), p[14], p[15]), p[4])),
                .add(.stroke(line(p[7], p[8], p[9], p[10]), p[11])),
                .add(.fill(taper(p[0] + p[2] * cos(p[5]), p[1] + p[3] * sin(p[5]), p[4] / 2, p[9], p[10], p[11] / 2)))]
    },
    // f: the stem rises and turns into the hook in one stroke; the crossbar is a second stroke.
    Letter(name: "f", color: aqua, p: [350.13, 163.56, 70.92, 11.35, 376.77, 69.69, 31.53, 109.58, 371.32, 108.98, 29.27],
           steps: [1, 1, 1, 1, 1, 1, 0.5, 1, 1, 1, 0.5]) { p in
        let hook = CGMutablePath()
        hook.move(to: pt(p[0], p[1]))
        hook.addArc(tangent1End: pt(p[0], p[2]), tangent2End: pt(p[4], p[5]), radius: p[3])
        hook.addLine(to: pt(p[4], p[5]))
        return [.add(.stroke(hook, p[6])), .add(.stroke(line(p[0], p[7], p[8], p[9]), p[10]))]
    },
    // o: a ring.
    Letter(name: "o", color: aqua, p: [425.42, 134.05, 42.66, 45.52, 425.55, 135.86, 12.11, 12.71], steps: [1, 1, 1, 1, 1, 1, 1, 1]) { p in
        [.add(.fill(ellipse(p[0], p[1], p[2], p[3]))), .cut(.fill(ellipse(p[4], p[5], p[6], p[7])))]
    },
    Letter(name: "l", color: aqua, p: [486.90, 69.20, 162.68], steps: [1, 1, 1]) { p in
        [.add(.stroke(line(p[0], p[1], p[0], p[2]), stem))]
    },
    // k: the stem and two arms that meet inside it.
    Letter(name: "k", color: aqua,
           p: [526.03, 73.91, 162.82, 547.11, 134.43, 575.22, 105.68, 548.02, 129.86, 575.85, 162.93],
           steps: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]) { p in
        [.add(.stroke(line(p[0], p[1], p[0], p[2]), stem)),
         .add(.stroke(line(p[3], p[4], p[5], p[6]), stem)),
         .add(.stroke(line(p[7], p[8], p[9], p[10]), stem))]
    },
    // The two short strokes above the k.
    Letter(name: "ray-up", color: aqua, p: [553.32, 18.66, 549.20, 46.84], steps: [1, 1, 1, 1]) { p in
        [.add(.stroke(line(p[0], p[1], p[2], p[3]), ray))]
    },
    Letter(name: "ray-right", color: aqua, p: [577.00, 66.06, 601.02, 41.05], steps: [1, 1, 1, 1]) { p in
        [.add(.stroke(line(p[0], p[1], p[2], p[3]), ray))]
    },
]

// MARK: Outlines

/// The letter as one filled outline: strokes outlined with round caps and joins, then merged.
func outline(_ letter: Letter) -> CGPath {
    func shape(_ s: Shape) -> CGPath {
        switch s {
        case .stroke(let path, let width): path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        case .fill(let path): path
        }
    }
    var merged: CGPath = CGMutablePath()
    for op in letter.build(letter.p) {
        switch op {
        case .add(let s): merged = merged.union(shape(s))
        case .cut(let s): merged = merged.subtracting(shape(s))
        }
    }
    let result = CGMutablePath()
    for contour in contours(merged) {
        for element in contour {
            switch element {
            case .move(let p): result.move(to: p)
            case .line(let p): result.addLine(to: p)
            case .curve(let c1, let c2, let p): result.addCurve(to: p, control1: c1, control2: c2)
            case .close: result.closeSubpath()
            }
        }
    }
    return result
}

enum Element {
    case move(CGPoint), line(CGPoint), curve(CGPoint, CGPoint, CGPoint), close
}

/// The path's contours in cubic curves and lines. Merging can leave hairline slivers where two
/// outlines touch; a contour with (almost) no area is dropped. The area is measured on the control
/// polygon, which is close enough to tell a sliver from a counter.
func contours(_ path: CGPath) -> [[Element]] {
    var all: [[Element]] = []
    var current = CGPoint.zero
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: current = e.points[0]; all.append([.move(current)])
        case .addLineToPoint: current = e.points[0]; all[all.count - 1].append(.line(current))
        case .addQuadCurveToPoint:
            // A quadratic is the same curve as this cubic.
            let c = e.points[0], end = e.points[1]
            let c1 = CGPoint(x: current.x + 2 / 3 * (c.x - current.x), y: current.y + 2 / 3 * (c.y - current.y))
            let c2 = CGPoint(x: end.x + 2 / 3 * (c.x - end.x), y: end.y + 2 / 3 * (c.y - end.y))
            all[all.count - 1].append(.curve(c1, c2, end)); current = end
        case .addCurveToPoint:
            all[all.count - 1].append(.curve(e.points[0], e.points[1], e.points[2])); current = e.points[2]
        case .closeSubpath: all[all.count - 1].append(.close)
        @unknown default: break
        }
    }
    return all.filter { contour in
        let polygon = contour.flatMap { element -> [CGPoint] in
            switch element {
            case .move(let p), .line(let p): [p]
            case .curve(let c1, let c2, let p): [c1, c2, p]
            case .close: []
            }
        }
        let area = zip(polygon, polygon.dropFirst() + polygon.prefix(1)).reduce(0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }
        return abs(area) / 2 > 1
    }
}

/// The master's frame in reference pixels: the lettering with a 3 px margin.
let frame = CGRect(x: 14, y: 6, width: 600, height: 178)

func svgData(_ path: CGPath) -> String {
    func n(_ v: CGFloat) -> String {
        var s = String(format: "%.2f", Double(v))
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }
    func p(_ q: CGPoint) -> String { "\(n(q.x - frame.minX)) \(n(q.y - frame.minY))" }
    return contours(path).joined().map { element in
        switch element {
        case .move(let q): "M \(p(q))"
        case .line(let q): "L \(p(q))"
        case .curve(let c1, let c2, let q): "C \(p(c1)) \(p(c2)) \(p(q))"
        case .close: "Z"
        }
    }.joined(separator: " ")
}

func writeMaster() throws {
    var svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(frame.width))" height="\(Int(frame.height))" viewBox="0 0 \(Int(frame.width)) \(Int(frame.height))" fill-rule="evenodd">
      <title>Sidefolk</title>
      <desc>Generated by scripts/wordmark.swift: heavy round-capped strokes, rings and round dots, merged into one filled outline per letter. No font dependency.</desc>

    """
    for letter in letters {
        svg += "  <path id=\"\(letter.name)\" fill=\"\(letter.color)\" d=\"\(svgData(outline(letter)))\"/>\n"
    }
    svg += "</svg>\n"
    try svg.write(to: masterURL, atomically: true, encoding: .utf8)
    print("wrote \(masterURL.path)")
}

// MARK: Comparing with the reference

/// Ink coverage of the reference (0…1) from its red channel, which separates both inks from the
/// near-white background; "Side" is navy and "folk" aqua, split at x = 332.
struct Reference {
    let image: CGImage
    let w: Int, h: Int
    var coverage: [Double]
    /// Which letter each inked pixel belongs to (nil for background).
    var owner: [String?]

    init() {
        let source = CGImageSourceCreateWithURL(referenceURL as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let w = image.width, h = image.height
        self.image = image; self.w = w; self.h = h
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = c.data!.assumingMemoryBound(to: UInt8.self)
        var coverage = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let ink = i % w < 332 ? 15.0 : 55.0
            coverage[i] = max(0, min(1, (245 - Double(px[i * 4])) / (245 - ink)))
        }
        self.coverage = coverage
        // Each pixel belongs to the letter whose construction covers it, or covers the pixel nearest to it.
        let ours = letters.map { render($0.build($0.p), in: CGRect(x: 0, y: 0, width: w, height: h)) }
        var owner = [String?](repeating: nil, count: w * h)
        for i in 0..<(w * h) where coverage[i] > 0.02 {
            let x = i % w, y = i / w
            search: for r in 0...5 {
                for dy in -r...r { for dx in -r...r where max(abs(dx), abs(dy)) == r {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    if let k = ours.firstIndex(where: { $0[ny * w + nx] > 0.5 }) { owner[i] = letters[k].name; break search }
                }}
            }
        }
        self.owner = owner
    }

    func target(_ name: String, in rect: CGRect) -> [Double] {
        var t: [Double] = []
        for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) {
            let i = y * w + x
            t.append(owner[i] == name ? coverage[i] : 0)
        }}
        return t
    }
}

/// Coverage of the construction in `rect` (reference pixels), one value per pixel.
func render(_ ops: [Op], in rect: CGRect) -> [Double] {
    let w = Int(rect.width), h = Int(rect.height)
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    c.translateBy(x: 0, y: Double(h)); c.scaleBy(x: 1, y: -1); c.translateBy(x: -rect.minX, y: -rect.minY)
    c.setLineCap(.round); c.setLineJoin(.round)
    for op in ops {
        let (shape, gray): (Shape, CGFloat) = switch op { case .add(let s): (s, 1); case .cut(let s): (s, 0) }
        c.setFillColor(gray: gray, alpha: 1); c.setStrokeColor(gray: gray, alpha: 1)
        switch shape {
        case .stroke(let path, let width): c.setLineWidth(width); c.addPath(path); c.strokePath()
        case .fill(let path): c.addPath(path); c.fillPath()
        }
    }
    let d = c.data!.assumingMemoryBound(to: UInt8.self)
    return (0..<(w * h)).map { Double(d[$0]) / 255 }
}

func bounds(_ letter: Letter) -> CGRect {
    outline(letter).boundingBoxOfPath.insetBy(dx: -8, dy: -8).integral
        .intersection(CGRect(x: 0, y: 0, width: 638, height: 196))
}

/// Intersection over union of the construction's coverage and the reference's, for one letter.
func match(_ letter: Letter, _ ref: Reference) -> Double {
    let rect = bounds(letter)
    let ours = render(letter.build(letter.p), in: rect), theirs = ref.target(letter.name, in: rect)
    var inter = 0.0, union = 0.0
    for i in ours.indices { inter += min(ours[i], theirs[i]); union += max(ours[i], theirs[i]) }
    return inter / union
}

func fit(_ letter: inout Letter, _ ref: Reference) {
    let rect = bounds(letter)
    let theirs = ref.target(letter.name, in: rect)
    func loss(_ p: [Double]) -> Double {
        zip(render(letter.build(p), in: rect), theirs).reduce(0) { $0 + abs($1.0 - $1.1) } + letter.rule(p)
    }
    var best = loss(letter.p), steps = letter.steps
    while steps.max()! > 0.002 {
        var improved = false
        for i in letter.p.indices where steps[i] > 0 {
            for sign in [1.0, -1.0] {
                var trial = letter.p
                trial[i] += sign * steps[i]
                let l = loss(trial)
                if l < best { best = l; letter.p = trial; improved = true; break }
            }
        }
        if !improved { steps = steps.map { $0 * 0.6 } }
    }
}

// MARK: The fit sheet

func check(into dir: URL) throws {
    let ref = Reference()
    let s = 2.0, w = Double(ref.w) * s, h = Double(ref.h) * s
    let zoom = 5.0
    let zoomed = ["S", "e", "f", "k"].compactMap { name in letters.first { $0.name == name } }
    // One shared height, so the close-ups sit on the same baseline.
    let top0 = zoomed.map { bounds($0).minY }.min() ?? 0, bottom0 = zoomed.map { bounds($0).maxY }.max() ?? 0
    func closeUp(_ l: Letter) -> CGRect { let b = bounds(l); return CGRect(x: b.minX, y: top0, width: b.width, height: bottom0 - top0) }
    let zoomWidth = zoomed.map { closeUp($0).width * zoom }.reduce(0, +) + Double(zoomed.count - 1) * 16
    let zoomHeight = (bottom0 - top0) * zoom
    let width = max(w, zoomWidth) + 48, label = 30.0
    let height = 24 + 4 * (label + h + 12) + label + zoomHeight * 2 + 8 + label + 24
    let c = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: width, height: height))
    var top = height - 24
    func caption(_ text: String) {
        top -= label
        (text as NSString).draw(at: NSPoint(x: 24, y: top + 8), withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                                                                                .foregroundColor: NSColor(white: 0.25, alpha: 1)])
    }
    /// Draws reference-space content into a box whose top-left is (x, top), scaled by `scale`.
    func place(_ rect: CGRect, scale: Double, x: Double, _ body: (CGContext) -> Void) {
        c.saveGState()
        c.translateBy(x: x, y: top); c.scaleBy(x: scale, y: -scale); c.translateBy(x: -rect.minX, y: -rect.minY)
        body(c)
        c.restoreGState()
    }
    func drawReference(_ rect: CGRect, alpha: Double) {
        c.saveGState(); c.setAlpha(alpha); c.interpolationQuality = .none
        // Image space is y up; the box is y down.
        c.translateBy(x: rect.minX, y: rect.maxY); c.scaleBy(x: 1, y: -1)
        c.draw(ref.image.cropping(to: rect)!, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        c.restoreGState()
    }
    func drawOutline(_ letters: [Letter], lineWidth: Double) {
        c.setStrokeColor(CGColor(srgbRed: 0.9, green: 0, blue: 0.5, alpha: 1)); c.setLineWidth(lineWidth)
        for l in letters { c.addPath(outline(l)) }
        c.strokePath()
    }
    func drawDifference(_ rect: CGRect, letters: [Letter]) {
        let rw = Int(rect.width), rh = Int(rect.height)
        var ours = [Double](repeating: 0, count: rw * rh), theirs = [Double](repeating: 0, count: rw * rh)
        for l in letters {
            let r = render(l.build(l.p), in: rect), t = ref.target(l.name, in: rect)
            for i in ours.indices { ours[i] = max(ours[i], r[i]); theirs[i] = max(theirs[i], t[i]) }
        }
        let dc = CGContext(data: nil, width: rw, height: rh, bitsPerComponent: 8, bytesPerRow: rw * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let px = dc.data!.assumingMemoryBound(to: UInt8.self)
        for i in ours.indices {
            let both = min(ours[i], theirs[i]), refOnly = max(0, theirs[i] - ours[i]), oursOnly = max(0, ours[i] - theirs[i])
            px[i * 4] = UInt8(max(0, 1 - oursOnly - both * 0.75) * 255)
            px[i * 4 + 1] = UInt8(max(0, 1 - refOnly - oursOnly - both * 0.75) * 255)
            px[i * 4 + 2] = UInt8(max(0, 1 - refOnly - both * 0.75) * 255)
            px[i * 4 + 3] = 255
        }
        c.saveGState(); c.interpolationQuality = .none
        c.translateBy(x: rect.minX, y: rect.maxY); c.scaleBy(x: 1, y: -1)
        c.draw(dc.makeImage()!, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        c.restoreGState()
    }
    let all = CGRect(x: 0, y: 0, width: ref.w, height: ref.h)
    let scores = letters.map { "\($0.name) \(String(format: "%.1f", match($0, ref) * 100))%" }.joined(separator: " · ")
    caption("Reference (wordmark-reference.png)")
    place(all, scale: s, x: 24) { _ in drawReference(all, alpha: 1) }
    top -= h + 12
    caption("New vector wordmark, same size")
    place(all, scale: s, x: 24) { c in
        for l in letters {
            c.setFillColor(l.color == navy ? CGColor(srgbRed: 15 / 255, green: 45 / 255, blue: 91 / 255, alpha: 1)
                                           : CGColor(srgbRed: 46 / 255, green: 212 / 255, blue: 217 / 255, alpha: 1))
            c.addPath(outline(l)); c.fillPath()
        }
    }
    top -= h + 12
    caption("Overlay: reference faded, construction outline in magenta")
    place(all, scale: s, x: 24) { _ in drawReference(all, alpha: 0.45); drawOutline(letters, lineWidth: 0.6) }
    top -= h + 12
    caption("Difference: red only in the reference, blue only in the new wordmark. Match: \(scores)")
    place(all, scale: s, x: 24) { _ in drawDifference(all, letters: letters) }
    top -= h + 12
    caption("Close-ups (×\(Int(zoom))): overlay above, difference below")
    var x = 24.0
    for l in zoomed {
        let r = closeUp(l)
        place(r, scale: zoom, x: x) { _ in drawReference(r, alpha: 0.45); drawOutline([l], lineWidth: 0.25) }
        top -= zoomHeight + 8
        place(r, scale: zoom, x: x) { _ in drawDifference(r, letters: [l]) }
        top += zoomHeight + 8
        x += r.width * zoom + 16
    }
    let url = dir.appendingPathComponent("wordmark-fit.png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, c.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(dest), "Cannot write \(url.path)")
    print("wrote \(url.path)\n\(scores)")
}

// MARK: Main

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "--check" where args.count == 2:
    try check(into: URL(fileURLWithPath: args[1], relativeTo: root))
case "--fit":
    let ref = Reference()
    for i in letters.indices where args.count == 1 || args.contains(letters[i].name) {
        fit(&letters[i], ref)
        print("\(letters[i].name) \(String(format: "%.1f", match(letters[i], ref) * 100))%: p: [\(letters[i].p.map { String(format: "%.3f", $0) }.joined(separator: ", "))]")
    }
case nil:
    try writeMaster()
default:
    print("usage: swift scripts/wordmark.swift [--check <dir> | --fit [letters]]")
    exit(2)
}
