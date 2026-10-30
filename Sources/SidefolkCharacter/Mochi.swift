import QuartzCore

/// Mochi, the brand mascot (D29), as a 2D cartoon (D59): a white rabbit with a round bun of a head on
/// a small round body, big navy eyes that glow blue at the bottom, pink cheeks, a tiny navy nose, tall
/// ears dipped in navy with pink insides, and a knitted scarf. Drawn frontal after
/// companions-3d/references/mochi-sheet-model.webp in the flat style of companions-2d/references/lineup-2d.webp,
/// feet on the floor and ear tips low enough that a hop or a lift stays in view.
extension Species {
    static let mochi = Species(
        shading: .flat(RGB(0xFFFFFF), shade: RGB(0xE6E4F1), line: RGB(0x6E7393)),
        edge: nil,
        torso: Shapes.roundish(center: pt(100, 46), width: 64, height: 42, top: 0.86, squareness: 2),
        head: Shapes.roundish(center: pt(100, 100), width: 90, height: 76, top: 0.96, squareness: 2.05),
        neck: pt(100, 66),
        feet: [pt(87, 26), pt(113, 26)],
        foot: CGSize(width: 24, height: 14),
        footShading: nil,
        shoulders: (pt(72, 57), pt(128, 57)),
        arm: ArmStyle(shape: Paths.ellipse(pt(0, -9), 6.5, 11.5),
                      shading: .flat(RGB(0xFFFFFF), shade: RGB(0xE6E4F1), line: RGB(0x6E7393))),
        // Big eyes low and wide on the face, a tiny nose between them and a mouth below.
        face: SoftFace(kind: .ink, eyes: (pt(80, 92), pt(120, 92)), mouth: pt(100, 81.5),
                       nose: CGRect(x: 96.8, y: 87.6, width: 6.4, height: 4), scale: 1.12, cheeks: true, temper: .smiling,
                       iris: RGB(0x2F74E0), eyeSize: 1.18, ink: RGB(0x0B2D5B), blush: RGB(0xFFB3C3)),
        // A slight outward lean, one ear a touch more than the other, so it looks alive.
        appendages: [ear(base: pt(84, 127), angle: 0.2, side: -1), ear(base: pt(116, 127), angle: -0.25, side: 1)],
        collar: Collar(center: pt(100, 64), halfWidth: 30, sag: 4.5, height: 19, tail: 1.45),
        restingFrame: CGRect(x: 55, y: 20, width: 90, height: 168),
        markOffsets: [.zzz: pt(-20, 20), .dots: pt(22, -18), .question: pt(8, 0), .exclaim: pt(6, 0),
                      .sweat: pt(-6, -12), .waves: pt(-15, -6), .ticks: pt(-10, -14)],
        // Its tall ears would leave the window when it hops or is lifted at full size.
        scale: 0.95)

    /// A tall rabbit ear rising from behind the head: a long oval, slim where it joins, widening to a
    /// fully round tip, its top two fifths dipped in navy, a pink inside below. Asleep it lies back
    /// behind the head, only the round tips showing over it.
    private static func ear(base: CGPoint, angle: CGFloat, side: CGFloat) -> AppendageSpec {
        let outline = Paths.blob([pt(-9, -4), pt(-13, 8), pt(-17, 20), pt(-19.5, 32), pt(-20, 43), pt(-17.5, 53),
                                  pt(-11, 60), pt(0, 63.5), pt(11, 60), pt(17.5, 53), pt(20, 43), pt(19.5, 32),
                                  pt(17, 20), pt(13, 8), pt(9, -4), pt(0, -7)])
        return AppendageSpec(base: base, angle: angle, side: side, layers: { _ in
            let root = Layers.canvas()
            let line = RGB(0x6E7393)
            root.addSublayer(SoftShape(outline, shading: .flat(RGB(0xFFFFFF), shade: RGB(0xE6E4F1), line: line)).layer)
            // The pink inside, a narrow oval from near the base up into the navy.
            let inner = Paths.blob([pt(-4.5, 6), pt(-8, 17), pt(-9.5, 29), pt(-8.5, 39), pt(0, 46), pt(8.5, 39), pt(9.5, 29),
                                    pt(8, 17), pt(4.5, 6), pt(0, 3)])
            root.addSublayer(Layers.shape(inner, fill: RGB(0xFFC9D2).cg()))
            root.addSublayer(Layers.shape(inner.subtracting(Paths.translated(inner, -1.5, 2.6)), fill: RGB(0xF4A9B8).cg()))
            // The navy cap ends in a soft curve, lower in the middle and on the outer side, like the mascot's.
            let dip = CGMutablePath()
            dip.move(to: pt(-30, 45 + 3 * side))
            dip.addQuadCurve(to: pt(30, 45 - 3 * side), control: pt(0, 33))
            dip.addLine(to: pt(30, 80))
            dip.addLine(to: pt(-30, 80))
            dip.closeSubpath()
            let tip = SoftShape(outline.intersection(dip), shading: .flat(RGB(0x1E3A8A), shade: RGB(0x172C6B), line: RGB(0x12224F)))
            root.addSublayer(tip.layer)
            return root
        }, outline: outline, floppiness: 1, fold: AppendageSpec.Fold(shift: pt(0, -3), turn: -0.1, length: 0.4))
    }
}
