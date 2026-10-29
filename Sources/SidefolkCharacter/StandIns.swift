import QuartzCore

/// Ember, Kiko, Nimbo and Folio exist only in 3D (D51): the app draws them in a web view over a soft rig
/// that is never shown. That rig still runs the states, idle life, petting and dragging, and its
/// outline is what takes clicks and where bubbles attach, so each stand-in is shaped like the 3D
/// character as the app frames it: 2.3 model units fill the view's height with the floor at 10%,
/// so one unit is 87 canvas units (`Canvas`: 200 wide, floor at y = 20).
extension Species {
    static func standIn(for species: CharacterSpecies) -> Species {
        var s = Species.mochi
        // Mochi's 0.95 scale stays: like its ears, the stand-ins' tops must stay in the window on a hop.
        s.appendages = []
        switch species {
        case .ember:
            // A round head with tall ears, a small body, the big tail out to its right (our left).
            s.head = Shapes.roundish(center: pt(100, 126), width: 92, height: 70)
                .union(Paths.ellipse(pt(73, 160), 13, 26)).union(Paths.ellipse(pt(127, 160), 13, 26))
            s.torso = Shapes.roundish(center: pt(100, 62), width: 52, height: 60).union(Paths.ellipse(pt(48, 64), 20, 38))
            s.neck = pt(100, 92)
            s.feet = [pt(87, 25), pt(113, 25)]
            s.shoulders = (pt(79, 84), pt(121, 84))
            s.restingFrame = CGRect(x: 54, y: 20, width: 92, height: 165)
        case .kiko:
            // A big head of curls on a small spacesuit, legs apart.
            s.head = Shapes.roundish(center: pt(100, 149), width: 80, height: 74)
            s.torso = Shapes.roundish(center: pt(100, 86), width: 52, height: 58).union(Paths.ellipse(pt(100, 42), 30, 22))
            s.neck = pt(100, 113)
            s.feet = [pt(83, 25), pt(117, 25)]
            s.shoulders = (pt(79, 96), pt(121, 96))
            s.restingFrame = CGRect(x: 60, y: 20, width: 80, height: 165)
        case .nimbo:
            // One wide cloud floating above the floor, its puffs at its lower front corners; no feet.
            s.head = nil
            s.torso = Shapes.roundish(center: pt(100, 90), width: 160, height: 112)
            s.neck = pt(100, 100)
            s.feet = []
            s.shoulders = (pt(65, 70), pt(135, 70))
            // Anchored at the floor like every companion: its shadow is where it stands.
            s.restingFrame = CGRect(x: 20, y: 20, width: 160, height: 126)
        case .folio:
            // A folded-paper house shape on two little feet, a paper fin at each side.
            s.head = nil
            s.torso = Shapes.roundish(center: pt(100, 103), width: 122, height: 127)
                .union(Paths.ellipse(pt(28, 63), 12, 16)).union(Paths.ellipse(pt(172, 63), 12, 16))
            s.neck = pt(100, 120)
            s.feet = [pt(71, 26), pt(129, 26)]
            s.shoulders = (pt(42, 75), pt(158, 75))
            s.restingFrame = CGRect(x: 39, y: 20, width: 122, height: 147)
        default:
            break
        }
        return s
    }
}
