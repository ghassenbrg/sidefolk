import QuartzCore

/// Kiko, the young space explorer, as a 2D cartoon (D59): a big head of wavy dark brown hair over a
/// round peach face with ears, big brown eyes and a smile; a mustard spacesuit with a purple collar,
/// backpack straps, a star badge, knee pads, big purple gloves with cuffs and big purple boots.
/// Outlines measured off companions-2d/targets/kiko.webp; parts painted (Art/kiko).
extension Species {
    static let kiko = Species(
        shading: .flat(suit, line: suitLine),
        edge: nil,
        torso: Paths.blob([pt(100, 96), pt(116, 95), pt(128, 90), pt(134, 82), pt(132, 70), pt(128, 58), pt(124, 48), pt(100, 50),
                           pt(76, 48), pt(72, 58), pt(68, 70), pt(66, 82), pt(72, 90), pt(84, 95)])
            .union(Paths.roundedRect(CGRect(x: 76, y: 28, width: 21, height: 26), 7))
            .union(Paths.roundedRect(CGRect(x: 103, y: 28, width: 21, height: 26), 7)),
        head: Shapes.roundish(center: pt(100, 126), width: 80, height: 60, top: 1.04, squareness: 2.2)
            .union(Paths.ellipse(pt(62, 117), 7, 10)).union(Paths.ellipse(pt(138, 117), 7, 10)).union(hairline),
        neck: pt(100, 97),
        feet: [pt(84, 27), pt(116, 27)],
        foot: CGSize(width: 36, height: 20),
        footShading: .flat(purple, line: purpleLine, light: 0.5),
        shoulders: (pt(69, 90), pt(131, 90)),
        arm: ArmStyle(shape: Paths.roundedRect(CGRect(x: -7.5, y: -24, width: 15, height: 28), 7), shading: .flat(suit, line: suitLine),
                      hand: (Paths.roundedRect(CGRect(x: -8.5, y: -26, width: 17, height: 7), 3)
                                .union(Paths.ellipse(pt(0, -33), 10, 11)).union(Paths.ellipse(pt(7, -28), 4, 5.5)),
                             .flat(purple, line: purpleLine, light: 0.5))),
        armTuck: 0.08,
        face: SoftFace(kind: .ink, eyes: (pt(81, 121), pt(119, 121)), mouth: pt(100, 109), scale: 1.15, cheeks: true, temper: .smiling,
                       iris: RGB(0x8A4E26), eyeSize: 1.16, ink: RGB(0x2E160C),
                       blush: RGB(0xF0807A), blushAt: (pt(75, 111), pt(125, 111)), blushSize: CGSize(width: 6, height: 3)),
        headShading: .flat(skin, line: skinLine),
        collar: Collar(center: pt(100, 93), halfWidth: 22, sag: 3, height: 12, tail: 1.6),
        restingFrame: CGRect(x: 56, y: 20, width: 88, height: 160),
        markOffsets: [.zzz: pt(-12, 10), .dots: pt(16, -6), .question: pt(4, 6), .exclaim: pt(4, 6)],
        // Its hair would leave the window when it is lifted at full size.
        scale: 0.92).painted("kiko", nudge: ["torso": pt(0, 4)], grow: ["torso": 1.1])

    private static let skin = RGB(0xF2AE7C)
    private static let skinLine = RGB(0x7A3A1E)
    private static let suit = RGB(0xF6B84A)
    private static let suitLine = RGB(0x8A561C)
    private static let purple = RGB(0x5E3C86)
    private static let purpleLine = RGB(0x2E1C48)

    /// The hair over the top of the head: swept and wavy, puffing out a little over the ears, its fringe
    /// falling in locks over the forehead.
    private static var hairline: CGPath {
        Paths.blob([pt(57, 129), pt(50, 137), pt(51, 146), pt(48, 153), pt(53, 161), pt(55, 169), pt(63, 177), pt(74, 182),
                    pt(88, 186), pt(100, 187), pt(112, 186), pt(121, 191), pt(127, 184), pt(136, 179), pt(142, 171),
                    pt(149, 165), pt(151, 156), pt(147, 149), pt(150, 140), pt(144, 130), pt(139, 137), pt(131, 141),
                    pt(122, 146), pt(110, 144), pt(99, 149), pt(88, 144), pt(77, 147), pt(69, 140), pt(63, 133)])
    }
}
