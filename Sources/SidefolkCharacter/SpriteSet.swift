import CoreGraphics
import Foundation
import ImageIO

/// The poses every sprite companion is drawn in: `<pose>.png` in its folder.
enum SpritePose: String, CaseIterable, Sendable {
    case idle, blink, listen, think, work1, work2, write1, write2, note, alert, sad, done, wave, sit, sleep, dangle
}

/// One sprite companion's art, placed in the character canvas. Pose files may differ in size and
/// margins: each is measured, scaled like the idle pose (which stands as tall as the vector robot),
/// stood on the floor line by the bottom of its opaque pixels and centered on its feet, then drawn
/// once into a canvas-sized bitmap. Every pose then shares one frame, so the image layer can swap
/// and crossfade them freely. Load a set once and share it; `CharacterLook` compares by identity.
@MainActor
public final class SpriteSet {
    /// The folder's name, e.g. "mochi".
    public let name: String
    private let files: [SpritePose: URL]
    /// Source pixels to canvas units, the same for every pose so they keep their relative sizes.
    private let unitsPerPixel: CGFloat
    /// The idle pose's opaque bounds, in canvas units.
    let restingFrame: CGRect
    private var drawn: [SpritePose: Drawing] = [:]

    /// The idle pose stands this tall: the vector robot's height from feet to fin.
    static let height: CGFloat = 158
    /// Bitmap pixels per canvas unit: the largest companion on a Retina screen needs about 1.6.
    static let pixelsPerUnit: CGFloat = 2

    /// Nil unless every pose has a file and the idle pose can be read; such a companion is not offered.
    public init?(folder: URL) {
        var files: [SpritePose: URL] = [:]
        for pose in SpritePose.allCases {
            let file = folder.appendingPathComponent("\(pose.rawValue).png")
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            files[pose] = file
        }
        guard let idle = Self.load(files[.idle]!), let body = Self.measure(idle) else { return nil }
        unitsPerPixel = Self.height / body.bounds.height
        restingFrame = CGRect(x: Canvas.pivot.x + (body.bounds.minX - body.feet) * unitsPerPixel, y: Canvas.floor,
                              width: body.bounds.width * unitsPerPixel, height: Self.height)
        name = folder.lastPathComponent
        self.files = files
        drawn[.idle] = draw(idle, body)
    }

    /// The pose as a canvas-sized image (200×200 units).
    func image(_ pose: SpritePose) -> CGImage { drawing(pose).image }

    /// The pose's visible shape in canvas units, so clicks pass through its transparent pixels.
    func silhouette(_ pose: SpritePose) -> CGPath { drawing(pose).outline }

    private struct Drawing {
        let image: CGImage
        let outline: CGPath
    }

    /// Drawn on first use. A pose file that can't be read shows the idle pose rather than nothing.
    private func drawing(_ pose: SpritePose) -> Drawing {
        if let done = drawn[pose] { return done }
        guard let source = files[pose].flatMap(Self.load), let body = Self.measure(source) else { return drawing(.idle) }
        let result = draw(source, body)
        drawn[pose] = result
        return result
    }

    private func draw(_ source: CGImage, _ body: Measure) -> Drawing {
        let side = Int(Canvas.size.width * Self.pixelsPerUnit)
        let context = Self.bitmap(width: side, height: side)
        context.interpolationQuality = .high
        // Source pixels run from the top-left; the canvas runs up from the bottom-left.
        let scale = unitsPerPixel * Self.pixelsPerUnit
        let frame = CGRect(x: (Canvas.pivot.x - body.feet * unitsPerPixel) * Self.pixelsPerUnit,
                           y: (Canvas.floor - (CGFloat(source.height) - body.bounds.maxY) * unitsPerPixel) * Self.pixelsPerUnit,
                           width: CGFloat(source.width) * scale, height: CGFloat(source.height) * scale)
        context.draw(source, in: frame)
        return Drawing(image: context.makeImage()!, outline: Self.outline(context, side: side))
    }

    // MARK: Alpha

    /// Coverage that counts as the character: soft, anti-aliased edges and faint fringes don't.
    private static let solid = UInt8(0.35 * 255)

    private struct Measure {
        /// Opaque bounds in source pixels, from the top-left.
        var bounds: CGRect
        /// Where the feet are across: the middle of the lowest eighth of the opaque pixels.
        var feet: CGFloat
    }

    private static func measure(_ image: CGImage) -> Measure? {
        // A quarter-megapixel copy is precise to a pixel or two of the source, and quick.
        let step = max(1, Int((CGFloat(max(image.width, image.height)) / 512).rounded(.up)))
        let width = (image.width + step - 1) / step, height = (image.height + step - 1) / step
        let context = bitmap(width: width, height: height)
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let alpha = context.data!.assumingMemoryBound(to: UInt8.self)
        func solid(_ x: Int, _ y: Int) -> Bool { alpha[(y * width + x) * 4 + 3] >= Self.solid }

        var top = height, bottom = -1, left = width, right = -1
        for y in 0..<height {
            for x in 0..<width where solid(x, y) {
                top = min(top, y); bottom = max(bottom, y)
                left = min(left, x); right = max(right, x)
            }
        }
        guard bottom >= top else { return nil }
        let band = max(1, (bottom - top + 1) / 8)
        var feetLeft = width, feetRight = -1
        for y in (bottom - band + 1)...bottom {
            for x in left...right where solid(x, y) {
                feetLeft = min(feetLeft, x); feetRight = max(feetRight, x)
            }
        }
        let s = CGFloat(step)
        return Measure(bounds: CGRect(x: CGFloat(left) * s, y: CGFloat(top) * s,
                                      width: CGFloat(right - left + 1) * s, height: CGFloat(bottom - top + 1) * s),
                       feet: CGFloat(feetLeft + feetRight + 1) / 2 * s)
    }

    /// Solid cells of 2×2 canvas units as one rectangle per run along each row: finer than a
    /// pointer needs, and built once per pose.
    private static func outline(_ context: CGContext, side: Int) -> CGPath {
        let alpha = context.data!.assumingMemoryBound(to: UInt8.self)
        let cell = Int(2 * pixelsPerUnit), cells = side / cell
        let unit = CGFloat(cell) / pixelsPerUnit
        let path = CGMutablePath()
        for row in 0..<cells {
            // Bitmap rows run top to bottom; the canvas runs bottom to top.
            let y = CGFloat(cells - 1 - row) * unit
            var start: Int?
            for column in 0...cells {
                var inside = false
                if column < cells {
                    var sum = 0
                    for dy in 0..<cell {
                        for dx in 0..<cell { sum += Int(alpha[((row * cell + dy) * side + column * cell + dx) * 4 + 3]) }
                    }
                    inside = sum / (cell * cell) >= Int(solid)
                }
                if inside, start == nil { start = column }
                if !inside, let first = start {
                    path.addRect(CGRect(x: CGFloat(first) * unit, y: y, width: CGFloat(column - first) * unit, height: unit))
                    start = nil
                }
            }
        }
        return path
    }

    private static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func bitmap(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
}

extension SpriteSet: Equatable {
    nonisolated public static func == (a: SpriteSet, b: SpriteSet) -> Bool { a === b }
}
