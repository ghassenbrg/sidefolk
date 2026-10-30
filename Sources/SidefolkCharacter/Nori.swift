import QuartzCore

/// Nori, the bookish tuxedo cat, as a 2D cartoon (D59): charcoal with a cream face rising in a blaze
/// between the eyes, pointed ears with pink insides, round black glasses over big brown eyes, a little
/// nose, an "ω" mouth and long whiskers; a cream belly and paws, and a tail curling up behind it with a
/// cream tip. Its mint scarf is the shared one, which it comes wearing (`standardStyle`). Measured off
/// companions-2d/targets/nori.webp (outlines); parts painted (Art/nori).
extension Species {
    static let nori: Species = {
        Species(
            shading: .flat(charcoal, line: line, light: 0.35),
            edge: nil,
            // Short legs: the round body ends just above its paws.
            torso: Paths.blob([pt(100, 82), pt(122, 80), pt(134, 70), pt(140, 56), pt(138, 42), pt(128, 35), pt(100, 33),
                               pt(72, 35), pt(62, 42), pt(60, 56), pt(66, 70), pt(78, 80)]),
            head: catHead,
            neck: pt(100, 84),
            // Big round paws, close together under the body, as in the target.
            feet: [pt(86, 27), pt(114, 27)],
            foot: CGSize(width: 31, height: 17),
            footShading: .flat(cream, line: line),
            shoulders: (pt(62, 75), pt(138, 75)),
            arm: ArmStyle(shape: Paths.ellipse(pt(0, -14), 9, 18), shading: .flat(charcoal, line: line, light: 0.35),
                          hand: (Paths.ellipse(pt(0, -27), 9, 8), .flat(cream, line: line))),
            // Short thick arms that hang close to its round body, as the target's do.
            armTuck: 0.36,
            face: SoftFace(kind: .ink, eyes: (pt(80, 111), pt(120, 111)), mouth: pt(100, 97),
                           nose: CGRect(x: 97, y: 102, width: 6, height: 4), scale: 1.15, cheeks: true, temper: .kitty,
                           noseColor: RGB(0x2A1A1A), iris: RGB(0x9A5424), eyeSize: 1.16, ink: RGB(0x2A160C),
                           blush: RGB(0xFF9FA8), blushAt: (pt(70, 95), pt(130, 95)), blushSize: CGSize(width: 6, height: 3.4)),
            appendages: [ear(base: pt(68, 140), angle: 0.24, side: -1), ear(base: pt(132, 140), angle: -0.24, side: 1)],
            tails: [tail],
            gear: [Gear(mount: .face, draw: { _ in glasses }, outline: Paths.ellipse(pt(100, 106), 70, 16))],
            collar: Collar(center: pt(100, 79), halfWidth: 28, sag: 3.5, height: 13, tail: 1.8),
            restingFrame: CGRect(x: 50, y: 20, width: 100, height: 156),
            markOffsets: [.zzz: pt(-14, 14), .dots: pt(18, -10), .question: pt(6, 0), .exclaim: pt(6, 0)],
            scale: 0.98).painted("nori", nudge: ["torso": pt(0, 3)], grow: ["torso": 1.1, "head": 1.06],
                                   // Broad through the chest, so it doesn't look thin under its head without a scarf.
                                   widen: ["torso": 1.14])
    }()

    private static let charcoal = RGB(0x3C3B48)
    private static let line = RGB(0x17161E)
    private static let cream = RGB(0xFBF2E6)

    private static var catHead: CGPath {
        Paths.blob([pt(100, 152), pt(124, 149), pt(140, 139), pt(148, 124), pt(149, 108), pt(144, 96), pt(132, 89),
                    pt(116, 86), pt(100, 85), pt(84, 86), pt(68, 89), pt(56, 96), pt(51, 108), pt(52, 124), pt(60, 139),
                    pt(76, 149)])
    }

    /// Round black glasses over the eyes, and two long whiskers each side reaching past the cheeks.
    private static var glasses: CALayer {
        let frames = CGMutablePath()
        frames.addPath(Paths.circle(pt(80, 112), 15))
        frames.addPath(Paths.circle(pt(120, 112), 15))
        frames.move(to: pt(95, 114))
        frames.addQuadCurve(to: pt(105, 114), control: pt(100, 118))
        frames.move(to: pt(65, 114))
        frames.addLine(to: pt(56, 117))
        frames.move(to: pt(135, 114))
        frames.addLine(to: pt(144, 117))
        let whiskers = CGMutablePath()
        for side in [-1.0, 1.0] {
            whiskers.move(to: pt(100 + side * 44, 104))
            whiskers.addLine(to: pt(100 + side * 68, 109))
            whiskers.move(to: pt(100 + side * 44, 98))
            whiskers.addLine(to: pt(100 + side * 68, 96))
        }
        return Cel.group([Layers.shape(Paths.circle(pt(80, 112), 14).union(Paths.circle(pt(120, 112), 14)), fill: RGB.white.cg(0.14), pad: 0),
                          Cel.line(frames, line, width: 3.6), Cel.line(whiskers, line, width: 2)])
    }

    /// A pointed cat ear, painted already leaning out as it rests (so its own angle is 0).
    private static func ear(base: CGPoint, angle: CGFloat, side: CGFloat) -> AppendageSpec {
        let outline = Paths.transformed(Paths.blob([pt(-18, -4), pt(-18, 10), pt(-13, 22), pt(-4, 32), pt(0, 34), pt(5, 31),
                                                    pt(13, 20), pt(18, 8), pt(18, -4), pt(0, -8)]),
                                        CGAffineTransform(rotationAngle: angle))
        return AppendageSpec(base: base, angle: 0, side: side, layers: { _ in
            Painted(side < 0 ? "nori/earL" : "nori/earR", over: outline)?.layer ?? Cel.part(outline, charcoal, line: line)
        }, outline: outline, floppiness: 0.4)
    }

    /// The tail out to our right, curling up behind it, painted with its cream tip.
    private static var tail: AppendageSpec {
        let outline = Paths.transformed(Paths.blob([pt(6, 0), pt(8, 14), pt(8, 26), pt(2, 36), pt(-8, 42), pt(-20, 42), pt(-30, 36),
                                                    pt(-34, 26), pt(-26, 22), pt(-18, 28), pt(-10, 28), pt(-5, 22), pt(-6, 12),
                                                    pt(-6, 0)]),
                                        CGAffineTransform(rotationAngle: -1.2))
        return AppendageSpec(base: pt(127, 34), angle: 0, side: 1, layers: { _ in
            // Painted lying flat, its tip on the left: mirrored and turned up to curl behind it.
            Painted("nori/tail", over: outline, nudge: pt(4, 4), turn: 0.45, mirrored: true)?.layer ?? Cel.part(outline, charcoal, line: line)
        }, outline: outline, floppiness: 0.7)
    }
}
