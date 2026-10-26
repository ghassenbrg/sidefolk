import QuartzCore

/// The Folk Family as full-size companions (D30): exactly twice the on-duty folk (its body, feet,
/// eyes and mouth map ×2, so its footprint is the robot's), with arms that pose, an ink face that
/// changes with every state, and its signature pieces from `FolkKit` drawn at the same scale.
/// Things it holds are put away whenever a state needs its hands.
extension Species {
    static func folk(_ folk: Folk) -> Species {
        let tint = folk.tint
        var species = Species(
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
            collar: Collar(center: pt(100, 62), halfWidth: 50, sag: 7, height: 14),
            restingFrame: CGRect(x: 38, y: 20, width: 124, height: 128))
        let sized = { (drawing: CALayer, shift: CGPoint) in FolkKit.companionSized(drawing, shift: shift) }
        switch folk {
        case .pip:
            species.face.temper = .beaming
        case .byte:
            species.gear = [Gear(mount: .face, draw: { _ in sized(FolkKit.glasses(), .zero) })]
        case .seed:
            species.face.temper = .cheerful
            species.appendages = [sprout]
        case .melody:
            species.face.temper = .content
            species.gear = [Gear(mount: .back, draw: { _ in sized(FolkKit.headband(), .zero) }),
                            Gear(mount: .head, draw: { _ in sized(FolkKit.headphones(), .zero) },
                                 outline: Paths.roundedRect(CGRect(x: 30, y: 76, width: 140, height: 40), 12))]
        case .scout:
            species.held = Held(arms: (nil, -0.3), overArms: false,
                                draw: { sized(FolkKit.magnifier(hand: nil), pt(3, 1)) })
        case .tempo:
            species.face.temper = .cheerful
            species.held = Held(arms: (nil, -0.25), overArms: true,
                                draw: { sized(FolkKit.calendar(at: pt(70, 24)), pt(2, 6)) })
        case .play:
            species.face.temper = .giddy
            species.held = Held(arms: (-0.85, -0.85), overArms: true,
                                draw: { sized(FolkKit.gamepad(), pt(0, 2)) })
        case .guard_:
            species.face.temper = .stern
            species.gear = [Gear(mount: .head, draw: { _ in sized(FolkKit.cap(), .zero) })]
            species.held = Held(arms: (nil, -0.2), overArms: true,
                                draw: { sized(FolkKit.shield(at: pt(72, 24)), pt(2, 5)) })
        case .nova:
            species.face.temper = .winking
            species.gear = [Gear(mount: .head, draw: { _ in sized(FolkKit.beret(), .zero) })]
            species.held = Held(arms: (nil, 0), overArms: false,
                                draw: { sized(FolkKit.paintbrush(hand: nil), pt(1, 2)) })
        case .brew:
            species.face.temper = .cheerful
            species.gear = [Gear(mount: .head, draw: { _ in sized(FolkKit.bowler(), .zero) })]
            species.held = Held(arms: (-0.55, nil), overArms: false,
                                draw: { sized(FolkKit.cup(at: pt(28, 24), hand: nil), pt(3, 8)) })
        }
        return species
    }

    /// Seed's two leaves on their stem, swaying and drooping like ears. A little smaller than twice
    /// the on-duty sprout, so it stays in the window when Seed is lifted.
    private static var sprout: AppendageSpec {
        AppendageSpec(base: pt(100, 138), angle: 0, side: 1, layers: { _ in
            FolkKit.companionSized(FolkKit.sprout(), shift: pt(-50, -70), scale: 1.75)
        }, outline: Paths.roundedRect(CGRect(x: -19, y: 0, width: 40, height: 38), 12), floppiness: 0.6)
    }
}
