import QuartzCore

/// Folio, the folded little wish, as a 2D cartoon (D59): a coral paper pentagon pointed at the top, its
/// top right corner folded down to show the cream back of the paper, deeper red facets down its sides,
/// paper wings for arms pointing out and down, two trapezoid paper legs, very big eyes, a wide smile
/// and soft cheeks. Outlines measured off companions-2d/targets/folio.webp; parts painted (Art/folio).
extension Species {
    static let folio = Species(
        shading: .flat(coral, line: line),
        edge: nil,
        torso: Paths.polyline([pt(103, 156), pt(160, 118), pt(155, 88), pt(146, 36), pt(55, 36), pt(46, 88), pt(41, 118)], closed: true),
        head: nil,
        neck: pt(100, 90),
        feet: [pt(76, 28), pt(126, 28)],
        foot: CGSize(width: 30, height: 18),
        footShading: .flat(coral.darker(0.04), line: line, light: 0),
        shoulders: (pt(46, 84), pt(154, 84)),
        arm: ArmStyle(shape: Paths.polyline([pt(-3, 4), pt(21, -25), pt(5, -37), pt(-3, -28)], closed: true),
                      shading: .flat(coral.darker(0.04), line: line, light: 0), outward: true),
        armTuck: 0.4,
        footShape: Paths.polyline([pt(-10, 9), pt(10, 9), pt(15, -8), pt(-15, -8)], closed: true),
        face: SoftFace(kind: .ink, eyes: (pt(74, 88), pt(126, 88)), mouth: pt(101, 77), scale: 1.3, cheeks: true,
                       temper: .smiling, iris: RGB(0x6E3424), eyeSize: 1.32, mouthSize: 1.35, ink: RGB(0x2A0E0A),
                       blush: RGB(0xFFA4A0), blushAt: (pt(66, 70), pt(134, 70)), blushSize: CGSize(width: 6.2, height: 3.6)),
        collar: Collar(center: pt(100, 50), halfWidth: 44, sag: 3, height: 13),
        restingFrame: CGRect(x: 40, y: 20, width: 120, height: 138),
        markOffsets: [.zzz: pt(-10, -6), .dots: pt(14, -16), .question: pt(4, -12), .exclaim: pt(4, -12)]).painted("folio")

    private static let coral = RGB(0xF47C78)
    private static let line = RGB(0x7A2228)
}
