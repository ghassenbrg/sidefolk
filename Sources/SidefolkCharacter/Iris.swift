import QuartzCore

/// Iris, the little camera scout, as a 2D cartoon (D59): a butter-yellow rounded camera whose one big
/// lens is its eye (a brown barrel, blue glass, a round dark pupil), a viewfinder window, a slot and an
/// orange shutter button on top, a smile under the lens, rosy cheeks, big dark brown mitts at its sides
/// and big shoes on short legs. Outlines measured off companions-2d/targets/iris.webp; parts painted (Art/iris).
extension Species {
    static let iris = Species(
        shading: .flat(yellow, line: line),
        edge: nil,
        torso: Paths.blob([pt(100, 153), pt(132, 152), pt(150, 147), pt(158, 132), pt(160, 100), pt(159, 64), pt(153, 50),
                           pt(136, 45), pt(100, 44), pt(64, 45), pt(47, 50), pt(41, 64), pt(41, 100), pt(42, 132), pt(50, 147),
                           pt(68, 152)]),
        head: nil,
        neck: pt(104, 100),
        feet: [pt(76, 30), pt(125, 30)],
        foot: CGSize(width: 32, height: 20),
        footShading: .flat(brown, line: brownLine, light: 0.5),
        shoulders: (pt(44, 90), pt(156, 90)),
        arm: ArmStyle(shape: Paths.ellipse(pt(0, -20), 11, 22), shading: .flat(brown, line: brownLine, light: 0.5)),
        armTuck: 0.08,
        footShape: Paths.ellipse(pt(0, -1), 16, 10).union(Paths.roundedRect(CGRect(x: -9, y: -2, width: 18, height: 16), 4)),
        // One eye, the lens's pupil; the mouth sits under the lens.
        face: SoftFace(kind: .ink, eyes: (pt(97, 92), pt(97, 92)), mouth: pt(100, 54), scale: 1.2, cheeks: true, temper: .smiling,
                       iris: RGB(0x2F6DB0), eyeSize: 3, mouthSize: 1.4, ink: RGB(0x14213A), blush: RGB(0xFF9A9A),
                       single: true, blushAt: (pt(62, 64), pt(140, 64)), blushSize: CGSize(width: 6.6, height: 3.8)),
        collar: Collar(center: pt(100, 52), halfWidth: 52, sag: 2, height: 12),
        restingFrame: CGRect(x: 38, y: 20, width: 124, height: 140),
        markOffsets: [.zzz: pt(-6, -6), .dots: pt(12, -14), .question: pt(4, -8), .exclaim: pt(4, -8)]).painted("iris")

    private static let yellow = RGB(0xFDC64A)
    private static let line = RGB(0x6E4416)
    private static let brown = RGB(0x5A3A2C)
    private static let brownLine = RGB(0x2E1A12)

}
