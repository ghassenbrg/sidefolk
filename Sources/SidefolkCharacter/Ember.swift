import QuartzCore

/// Ember, the curious red fox, as a 2D cartoon (D59): a round orange head with cream cheeks flaring
/// into tufts, tall ears rimmed in dark brown with cream insides, big brown eyes, a little dark nose
/// and an "ω" mouth; standing on its legs, a cream belly, long arms with dark paws, dark feet and a
/// big teardrop tail with a zigzag cream tip that wags when it's happy. Its outlines are measured off
/// companions-2d/targets/ember.webp (the style target, in canvas units); its parts are painted (Art/ember).
extension Species {
    static let ember: Species = {
        Species(
            shading: .flat(orange, line: line),
            edge: nil,
            torso: Paths.blob([pt(100, 84), pt(118, 83), pt(127, 76), pt(131, 64), pt(131, 50), pt(127, 40), pt(118, 34),
                               pt(100, 32), pt(82, 34), pt(73, 40), pt(69, 50), pt(69, 64), pt(73, 76), pt(82, 83)])
                .union(Paths.roundedRect(CGRect(x: 75, y: 22, width: 18, height: 26), 8))
                .union(Paths.roundedRect(CGRect(x: 107, y: 22, width: 18, height: 26), 8)),
            head: foxHead,
            neck: pt(100, 82),
            feet: [pt(83, 26), pt(117, 26)],
            foot: CGSize(width: 27, height: 15),
            footShading: .flat(paw, line: line, light: 0.3),
            shoulders: (pt(72, 81), pt(128, 81)),
            arm: ArmStyle(shape: Paths.ellipse(pt(0, -15), 7, 18), shading: .flat(orange, line: line),
                          hand: (Paths.ellipse(pt(0, -28), 7.5, 9.5), .flat(paw, line: line, light: 0.3))),
            armTuck: 0.3,
            face: SoftFace(kind: .ink, eyes: (pt(79, 117), pt(121, 117)), mouth: pt(100, 97),
                           nose: CGRect(x: 96.5, y: 101.7, width: 7, height: 4.6), scale: 1.2, cheeks: true, temper: .kitty,
                           iris: RGB(0xB8662C), eyeSize: 1.3, ink: RGB(0x2B160E),
                           blush: RGB(0xFF8E8A), blushAt: (pt(72, 99), pt(128, 99)), blushSize: CGSize(width: 5.4, height: 3)),
            appendages: [ear(base: pt(64, 138), angle: 0.3, side: -1), ear(base: pt(136, 138), angle: -0.3, side: 1)],
            tails: [tail],
            collar: Collar(center: pt(100, 82), halfWidth: 28, sag: 3.5, height: 14, tail: 1.6),
            restingFrame: CGRect(x: 52, y: 20, width: 96, height: 160),
            markOffsets: [.zzz: pt(-14, 14), .dots: pt(18, -10), .question: pt(6, 0), .exclaim: pt(6, 0), .sweat: pt(-4, -8)],
            // Its tail and ears would leave the window asleep (squashed wide) or lifted at full size.
            scale: 0.92).painted("ember", nudge: ["torso": pt(0, 3)], grow: ["torso": 1.12])
    }()

    private static let orange = RGB(0xEE6E30)
    private static let line = RGB(0x5A2814)
    private static let paw = RGB(0x5C3420)

    /// Round on top, the cheeks flaring out into a fluffy tuft each side above a soft chin.
    private static var foxHead: CGPath {
        Paths.blob([pt(100, 153), pt(118, 151), pt(133, 144), pt(142, 133), pt(147, 120), pt(147, 110), pt(152, 102),
                    pt(140, 93), pt(124, 85), pt(110, 80), pt(100, 79), pt(90, 80), pt(76, 85), pt(60, 93), pt(48, 102),
                    pt(53, 110), pt(53, 120), pt(58, 133), pt(67, 144), pt(82, 151)])
    }

    /// A tall ear, painted already leaning out as it rests (so its own angle is 0); stiff, it twitches rather than flops.
    private static func ear(base: CGPoint, angle: CGFloat, side: CGFloat) -> AppendageSpec {
        let outline = Paths.transformed(Paths.blob([pt(-17, -6), pt(-19, 9), pt(-16, 25), pt(-9, 39), pt(-1, 48), pt(4, 46),
                                                    pt(11, 34), pt(17, 18), pt(19, 2), pt(15, -8), pt(0, -10)]),
                                        CGAffineTransform(rotationAngle: angle))
        return AppendageSpec(base: base, angle: 0, side: side, layers: { _ in
            Painted(side < 0 ? "ember/earL" : "ember/earR", over: outline, nudge: pt(0, 4), grow: 1.12)?.layer ?? Cel.part(outline, orange, line: line)
        }, outline: outline, floppiness: 0.45)
    }

    /// The big bushy tail behind it on our left, fattest near the floor, painted with its zigzag cream tip.
    private static var tail: AppendageSpec {
        // Painted as it rests, out to our left with its tip up: the outline is drawn that way and its own angle is 0.
        let outline = Paths.blob([pt(-2, -2), pt(-30, -4), pt(-55, 8), pt(-64, 30), pt(-62, 55), pt(-58, 73), pt(-40, 70),
                                  pt(-20, 58), pt(-6, 40), pt(0, 20)])
        return AppendageSpec(base: pt(78, 30), angle: 0, side: -1, layers: { _ in
            Painted("ember/tail", over: outline)?.layer ?? Cel.part(outline, orange, line: line)
        }, outline: outline, floppiness: 0.8)
    }
}
