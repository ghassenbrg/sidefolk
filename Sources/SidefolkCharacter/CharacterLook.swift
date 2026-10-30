/// Who a `CharacterView` draws and how it is dressed (DECISIONS D30).
public struct CharacterLook: Equatable, Sendable {
    public var species: CharacterSpecies
    public var style: CharacterStyle
    /// A companion made from data (`CustomCompanion`), drawn on a soft rig instead of `species`.
    public var custom: CustomCompanion?
    /// Shown in 3D by the app (D51): this module's rig still runs, undrawn, and the app draws the
    /// species' 3D character over it. Otherwise this module draws it in 2D (D59).
    public var threeD = false
    /// A 3D character added from a folder (D60) that the app draws instead of `species`' own: `species` then only
    /// lends the stand-in rig underneath (its outline, anchors and moves).
    public var character3D: String?

    /// Who is drawn, whatever it wears: another identity means another body.
    var identity: String { custom.map { "custom:\($0.id)" } ?? species.rawValue }

    public init(_ species: CharacterSpecies, style: CharacterStyle? = nil, threeD: Bool = false) {
        self.species = species
        self.style = style ?? species.standardStyle
        self.threeD = threeD && species.has3D
    }
}

/// Every companion that can live on the desktop: soft rigs built from a `Species`, each drawn in 2D here and,
/// for the ten companions, in 3D by the app over that rig (D51, D59). The original robot's vector rig (D2) is
/// retired (D56).
public enum CharacterSpecies: String, CaseIterable, Sendable {
    case mochi, spark
    case pip, byte, seed, melody, scout, tempo, play, guard_ = "guard", nova, brew
    case ember, kiko, nimbo, folio, iris, nori, purl, rune

    /// Companions finished to the full bar (every state, gesture, prop): only these are offered.
    public static let available: [CharacterSpecies] = allCases

    /// Has a 3D character the app can draw (D51).
    public var has3D: Bool { [.mochi, .spark, .ember, .kiko, .nimbo, .folio, .iris, .nori, .purl, .rune].contains(self) }

    /// Comes from the add-on gallery (D55): its 3D files download on demand; its 2D rig is built in
    /// (D59), and in 3D it runs on a stand-in shaped like its 3D body.
    public var inGallery: Bool { [.ember, .kiko, .nimbo, .folio, .iris, .nori, .purl, .rune].contains(self) }

    /// The companions this module draws itself: all of them, in 2D (D59).
    public static var drawn2D: [CharacterSpecies] { allCases }

    public var displayName: String {
        switch self {
        case .mochi: "Mochi"
        case .spark: "Spark"
        case .ember: "Ember"
        case .kiko: "Kiko"
        case .nimbo: "Nimbo"
        case .folio: "Folio"
        case .iris: "Iris"
        case .nori: "Nori"
        case .purl: "Purl"
        case .rune: "Rune"
        default: folk!.displayName
        }
    }

    /// The folk this companion is, when it is one of the Folk Family.
    public var folk: Folk? { Folk(rawValue: rawValue) }

    /// Whether the style colour paints part of the companion itself (Spark's gear), not only what it wears.
    public var hasOwnAccents: Bool { self == .spark }

    /// How it comes dressed: Mochi in its aqua scarf and Nori in a mint one, the others in nothing with aqua accents.
    public var standardStyle: CharacterStyle {
        switch self {
        case .mochi: CharacterStyle(color: .aqua, accessory: .scarf)
        case .nori: CharacterStyle(color: .mint, accessory: .scarf)
        default: CharacterStyle(color: .aqua, accessory: .none)
        }
    }
}

/// The same small set of choices for every companion: one brand colour and one thing to wear.
public struct CharacterStyle: Equatable, Sendable {
    /// Colours what it wears and its own accent parts (Spark's headphones).
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
