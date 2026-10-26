import QuartzCore

/// The Folk Family as full-size companions: the on-duty folk's body at twice the size (its footprint
/// is then the robot's), with arms that pose, an ink face that changes with every state, and its
/// signature pieces.
extension Species {
    static func folk(_ folk: Folk) -> Species {
        let tint = folk.tint
        return Species(
            shading: .tinted(tint),
            edge: nil,
            torso: FolkRig.outline(folk, center: pt(100, 88), scale: 2),
            head: nil,
            neck: pt(100, 92),
            feet: [pt(82, 27), pt(118, 27)],
            foot: CGSize(width: 30, height: 20),
            footShading: .tinted(tint.darker(0.12)),
            shoulders: (pt(46, 80), pt(154, 80)),
            arm: ArmStyle(shape: Shapes.nub(width: 24, length: 24), shading: .tinted(tint.mix(.white, 0.06)), edge: nil),
            face: SoftFace(kind: .ink, eyes: (pt(82, 94), pt(118, 94)), mouth: pt(100, 78), scale: 1.35, cheeks: true,
                           temper: .smiling),
            collar: Collar(center: pt(100, 62), halfWidth: 44, sag: 3, height: 15),
            restingFrame: CGRect(x: 38, y: 20, width: 124, height: 128))
    }
}
