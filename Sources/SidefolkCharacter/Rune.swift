import QuartzCore

/// Rune, the pocket golem, as a 2D cartoon (D59): a domed boulder of a head with clumps of moss on its
/// top, big eyes, a wide smile and pink cheeks; a stone body with an amber gem at its heart, big blocky
/// stone arms with small hands, stubby stone legs, speckled and mossy. Measured off
/// companions-2d/targets/rune.webp (outlines); parts painted (Art/rune).
extension Species {
    static let rune: Species = {
        Species(
            shading: .flat(stone, line: line),
            edge: nil,
            torso: Paths.blob([pt(100, 80), pt(118, 79), pt(128, 72), pt(130, 56), pt(126, 42), pt(112, 36), pt(100, 35),
                               pt(88, 36), pt(74, 42), pt(72, 56), pt(74, 72), pt(84, 79)]),
            head: boulderHead,
            neck: pt(100, 86),
            feet: [pt(88, 29), pt(118, 29)],
            foot: CGSize(width: 22, height: 22),
            footShading: .flat(stone, line: line),
            shoulders: (pt(66, 76), pt(136, 76)),
            arm: ArmStyle(shape: Paths.ellipse(pt(0, -18), 14, 21), shading: .flat(stone, line: line),
                          hand: (Paths.ellipse(pt(-1, -38), 8, 9), .flat(stone, line: line))),
            armTuck: -0.1,
            footShape: Paths.roundedRect(CGRect(x: -11, y: -11, width: 22, height: 22), 9),
            face: SoftFace(kind: .ink, eyes: (pt(78, 118), pt(124, 118)), mouth: pt(102, 106), scale: 1.15, cheeks: true,
                           temper: .smiling, iris: RGB(0x7A4228), eyeSize: 1.2, mouthSize: 1.5, ink: RGB(0x241410),
                           blush: RGB(0xFF9A9A), blushAt: (pt(69, 104), pt(134, 104)), blushSize: CGSize(width: 6, height: 3.2)),
            collar: Collar(center: pt(100, 80), halfWidth: 28, sag: 3, height: 13, tail: 1.6),
            restingFrame: CGRect(x: 40, y: 20, width: 120, height: 146),
            markOffsets: [.zzz: pt(-10, 6), .dots: pt(16, -10), .question: pt(4, -2), .exclaim: pt(4, -2)]).painted("rune", nudge: ["torso": pt(0, 3)], grow: ["torso": 1.06])
    }()

    private static let stone = RGB(0xC8C3A5)
    private static let line = RGB(0x4E4A30)

    private static var boulderHead: CGPath {
        Paths.blob([pt(80, 152), pt(104, 155), pt(126, 152), pt(142, 140), pt(152, 124), pt(157, 104), pt(150, 90), pt(126, 84),
                    pt(100, 82), pt(74, 84), pt(50, 90), pt(43, 104), pt(48, 124), pt(58, 140)])
    }
}
