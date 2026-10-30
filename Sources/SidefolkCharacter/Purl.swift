import QuartzCore

/// Purl, the little mended friend, as a 2D cartoon (D59): a plush with a big soft-square linen head,
/// a stitched seam down its left side and a denim patch sewn over its top right corner; big eyes, a
/// smile and pink cheeks; a round denim body with a mustard patch, long soft arms and short legs.
/// Outlines measured off companions-2d/targets/purl.webp; parts painted (Art/purl).
extension Species {
    static let purl: Species = {
        Species(
            shading: .flat(denim, line: denimLine, light: 0.35),
            edge: nil,
            torso: Shapes.roundish(center: pt(102, 56), width: 66, height: 52, top: 0.86, squareness: 2.3),
            head: plushHead,
            neck: pt(100, 86),
            feet: [pt(85, 26), pt(119, 26)],
            foot: CGSize(width: 24, height: 16),
            footShading: .flat(denim, line: denimLine, light: 0.35),
            shoulders: (pt(74, 74), pt(130, 74)),
            arm: ArmStyle(shape: Paths.ellipse(pt(0, -17), 9.5, 21), shading: .flat(denim, line: denimLine, light: 0.35)),
            armTuck: -0.1,
            footShape: Paths.roundedRect(CGRect(x: -12, y: -7, width: 24, height: 16), 6),
            face: SoftFace(kind: .ink, eyes: (pt(77, 114), pt(129, 114)), mouth: pt(103, 103), scale: 1.15, cheeks: true,
                           temper: .smiling, iris: RGB(0x7A3E1E), eyeSize: 1.2, mouthSize: 1.3, ink: RGB(0x2A140C),
                           blush: RGB(0xFF9AA2), blushAt: (pt(69, 100), pt(136, 100)), blushSize: CGSize(width: 6, height: 3.2)),
            headShading: .flat(linen, line: line),
            collar: Collar(center: pt(102, 82), halfWidth: 30, sag: 3, height: 13, tail: 1.6),
            restingFrame: CGRect(x: 44, y: 20, width: 114, height: 142),
            markOffsets: [.zzz: pt(-10, 6), .dots: pt(16, -10), .question: pt(4, -2), .exclaim: pt(4, -2)]).painted("purl", nudge: ["torso": pt(0, 3)])
    }()

    private static let linen = RGB(0xF7D59C)
    private static let line = RGB(0x6E4A2A)
    private static let denim = RGB(0x4E66B0)
    private static let denimLine = RGB(0x232E58)

    private static var plushHead: CGPath {
        Paths.blob([pt(52, 150), pt(80, 158), pt(112, 162), pt(145, 158), pt(153, 148), pt(157, 128), pt(156, 105), pt(150, 92),
                    pt(130, 86), pt(100, 84), pt(70, 86), pt(52, 92), pt(45, 108), pt(44, 128), pt(46, 142)])
    }
}
