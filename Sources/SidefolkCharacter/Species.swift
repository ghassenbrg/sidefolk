import QuartzCore

/// Everything that makes one soft companion itself, in canvas units (y up, feet on y = 20, centered
/// on x = 100). `SoftRig` builds and moves any of them the same way; the files beside this one
/// (Mochi, Spark, FolkSpecies) are just data and a few drawings.
@MainActor
struct Species {
    /// Body colours, highlight to core shadow, and an optional thin edge for white bodies.
    var shading: Shading
    var edge: RGB?
    /// One piece for the folks; a head above a torso for Mochi and Spark.
    var torso: CGPath
    var head: CGPath?
    /// Where the head turns and tilts (the neck), or the face's middle for one-piece bodies.
    var neck: CGPoint
    var feet: [CGPoint]
    var foot: CGSize
    var footShading: Shading?
    var shoulders: (CGPoint, CGPoint)
    var arm: ArmStyle
    /// Turns both arms in toward the body by this much in every pose (long arms that hang straight at rest).
    var armTuck: CGFloat = 0
    /// Feet of another shape than an oval (Folio's paper legs), drawn around each foot's centre.
    var footShape: CGPath?
    var face: SoftFace
    /// Ears, antennae and sprouts, drawn behind the head; they sway, droop and trail.
    var appendages: [AppendageSpec] = []
    /// The head in its own colour when it isn't the body's (Kiko's face, Purl's linen head).
    var headShading: Shading?
    /// Tails, drawn behind the body: they sway at rest, wag when happy and trail behind moves.
    var tails: [AppendageSpec] = []
    /// Painted parts drawn in place of the flat ones (D59).
    var painting: Painting?
    /// Floats this high above the floor, bobbing gently (Nimbo); 0 stands on its feet.
    var hover: CGFloat = 0
    /// Fixed pieces drawn over the head or body (headphones, a chest badge, a cap).
    var gear: [Gear] = []
    var held: Held?
    /// Where a scarf goes (the shared accessory).
    var collar: Collar
    /// The body at rest: what bubbles and panels attach to.
    var restingFrame: CGRect
    /// Marks (zZz, "?", thought dots) moved clear of ears and tufts.
    var markOffsets: [Effect: CGPoint] = [:]
    /// The colour of its marks when not its accent light.
    var marks: Light?
    /// Draws the whole body this much smaller around the floor point, so a tall companion's ears
    /// stay inside the window when it hops or is lifted. Coordinates above are before it.
    var scale: CGFloat = 1

    /// Drawn as a 2D cartoon (`Flat`) rather than softly shaded.
    var flat: Bool { shading.flat != nil }

    /// Every companion is a soft rig of its species. Shown in 3D, the gallery's companions run on a
    /// stand-in shaped like their 3D body instead (Mochi and Spark on their own 2D rig).
    static func figure(for look: CharacterLook) -> any Figure {
        if let custom = look.custom { return SoftRig(Species(custom)) }
        if look.threeD, look.species.inGallery { return SoftRig(standIn(for: look.species)) }
        return switch look.species {
        case .mochi: SoftRig(mochi)
        case .spark: SoftRig(spark)
        case .ember: SoftRig(ember)
        case .kiko: SoftRig(kiko)
        case .nimbo: SoftRig(nimbo)
        case .folio: SoftRig(folio)
        case .iris: SoftRig(iris)
        case .nori: SoftRig(nori)
        case .purl: SoftRig(purl)
        case .rune: SoftRig(rune)
        default: SoftRig(folk(look.species.folk!))
        }
    }
}

/// A face drawn in ink (bead eyes, like Mochi and the folks) or glowing on a screen (Spark).
struct SoftFace {
    enum Kind {
        case ink
        /// A dark rounded screen; the eyes are light in the companion's accent.
        case screen(CGRect, radius: CGFloat)
    }

    var kind: Kind
    var eyes: (CGPoint, CGPoint)
    var mouth: CGPoint
    /// A tiny nose between the eyes (Mochi).
    var nose: CGRect?
    /// Strokes are designed for Mochi's face; bigger faces scale them.
    var scale: CGFloat = 1
    /// Rosy cheeks under the eyes (the folks).
    var cheeks: Bool = false
    /// How it looks at rest: eyes and mouth for idle and the calm states.
    var temper: Temper = .calm
    /// The nose's colour when it isn't the eyes' ink (a custom companion's pink nose).
    var noseColor: RGB?
    /// The 2D companions' eyes: their ink fades into this colour toward the bottom, with two catchlights.
    var iris: RGB?
    /// How much bigger those eyes are than the face's other marks, and the mouth.
    var eyeSize: CGFloat = 1
    var mouthSize: CGFloat = 1
    /// Eyes, brows and mouth in this ink instead of the bead eyes' navy.
    var ink: RGB?
    /// Cheeks in this colour instead of the folks' rosy pink.
    var blush: RGB?
    /// One eye only, at the left eye's place (Iris's lens): the right eye's marks stay hidden.
    var single = false
    /// Where the cheeks sit and their half size, when not under the eyes as the folks' do.
    var blushAt: (CGPoint, CGPoint)?
    var blushSize = CGSize(width: 5.5, height: 3.4)
}

/// Resting expressions, from the folks' personalities.
enum Temper {
    /// Bead eyes, no mouth (Mochi), or bead eyes and a smile (`smiling`).
    case calm, smiling
    /// ^ ^ eyes and a smile.
    case cheerful
    /// ^ ^ eyes and an open grin.
    case beaming
    /// Closed, content eyes and a cat mouth.
    case content
    /// Bead eyes and a cat's "ω" mouth (Ember, Nori).
    case kitty
    /// > < eyes and a grin.
    case giddy
    /// Bead eyes under stern brows.
    case stern
    /// One eye winking.
    case winking
}

/// An ear, antenna or sprout: a shape standing on `base`, tilted `angle` from upright.
struct AppendageSpec {
    var base: CGPoint
    /// Radians from upright; positive leans left (counterclockwise).
    var angle: CGFloat
    /// -1 for a left ear, 1 for a right one; droop turns it outward.
    var side: CGFloat
    /// Draws it standing upright on the origin; `accent` is the style colour as a material.
    var layers: @MainActor (_ accent: RGB) -> CALayer
    /// The outline standing upright on the origin, for clicks.
    var outline: CGPath
    /// How far it trails behind moves, 0...1 (long ears more than a stiff antenna).
    var floppiness: CGFloat = 1
    /// How a soft ear folds back and down along the head when asleep: its base slides out to the
    /// head's edge (`shift`, for a right ear; mirrored for a left one), it turns `turn` further
    /// out and shows `length` of itself. Antennae and sprouts don't fold; they only droop.
    var fold: Fold?

    struct Fold {
        var shift: CGPoint
        var turn: CGFloat
        var length: CGFloat
    }
}

/// A signature thing the companion holds while nothing else is going on (idle):
/// Scout's magnifier, Tempo's calendar. Other states put it away and hold their own props.
struct Held {
    /// Arm raises while holding it (left, right); the shared choreography's otherwise.
    var arms: (CGFloat?, CGFloat?)
    /// Drawn over the hands (a card held from behind) or under them (a handle gripped).
    var overArms: Bool
    var draw: @MainActor () -> CALayer
}

/// A fixed piece worn over the head or body, optionally in the accent colour.
struct Gear {
    /// `back` hangs behind the body and turns with the head (Melody's headband); `skin` is painted on
    /// the head under the face (a fox's cream mask); `under` lies on the face under the eyes and mouth
    /// (Iris's lens), `face` over them (glasses).
    enum Mount { case back, head, skin, under, face, body }
    var mount: Mount
    /// Draws it in canvas units; `accent` is the style colour as a material.
    var draw: @MainActor (_ accent: RGB) -> CALayer
    /// Extra outline for clicks (headphone cups stick out).
    var outline: CGPath?
}

/// Where a scarf wraps: the middle of its band, its half-width and how much it sags.
struct Collar {
    var center: CGPoint
    var halfWidth: CGFloat
    var sag: CGFloat = 4
    var height: CGFloat = 15
    /// How far the loose end hangs, in band heights.
    var tail: CGFloat = 2.05
}
