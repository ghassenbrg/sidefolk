import QuartzCore

/// Spark, the little robot, as a 2D cartoon (D59): a wide warm-white helmet with a dark navy face
/// screen and glowing eyes, round headphones, an antenna with a ball on top; a small body with navy
/// shoulder caps and waistband, a shield on its chest, white arms ending in navy mittens and white legs
/// in navy boots. Outlines measured off companions-2d/targets/spark.webp; parts painted (Art/spark). Its
/// glowing eyes take the style colour.
extension Species {
    static let spark = Species(
        shading: .flat(shell, line: line),
        edge: nil,
        torso: Shapes.roundish(center: pt(100, 64), width: 50, height: 38, top: 1.08, squareness: 2.6)
            .union(Paths.roundedRect(CGRect(x: 77, y: 24, width: 19, height: 28), 7))
            .union(Paths.roundedRect(CGRect(x: 104, y: 24, width: 19, height: 28), 7)),
        head: Shapes.roundish(center: pt(100, 117), width: 88, height: 68, top: 1.0, squareness: 2.9)
            .union(Paths.ellipse(pt(53, 116), 11, 21)).union(Paths.ellipse(pt(147, 116), 11, 21)),
        neck: pt(100, 84),
        feet: [pt(85, 23), pt(115, 23)],
        foot: CGSize(width: 24, height: 13),
        footShading: .flat(navy, line: line, light: 0.4),
        shoulders: (pt(78, 78), pt(122, 78)),
        arm: ArmStyle(shape: Paths.roundedRect(CGRect(x: -6.5, y: -26, width: 13, height: 30), 6.5), shading: .flat(shell, line: line),
                      hand: (Paths.ellipse(pt(0, -29), 9, 8).union(Paths.ellipse(pt(7, -27), 3.5, 4.5)), .flat(navy, line: line, light: 0.4))),
        armTuck: -0.1,
        face: SoftFace(kind: .screen(CGRect(x: 66, y: 92, width: 68, height: 49), radius: 18),
                       eyes: (pt(83, 117), pt(117, 117)), mouth: pt(100, 106), scale: 1.0),
        appendages: [antenna],
        collar: Collar(center: pt(100, 80), halfWidth: 24, sag: 2, height: 11),
        restingFrame: CGRect(x: 52, y: 20, width: 96, height: 160),
        markOffsets: [.zzz: pt(16, 6), .dots: pt(18, 4), .waves: pt(4, 13), .question: pt(4, 4)]).painted("spark", nudge: ["torso": pt(0, 4)], grow: ["torso": 1.06])

    private static let shell = RGB(0xFFF8F1)
    private static let line = RGB(0x1E2B4A)
    private static let navy = RGB(0x253A72)

    /// The antenna, painted leaning right with its glowing ball; it bobs and trails stiffly.
    private static var antenna: AppendageSpec {
        let outline = Paths.transformed(Paths.roundedRect(CGRect(x: -4, y: 0, width: 8, height: 16), 3).union(Paths.circle(pt(2, 22), 9.5)),
                                        CGAffineTransform(rotationAngle: -0.3))
        return AppendageSpec(base: pt(100, 149), angle: 0, side: 1, layers: { accent in
            Painted("spark/antenna", over: outline)?.layer ?? Cel.part(outline, accent, line: line)
        }, outline: outline, floppiness: 0.7)
    }
}
