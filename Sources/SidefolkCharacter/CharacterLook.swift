/// Who a `CharacterView` draws and how it is dressed (DECISIONS D30).
public struct CharacterLook: Equatable, Sendable {
    public var species: CharacterSpecies
    public var style: CharacterStyle

    public init(_ species: CharacterSpecies, style: CharacterStyle? = nil) {
        self.species = species
        self.style = style ?? species.standardStyle
    }
}

/// Every companion that can live on the desktop. The robot is its own vector rig (D2); the others
/// are soft rigs built from a `Species`.
public enum CharacterSpecies: String, CaseIterable, Sendable {
    case mochi, sidefolk, spark
    case pip, byte, seed, melody, scout, tempo, play, guard_ = "guard", nova, brew

    /// Companions finished to the full bar (every state, gesture, prop): only these are offered.
    public static let available: [CharacterSpecies] = [.mochi, .sidefolk, .spark]

    public var displayName: String {
        switch self {
        case .mochi: "Mochi"
        case .sidefolk: "Sidefolk"
        case .spark: "Spark"
        default: folk!.displayName
        }
    }

    /// The folk this companion is, when it is one of the Folk Family.
    public var folk: Folk? { Folk(rawValue: rawValue) }

    /// Whether the style colour paints part of the companion itself (the robot's light, Spark's
    /// gear), not only what it wears.
    public var hasOwnAccents: Bool { self == .sidefolk || self == .spark }

    /// How it comes dressed: Mochi in its scarf, the others in nothing; aqua accents for all.
    public var standardStyle: CharacterStyle {
        CharacterStyle(color: .aqua, accessory: self == .mochi ? .scarf : .none)
    }
}

/// The same small set of choices for every companion: one brand colour and one thing to wear.
public struct CharacterStyle: Equatable, Sendable {
    /// Colours what it wears and its own accent parts (the robot's light, Spark's headphones).
    public var color: CharacterAccent
    public var accessory: CharacterAccessory

    public init(color: CharacterAccent, accessory: CharacterAccessory) {
        self.color = color
        self.accessory = accessory
    }
}

/// Something any companion can wear, fitted to each body's neck or eyes.
public enum CharacterAccessory: String, CaseIterable, Sendable {
    case none, scarf
}

/// The brand colours (aqua, coral, mint, light blue) a companion's accents can take.
public enum CharacterAccent: String, CaseIterable, Sendable {
    case aqua, coral, mint, lightBlue

    /// As a light: halo, stroke and hot core. Aqua keeps the reference's hand-picked shades.
    var light: Light {
        switch self {
        case .aqua: Light(glow: Palette.aqua, line: Palette.eyeLight, core: Palette.eyeCore)
        case .coral: Light(Palette.coral)
        case .mint: Light(Palette.mint)
        case .lightBlue: Light(Palette.lightBlue)
        }
    }

    /// As a material (a knitted scarf, a plastic part). Aqua leans to mint, like Mochi's scarf and
    /// Spark's headphones in the founder's renders.
    var tint: RGB {
        switch self {
        case .aqua: Palette.aqua.mix(Palette.mint, 0.45).lighter(0.08)
        case .coral: Palette.coral
        case .mint: Palette.mint
        case .lightBlue: Palette.lightBlue
        }
    }
}

/// One light colour in the three shades the rigs draw it with.
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
