import QuartzCore

/// Nimbo, the daydream cloud, as a 2D cartoon (D59): one wide lilac cloud floating above its shadow,
/// a big cream cloud of a face with very big purple eyes and a small smile, puffs for hands at its
/// lower corners, glossy highlights on its top and a gold star tucked in at the top right. It bobs as
/// it floats. Outline measured off companions-2d/targets/nimbo.webp; painted (Art/nimbo).
extension Species {
    static let nimbo: Species = {
        Species(
            shading: .flat(lilac, line: line, light: 0.65),
            edge: nil,
            torso: lifted(cloud.union(Paths.circle(pt(146, 122), 15))),
            head: nil,
            neck: pt(100, 80),
            feet: [],
            foot: .zero,
            footShading: nil,
            shoulders: (pt(48, 62), pt(152, 62)),
            arm: ArmStyle(shape: Paths.ellipse(pt(0, -12), 13, 11).union(Paths.circle(pt(0, -3), 8)),
                          shading: .flat(lilac, line: line, light: 0.65)),
            armTuck: -0.1,
            face: SoftFace(kind: .ink, eyes: (pt(74, 71), pt(126, 71)), mouth: pt(100, 56), scale: 1.3, cheeks: true,
                           temper: .smiling, iris: RGB(0x7B58C8), eyeSize: 1.32, ink: RGB(0x2A1844), blush: RGB(0xFF8FA6),
                           blushAt: (pt(66, 57), pt(134, 57)), blushSize: CGSize(width: 5.4, height: 2.8)),
            hover: 10,
            collar: Collar(center: pt(100, 34), halfWidth: 44, sag: 4, height: 13),
            restingFrame: CGRect(x: 18, y: 20, width: 164, height: 130),
            markOffsets: [.zzz: pt(6, -14), .dots: pt(10, -24), .question: pt(4, -18), .exclaim: pt(4, -18)],
            // So wide a cloud would leave the window asleep (squashed wider) at full size.
            scale: 0.9).painted("nimbo")
    }()

    private static let lilac = RGB(0xBDB2F4)
    private static let line = RGB(0x5A4CB0)

    /// Drawn where the target shows it, then lowered by its hover: the float lifts it back.
    private static func lifted(_ path: CGPath) -> CGPath { Paths.translated(path, 0, -10) }

    /// A big round bump on top, smaller ones down each side and a flat soft bottom.
    private static var cloud: CGPath {
        var cloud = Paths.ellipse(pt(100, 56), 74, 25)
        for (c, r) in [(pt(104, 116), 31.0), (pt(66, 104), 25.0), (pt(32, 76), 19.0), (pt(144, 98), 22.0), (pt(166, 74), 19.0),
                       (pt(48, 58), 18.0), (pt(152, 58), 18.0), (pt(84, 104), 20.0), (pt(124, 104), 22.0)] {
            cloud = cloud.union(Paths.circle(c, r))
        }
        return cloud
    }
}
