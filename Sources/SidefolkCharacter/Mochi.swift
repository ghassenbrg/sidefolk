import QuartzCore

/// Mochi, the brand mascot (D29): a white rabbit with a round bun of a head on a small round body,
/// big glossy navy eyes, a tiny nose, tall ears dipped in navy and a knitted scarf. Drawn frontal
/// after Resources/Brand/masters/mascot-mochi.png and the brand guide's expressions, feet on the
/// floor and ear tips low enough that a hop or a lift stays in view.
extension Species {
    static let mochi = Species(
        shading: Shading(colors: Palette.fur, locations: [0, 0.32, 0.6, 0.84, 1],
                         center: CGPoint(x: 0.34, y: 0.76), reach: CGSize(width: 0.98, height: 1.05)),
        edge: Palette.shellEdge,
        torso: Shapes.roundish(center: pt(100, 46), width: 66, height: 42, top: 0.86, squareness: 2),
        head: Shapes.roundish(center: pt(100, 101), width: 86, height: 74, top: 0.96, squareness: 2.05),
        neck: pt(100, 66),
        feet: [pt(87, 27), pt(113, 27)],
        foot: CGSize(width: 25, height: 15),
        footShading: nil,
        shoulders: (pt(72, 57), pt(128, 57)),
        arm: ArmStyle(shape: Paths.ellipse(pt(0, -9), 6.5, 11.5),
                      shading: Shading(colors: Palette.fur, locations: [0, 0.3, 0.6, 0.85, 1],
                                       center: CGPoint(x: 0.35, y: 0.7), reach: CGSize(width: 0.9, height: 0.9)),
                      edge: (Palette.shellEdge, 0.4)),
        // Eyes low and wide on the face, a little bigger than the folks' (scale): they carry the cuteness.
        face: SoftFace(kind: .ink, eyes: (pt(80, 89.5), pt(120, 89.5)), mouth: pt(100, 81.5),
                       nose: CGRect(x: 97, y: 88, width: 6, height: 3.6), scale: 1.14),
        appendages: [ear(base: pt(85, 127), angle: 0.3, side: -1), ear(base: pt(115, 127), angle: -0.3, side: 1)],
        collar: Collar(center: pt(100, 64), halfWidth: 30, sag: 4.5, height: 19, tail: 1.45),
        restingFrame: CGRect(x: 57, y: 20, width: 86, height: 156),
        markOffsets: [.zzz: pt(-20, 20), .dots: pt(22, -18), .question: pt(8, 0), .exclaim: pt(6, 0),
                      .sweat: pt(-6, -12), .waves: pt(-15, -6), .ticks: pt(-10, -14)])

    /// A tall rabbit ear rising from behind the head: slim where it joins, round at the top, the
    /// upper part dipped in navy. Asleep it folds back and down along the head.
    private static func ear(base: CGPoint, angle: CGFloat, side: CGFloat) -> AppendageSpec {
        let outline = Paths.blob([pt(-10, -4), pt(-15, 10), pt(-17.5, 23), pt(-18, 35), pt(-14, 46), pt(0, 51.5),
                                  pt(14, 46), pt(18, 35), pt(17.5, 23), pt(15, 10), pt(10, -4), pt(0, -7)])
        return AppendageSpec(base: base, angle: angle, side: side, layers: { _ in
            let root = Layers.canvas()
            let ear = SoftShape(outline, shading: Shading(colors: Palette.fur, locations: [0, 0.3, 0.6, 0.85, 1],
                                                           center: CGPoint(x: side < 0 ? 0.3 : 0.42, y: 0.55),
                                                           reach: CGSize(width: 0.95, height: 0.9)))
            ear.shadow(radius: 3, opacity: 0.14, offset: CGSize(width: -side, height: -1))
            ear.outline(Palette.shellEdge, alpha: 0.4, width: 0.8)
            root.addSublayer(ear.layer)
            // The navy cap ends in a soft curve, lower in the middle like the mascot's.
            let dip = CGMutablePath()
            dip.move(to: pt(-30, 28))
            dip.addQuadCurve(to: pt(30, 28), control: pt(0, 19))
            dip.addLine(to: pt(30, 80))
            dip.addLine(to: pt(-30, 80))
            dip.closeSubpath()
            let tip = SoftShape(outline.intersection(dip),
                                shading: Shading(colors: [RGB(0x44609A), RGB(0x2F477A), Palette.earTip, RGB(0x1A2B52), RGB(0x14213F)],
                                                 locations: [0, 0.3, 0.6, 0.85, 1], center: CGPoint(x: side < 0 ? 0.32 : 0.45, y: 0.82),
                                                 reach: CGSize(width: 0.95, height: 1.05)))
            root.addSublayer(tip.layer)
            return root
        }, outline: outline, floppiness: 1, fold: AppendageSpec.Fold(shift: pt(16, -7), turn: 2.15, length: 0.64))
    }
}
