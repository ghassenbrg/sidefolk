import Foundation
import ImageIO
import QuartzCore

/// A painted part (D59): an image drawn in place of a part's flat vector drawing. Its vector shape
/// stays what takes clicks, anchors bubbles and places the image: the image is fitted over it.
struct Painted {
    var image: CGImage
    /// Where it is drawn, in the part's own units (canvas units; the arm's, ear's or tail's own for those).
    var rect: CGRect

    /// Turned (radians) and mirrored left to right around its middle: a part painted lying another way.
    var turn: CGFloat = 0
    var mirrored = false

    /// The painting `name` ("ember/head", from `Art/` in this module) fitted over `outline`: centred on it,
    /// as large in area as its bounds and in its own proportions, then moved by `nudge`, grown by `grow` and
    /// stretched sideways by `widen` (a body painted a little slimmer than the target's).
    @MainActor init?(_ name: String, over outline: CGPath, nudge: CGPoint = .zero, grow: CGFloat = 1, widen: CGFloat = 1,
                     turn: CGFloat = 0, mirrored: Bool = false) {
        guard let image = Art.image(name) else { return nil }
        let box = outline.boundingBoxOfPath
        let size = CGSize(width: image.width, height: image.height)
        let scale = (box.width * box.height / (size.width * size.height)).squareRoot() * grow
        let drawn = CGSize(width: size.width * scale * widen, height: size.height * scale)
        self.image = image
        self.turn = turn
        self.mirrored = mirrored
        rect = CGRect(x: box.midX - drawn.width / 2 + nudge.x, y: box.midY - drawn.height / 2 + nudge.y,
                      width: drawn.width, height: drawn.height)
    }

    @MainActor var layer: CALayer {
        let layer = CALayer()
        layer.frame = rect
        layer.contents = image
        layer.contentsGravity = .resize
        // Shrunk a lot on screen: filtered across mip levels so its outlines stay smooth, not jagged.
        layer.minificationFilter = .trilinear
        layer.setAffineTransform(CGAffineTransform(rotationAngle: turn).scaledBy(x: mirrored ? -1 : 1, y: 1))
        return layer
    }
}

/// The painted parts of a companion that has them; parts left out keep their flat drawing.
struct Painting {
    var head: Painted?
    var torso: Painted?
    /// Left and right, in the arm's own units (the shoulder at the origin, hanging down).
    var arms: (Painted, Painted)?
    /// Left and right, around each foot's centre.
    var feet: (Painted, Painted)?
}

/// The paintings shipped in this module (Art/<companion>/<part>.png, cut by companions-2d/parts/cut.py).
@MainActor
enum Art {
    private static var cache: [String: CGImage] = [:]

    static func image(_ name: String) -> CGImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Art"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        cache[name] = image
        return image
    }
}

extension Species {
    /// This companion drawn with its paintings (Art/<name>/head, torso, armL, armR, footL, footR), each fitted over
    /// its outline here; `head` and `torso` give a larger outline when the painting holds more (hair painted with the
    /// head). Parts without a painting keep their flat drawing; the outlines still take clicks.
    /// `nudge` and `grow` adjust a part by name: a body nudged up and grown sits wide under the chin, with no pinched
    /// neck between head and shoulders (painted bodies start slim at the top).
    func painted(_ name: String, head: CGPath? = nil, torso: CGPath? = nil, nudge: [String: CGPoint] = [:],
                 grow: [String: CGFloat] = [:], widen: [String: CGFloat] = [:]) -> Species {
        func part(_ part: String, _ outline: CGPath?) -> Painted? {
            outline.flatMap {
                Painted("\(name)/\(part)", over: $0, nudge: nudge[part] ?? .zero, grow: grow[part] ?? 1, widen: widen[part] ?? 1)
            }
        }
        let arm = arm.hand.map { arm.shape.union($0.path) } ?? arm.shape
        let mirror = CGAffineTransform(scaleX: self.arm.outward ? -1 : 1, y: 1)
        let foot = footShape ?? Paths.ellipse(.zero, self.foot.width / 2, self.foot.height / 2)
        var species = self
        species.painting = Painting(
            head: part("head", head ?? self.head), torso: part("torso", torso ?? self.torso),
            arms: part("armL", Paths.transformed(arm, mirror)).flatMap { left in part("armR", arm).map { (left, $0) } },
            feet: feet.isEmpty ? nil : part("footL", foot).flatMap { left in part("footR", foot).map { (left, $0) } })
        return species
    }
}
