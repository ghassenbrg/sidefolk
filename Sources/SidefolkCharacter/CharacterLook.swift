/// Which companion a `CharacterView` draws (DECISIONS D27).
public enum CharacterLook: Equatable, Sendable {
    /// The vector robot (D2), its light in `accent`.
    case sidefolk(CharacterAccent)
    /// A companion drawn from pose images (Mochi, Spark).
    case sprites(SpriteSet)
}

/// The colour of Sidefolk's light: the eyes, brows and mouth on the visor, the ear pods, and the
/// marks drawn in that light (zZz, waves, thought dots). Brand colours only; badges stay aqua.
public enum CharacterAccent: String, CaseIterable, Sendable {
    case aqua, coral, mint, lightBlue

    var light: Light {
        switch self {
        // The reference's hand-picked shades.
        case .aqua: Light(glow: Palette.aqua, line: Palette.eyeLight, core: Palette.eyeCore)
        case .coral: Light(Palette.coral)
        case .mint: Light(Palette.mint)
        case .lightBlue: Light(Palette.lightBlue)
        }
    }
}

/// One light colour in the three shades the rig draws it with.
struct Light: Equatable {
    /// The halo (a layer shadow) and the ear pods' fill.
    var glow: RGB
    /// The visible stroke.
    var line: RGB
    /// The hot centre of the eyes.
    var core: RGB

    init(glow: RGB, line: RGB, core: RGB) {
        self.glow = glow
        self.line = line
        self.core = core
    }

    /// Shades derived the way the aqua ones relate to aqua: a lighter stroke and a near-white core.
    init(_ color: RGB) {
        self.init(glow: color, line: color.lighter(0.22), core: color.lighter(0.75))
    }
}
