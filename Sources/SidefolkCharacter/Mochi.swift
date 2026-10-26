import QuartzCore

/// Mochi, the brand mascot (D29): a white rabbit with tall navy-tipped ears, navy bead eyes, a
/// tiny nose and a knitted scarf. Proportions follow Resources/Brand/masters/mascot-mochi.png
/// (0.16 canvas units per pixel, feet on the floor, ear tips just under the canvas top so a hop
/// stays in view), drawn frontal.
extension Species {
    static let mochi = Species(
        shading: Shading(colors: Palette.fur, locations: [0, 0.32, 0.6, 0.84, 1],
                         center: CGPoint(x: 0.34, y: 0.76), reach: CGSize(width: 0.98, height: 1.05)),
        edge: Palette.shellEdge,
        torso: Shapes.roundish(center: pt(100, 48), width: 74, height: 44, top: 0.84, squareness: 2.15),
        head: Shapes.roundish(center: pt(100, 99), width: 90, height: 68, top: 0.93, squareness: 2.15),
        neck: pt(100, 68),
        feet: [pt(85, 26.5), pt(115, 26.5)],
        foot: CGSize(width: 27, height: 14),
        footShading: nil,
        shoulders: (pt(69, 60), pt(131, 60)),
        arm: ArmStyle(shape: Shapes.nub(width: 12.5, length: 20),
                      shading: Shading(colors: Palette.fur, locations: [0, 0.3, 0.6, 0.85, 1],
                                       center: CGPoint(x: 0.35, y: 0.7), reach: CGSize(width: 0.9, height: 0.9)),
                      edge: (Palette.shellEdge, 0.4)),
        face: SoftFace(kind: .ink, eyes: (pt(82, 92), pt(118, 92)), mouth: pt(100, 84),
                       nose: CGRect(x: 97, y: 90.2, width: 6, height: 3.6)),
        appendages: [ear(base: pt(83, 126), angle: 0.34, side: -1), ear(base: pt(117, 126), angle: -0.34, side: 1)],
        collar: Collar(center: pt(100, 63), halfWidth: 32, sag: 4.5, height: 16.5),
        restingFrame: CGRect(x: 55, y: 20, width: 90, height: 160),
        markOffsets: [.zzz: pt(-20, 20), .dots: pt(22, -18), .question: pt(8, 0), .exclaim: pt(6, 0),
                      .sweat: pt(-6, -12), .waves: pt(-15, -6), .ticks: pt(-10, -14)])

    /// A long rabbit ear standing on its base, its upper half dipped in navy.
    private static func ear(base: CGPoint, angle: CGFloat, side: CGFloat) -> AppendageSpec {
        let outline = Paths.blob([pt(-10, -3), pt(-15, 12), pt(-19, 28), pt(-19.5, 41), pt(-13, 52), pt(0, 57),
                                  pt(13, 52), pt(19.5, 41), pt(19, 28), pt(15, 12), pt(10, -3), pt(0, -6)])
        return AppendageSpec(base: base, angle: angle, side: side, layers: { _ in
            let root = Layers.canvas()
            let ear = SoftShape(outline, shading: Shading(colors: Palette.fur, locations: [0, 0.3, 0.6, 0.85, 1],
                                                           center: CGPoint(x: side < 0 ? 0.3 : 0.42, y: 0.55),
                                                           reach: CGSize(width: 0.95, height: 0.9)))
            ear.shadow(radius: 3, opacity: 0.14, offset: CGSize(width: -side, height: -1))
            ear.outline(Palette.shellEdge, alpha: 0.4, width: 0.8)
            root.addSublayer(ear.layer)
            // The navy tip ends in a soft curve, lower in the middle like the mascot's.
            let dip = CGMutablePath()
            dip.move(to: pt(-30, 31))
            dip.addQuadCurve(to: pt(30, 31), control: pt(0, 22))
            dip.addLine(to: pt(30, 80))
            dip.addLine(to: pt(-30, 80))
            dip.closeSubpath()
            let tip = SoftShape(outline.intersection(dip),
                                shading: Shading(colors: [RGB(0x40588F), RGB(0x2E4476), Palette.earTip, RGB(0x1A2B52), RGB(0x14213F)],
                                                 locations: [0, 0.28, 0.58, 0.84, 1], center: CGPoint(x: side < 0 ? 0.3 : 0.45, y: 0.8),
                                                 reach: CGSize(width: 0.95, height: 1.1)))
            root.addSublayer(tip.layer)
            return root
        }, outline: outline, floppiness: 1)
    }
}
