import QuartzCore

/// Spark, the little cream robot: a dark face screen with glowing eyes, headphones, an antenna with
/// a ball on top, a chest badge, dark hands and feet. Proportions follow folk-family/spark/spark.png
/// (about 0.155 canvas units per pixel), drawn frontal. Its headphones, antenna ball, badge and eyes
/// take the style colour.
extension Species {
    static let spark = Species(
        shading: Shading(colors: Palette.cream, locations: [0, 0.3, 0.6, 0.84, 1],
                         center: CGPoint(x: 0.34, y: 0.76), reach: CGSize(width: 0.98, height: 1.05)),
        edge: Palette.creamEdge,
        torso: Shapes.roundish(center: pt(100, 58), width: 72, height: 44, top: 0.86, squareness: 2.3)
            .union(Paths.roundedRect(CGRect(x: 75, y: 25, width: 18, height: 16), 8))
            .union(Paths.roundedRect(CGRect(x: 107, y: 25, width: 18, height: 16), 8)),
        head: Shapes.roundish(center: pt(100, 113), width: 94, height: 72, top: 1.02, squareness: 2.55)
            .union(Paths.ellipse(pt(100, 149), 8, 6)),
        neck: pt(100, 82),
        feet: [pt(84, 26), pt(116, 26)],
        foot: CGSize(width: 30, height: 14),
        footShading: Shading(colors: Palette.darkPart, locations: [0, 0.3, 0.6, 0.85, 1],
                             center: CGPoint(x: 0.35, y: 0.8), reach: CGSize(width: 0.9, height: 1)),
        shoulders: (pt(66, 73), pt(134, 73)),
        arm: ArmStyle(shape: Shapes.nub(width: 11.5, length: 19),
                      shading: Shading(colors: Palette.cream, locations: [0, 0.3, 0.6, 0.85, 1],
                                       center: CGPoint(x: 0.35, y: 0.7), reach: CGSize(width: 0.9, height: 0.9)),
                      edge: (Palette.creamEdge, 0.4),
                      hand: (Paths.ellipse(pt(0, -19.5), 7.5, 6.5),
                             Shading(colors: Palette.darkPart, locations: [0, 0.3, 0.6, 0.85, 1],
                                     center: CGPoint(x: 0.35, y: 0.75), reach: CGSize(width: 0.9, height: 1)))),
        face: SoftFace(kind: .screen(CGRect(x: 61, y: 88, width: 78, height: 46), radius: 20),
                       eyes: (pt(84, 111), pt(116, 111)), mouth: pt(100, 96), scale: 0.8),
        appendages: [antenna],
        gear: [Gear(mount: .head, draw: headphones,
                    outline: Paths.ellipse(pt(48, 110), 9, 18).union(Paths.ellipse(pt(152, 110), 9, 18))),
               Gear(mount: .body, draw: badge)],
        collar: Collar(center: pt(100, 80), halfWidth: 30, sag: 2, height: 12),
        restingFrame: CGRect(x: 52, y: 20, width: 96, height: 160),
        markOffsets: [.zzz: pt(16, 6), .dots: pt(18, 4), .waves: pt(4, 13), .question: pt(4, 4)])

    /// A dark stalk leaning right with a glossy ball in the style colour; it bobs and trails stiffly.
    private static var antenna: AppendageSpec {
        let stalk = CGMutablePath()
        stalk.move(to: pt(0, 0))
        stalk.addQuadCurve(to: pt(1.5, 15), control: pt(-1.5, 8))
        return AppendageSpec(base: pt(100, 151), angle: -0.24, side: 1, layers: { accent in
            let root = Layers.canvas()
            root.addSublayer(Layers.shape(stalk, stroke: Palette.darkPart[2].cg(), lineWidth: 3.4))
            let ball = SoftShape(Paths.circle(pt(1.5, 20.5), 6.8), shading: .tinted(accent))
            ball.shadow(radius: 2, opacity: 0.18, offset: CGSize(width: 0, height: -1))
            root.addSublayer(ball.layer)
            root.addSublayer(Layers.shape(Paths.circle(pt(-1, 23.5), 2), fill: RGB.white.cg(0.75)))
            return root
        }, outline: Paths.roundedRect(CGRect(x: -4, y: 0, width: 8, height: 16), 3).union(Paths.circle(pt(1.5, 20.5), 7)),
        floppiness: 0.7)
    }

    /// Cream ear cups on a band of the style colour, one each side of the head.
    private static func headphones(_ accent: RGB) -> CALayer {
        let root = Layers.canvas()
        for side in [-1.0, 1.0] {
            let band = SoftShape(Paths.ellipse(pt(100 + side * 46, 110), 6, 18.5), shading: .tinted(accent))
            root.addSublayer(band.layer)
            let cup = SoftShape(Paths.ellipse(pt(100 + side * 51, 110), 7, 15.5),
                                shading: Shading(colors: Palette.cream, locations: [0, 0.3, 0.6, 0.85, 1],
                                                 center: CGPoint(x: side < 0 ? 0.3 : 0.45, y: 0.75), reach: CGSize(width: 0.9, height: 0.95)))
            cup.shadow(radius: 2, opacity: 0.16, offset: CGSize(width: side, height: -1))
            cup.outline(Palette.creamEdge, alpha: 0.45, width: 0.7)
            root.addSublayer(cup.layer)
        }
        return root
    }

    /// The little shield on its chest.
    private static func badge(_ accent: RGB) -> CALayer {
        let c = pt(111, 66)
        let shield = CGMutablePath()
        shield.move(to: c + pt(-4.5, 4))
        shield.addLine(to: c + pt(4.5, 4))
        shield.addQuadCurve(to: c + pt(0, -5), control: c + pt(4.5, -3))
        shield.addQuadCurve(to: c + pt(-4.5, 4), control: c + pt(-4.5, -3))
        shield.closeSubpath()
        return Layers.shape(shield, fill: accent.cg())
    }
}
