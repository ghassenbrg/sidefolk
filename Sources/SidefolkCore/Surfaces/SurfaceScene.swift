import Foundation

/// What an extension's surface shows right now (D99): a typed, capped tree it sends as data, drawn by Sidefolk with
/// native layers. Images come only from the extension's own pack, colours from the theme by name or as plain values,
/// animations run in the app from the data alone (so a shuffle or a coin flip needs no streaming), and at rest nothing
/// runs. The extension hears only moves its scene offered (`SurfaceMove`), and can place the person's companion and the
/// person but never read them. Everything here is checked by `SurfaceScene.parse`; a node this version doesn't know is
/// skipped, so a newer extension still opens.
public struct SurfaceScene: Sendable, Hashable {
    public var size: SceneSize
    public var nodes: [SceneNode]
    public var runs: [SceneRun] = []
    public var timers: [SceneTimer] = []
    public var keys: [SceneKey] = []
    public var background: SceneColor?
    /// No move is taken for this long (besides areas marked `always`), on top of what a blocking animation holds.
    public var inputAfter: Double = 0
    /// Show this scene so long, then ask for the next (`next`): the extension never keeps time itself.
    public var after: Double?
    /// The same wait under Reduce Motion, when the build-up it allows for doesn't play: nothing tells the program that setting.
    public var afterStill: Double?
    /// A switch among the extension's settings that the frame's speaker is while this scene shows (one surface, many choices).
    public var speaker: String?
    /// The frame's second line, beside the extension's name.
    public var title: String?
    /// The frame shows Back, which sends `back`.
    public var back = false
    /// Ended: Sidefolk stops the clocks and writes the one Activity row.
    public var over = false
    /// Puts the surface away, after `closeAfter` seconds.
    public var close = false
    public var closeAfter: Double = 0
    /// How a node that changed since the last scene eases to its new place (0: at once).
    public var transition: Double = 0
    /// Lays out right to left in Arabic: x runs from the far side, except under a node marked `ltr`.
    public var mirrors = true
    /// What VoiceOver hears as this scene shows.
    public var announce: String?
    /// How it ended for the person, as Sidefolk's own row says it; never words of the extension's.
    public var outcome: SceneOutcome?
    public var tally: [Int]?
    /// What was left out and why, for the author: logged, never shown.
    public var notes: [String] = []

    public init(size: SceneSize, nodes: [SceneNode] = []) {
        self.size = size
        self.nodes = nodes
    }

    public static let maxBytes = 64 * 1024
    public static let maxNodes = 1500
    public static let maxDepth = 16
    public static let maxImages = 400
    public static let maxAssets = 64
    public static let maxAreas = 400
    public static let maxKeys = 160
    public static let maxTimers = 8
    public static let maxRuns = 32
    public static let maxSteps = 600
    public static let maxEvents = 200
    /// Everything handed to the animator: the points of the curves, and what a flip's turning is sampled into.
    public static let maxPoints = 6000
    /// What one scene's own bitmaps may take: words, gradients, symbols, figures and tinted pictures, drawn at twice their size,
    /// and the pictures it decodes (`drawnBytes`). The node counts above count nodes, not pixels.
    public static let maxDrawnBytes = 96 * 1024 * 1024
    public static let maxStyles = 48
    /// Each is a cached picture of Sidefolk's; nothing about the person is at stake in how many times it is placed.
    public static let maxPeople = 32
    public static let maxEntries = 2
    public static let maxClocks = 4
    public static let maxPathCommands = 240
    public static let maxTextCharacters = 400
    public static let maxAllText = 24_000
    /// How long a timeline can run: no animation, however it is repeated, draws for ever.
    public static let maxTimeline: Double = 120
    public static let maxRepeats = 40
    public static let coordinates = -4000.0...4000.0
}

public struct SceneSize: Sendable, Hashable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// A colour by the theme's name, a verdict's name, or a plain value, which may differ in the dark.
public enum SceneColor: Sendable, Hashable {
    /// `#RRGGBBAA` as a number.
    case rgba(UInt32)
    case token(Token)
    case adaptive(light: UInt32, dark: UInt32)
    /// A theme colour made lighter or darker (-1…1) or see-through (0…1), as a lip under a key or a gradient to itself.
    case tuned(Token, alpha: Double, brightness: Double)

    public enum Token: String, Sendable, Hashable, CaseIterable {
        case ink, inkMuted = "ink_muted", inkFaint = "ink_faint", surface, surfaceSunken = "surface_sunken", surfaceRaised = "surface_raised",
             line, well, accent, onAccent = "on_accent", accentSoft = "accent_soft", link, success, successSoft = "success_soft", warning,
             warningSoft = "warning_soft", info, clear
        /// The verdicts (D75, D78): what a result means for the person. A loss is a calm warm tone, never the danger red;
        /// draw it with a symbol or a word, never colour alone.
        case win, loss, draw
    }
}

/// One thing on the canvas. `x`, `y`, `width` and `height` are its box in its parent, from the top left; `scale`,
/// `rotate` and `opacity` act around `anchor`.
public struct SceneNode: Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: Kind
    public var x = 0.0, y = 0.0, width = 0.0, height = 0.0
    public var anchorX = 0.5, anchorY = 0.5
    public var scaleX = 1.0, scaleY = 1.0, rotate = 0.0, opacity = 1.0, z = 0.0
    public var clips = false
    public var corner = 0.0
    public var shadow: SceneShadow?
    public var children: [SceneNode] = []
    public var area: SceneArea?
    /// This node's own contents never mirror (a picture, a grid: the same in every language).
    public var ltr = false
    /// What VoiceOver reads for a thing that can't be pressed; nil leaves it out.
    public var label: String?

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    public enum Kind: Sendable, Hashable {
        case group
        case image(SceneImage)
        case text(SceneText)
        case shape(SceneShape)
        case symbol(SceneSymbol)
        /// Two faces on one turning plate: `children[0]` the front and `children[1]` the back; a `flip` value of 1 shows
        /// the back, 2 the front again, in half turns.
        case flip(SceneFlip)
        /// The person's companion, drawn by Sidefolk: the extension places it and never gets its picture.
        case companion(pose: SceneCompanionPose, look: SceneFigureLook)
        /// The person, by their Mac account's picture or a friendly stand-in: the same rule.
        case person(look: SceneFigureLook)
        /// A clipped box whose children are taller than it: the wheel and the trackpad move them, in the app, with nothing sent.
        case scroll(SceneScroll)
        case entry(SceneEntry)
        case clock(SceneClock)
    }
}

public struct SceneShadow: Sendable, Hashable {
    public var color: SceneColor
    public var radius: Double
    public var dx: Double
    public var dy: Double
}

/// How a figure Sidefolk draws sits in its box. The picture stays Sidefolk's; the extension only says how to place it.
public struct SceneFigureLook: Sendable, Hashable {
    /// The profile picture rather than the whole figure. For the person there is only one.
    public var face = false
    /// Stands on the box's bottom edge rather than in its middle.
    public var bottom = false
    /// Drawn in shades of this colour (a face on a gold coin).
    public var duotone: SceneColor?

    public init(face: Bool = false, bottom: Bool = false, duotone: SceneColor? = nil) {
        self.face = face
        self.bottom = bottom
        self.duotone = duotone
    }
}

/// `height` is what the children take up. `to` keeps a node in view: the keyboard's selection, say, sent with a new scene.
public struct SceneScroll: Sendable, Hashable {
    public var contentHeight: Double
    public var to: String?
}

public struct SceneImage: Sendable, Hashable {
    public enum Fit: String, Sendable, Hashable { case fill, contain, cover }
    /// Relative to the pack's assets folder.
    public var path: String
    /// Another picture in dark mode (a scene at night).
    public var dark: String?
    public var fit: Fit
    /// Drawn as a stencil in this colour.
    public var tint: SceneColor?
}

public struct SceneText: Sendable, Hashable {
    public enum Weight: String, Sendable, Hashable { case regular, medium, semibold, bold, heavy, black }
    /// `theme` is the theme's own face at its own scale, whichever the person chose.
    public enum Design: String, Sendable, Hashable { case standard = "default", rounded, serif, mono, theme }
    /// Part of the words in its own colour or weight, in one wrapping line.
    public struct Run: Sendable, Hashable {
        public var text: String
        public var color: SceneColor?
        public var weight: Weight?
    }
    public enum Align: String, Sendable, Hashable { case leading, center, trailing }
    public enum VAlign: String, Sendable, Hashable { case top, center, bottom }
    /// May hold `{companion}`, which Sidefolk fills in when it draws: an extension shows the name without knowing it.
    public var text: String
    public var size: Double
    public var weight: Weight
    public var design: Design
    public var color: SceneColor
    public var align: Align
    public var vAlign: VAlign
    public var lines: Int
    public var minScale: Double
    public var italic = false
    /// Digits of one width, so a running number doesn't jitter.
    public var tabular = false
    public var strike = false
    /// When any, these are the words, and `text` is them joined.
    public var runs: [Run] = []
}

public struct SceneShape: Sendable, Hashable {
    public enum Form: Sendable, Hashable {
        case rect, ellipse, capsule
        /// Points in the node's box, from the top left.
        case path([PathOp])
    }
    public enum PathOp: Sendable, Hashable {
        case move(Double, Double)
        case line(Double, Double)
        case quad(Double, Double, Double, Double)
        case cubic(Double, Double, Double, Double, Double, Double)
        case close
    }
    public struct Gradient: Sendable, Hashable {
        public var colors: [SceneColor]
        /// In the box, 0–1.
        public var fromX: Double, fromY: Double, toX: Double, toY: Double
    }
    public var form: Form
    public var fill: SceneColor?
    public var gradient: Gradient?
    public var stroke: SceneColor?
    public var lineWidth: Double
    public var dash: [Double]
}

public struct SceneSymbol: Sendable, Hashable {
    /// An SF Symbol, by the rule pages use.
    public var name: String
    public var color: SceneColor
    public var weight: SceneText.Weight = .semibold
    /// One flat colour, rather than the system's lighter layers.
    public var mono = false
    /// A second colour for a symbol's second layer.
    public var secondary: SceneColor?
}

public struct SceneFlip: Sendable, Hashable {
    public enum Axis: String, Sendable, Hashable { case x, y }
    public var axis: Axis
    /// Half turns at rest: odd shows the back.
    public var turns: Double
}

/// The poses every companion is drawn in, as the Play panel uses them. Nothing else about it is reachable.
public enum SceneCompanionPose: String, Sendable, Hashable, CaseIterable {
    case idle, listening, thinking, waiting, success, alert, celebrating
}

/// A one-line field typed with the person's input method; Return sends `entry`.
public struct SceneEntry: Sendable, Hashable {
    public var id: String
    public var placeholder: String?
    public var max: Int
    public var locked: Bool
    public var size: Double
    /// Takes the keyboard when it appears, if the surface has the keyboard.
    public var focus = false
    /// No box of its own: the scene draws what it sits on.
    public var plain = false
    public var weight: SceneText.Weight = .regular
    public var design: SceneText.Design = .standard
}

/// Time drawn in the text's style, once a second while `running`; a stopped clock costs nothing.
public struct SceneClock: Sendable, Hashable {
    public var seconds: Double
    public var running: Bool
    /// Counts down to 0 rather than on.
    public var down: Bool
    public var style: SceneText
}

/// Where a node can be clicked or dragged. Every area says what it is for VoiceOver, or it isn't an area.
public struct SceneArea: Sendable, Hashable {
    public var id: String
    /// Which of many sharing an id: a cell, a key. Sent back with the move.
    public var value: String?
    public var label: String
    public var disabled = false
    /// Takes its move while an animation holds the rest (the companion clicked mid-shuffle).
    public var always = false
    public var hover: SceneStyle?
    public var press: SceneStyle?
    /// Other nodes that take `hover` while this one is under the pointer.
    public var highlight: [String] = []
    /// Other nodes that take a look of their own while this one is under the pointer: lift one, reveal another.
    public var looks: [String: SceneStyle] = [:]
    /// Sends what is typed in this field of the scene, as Return does; takes no press while it is empty.
    public var submits: String?
    /// A sound from the pack on the press itself, before the extension answers.
    public var sound: String?
    public var drag: SceneDrag?
    /// A moment in the scene (ms after it shows), from which the press is timed: the move carries `ms`, below 0 for a
    /// press before it. Measured from the input event's own time, so an extension can run a reflex test.
    public var timedFrom: Double?
    public var selected = false

    public init(id: String, value: String? = nil, label: String) {
        self.id = id
        self.value = value
        self.label = label
    }
}

public struct SceneStyle: Sendable, Hashable {
    public var scale: Double?
    public var dx: Double?
    public var dy: Double?
    public var opacity: Double?
    public var rotate: Double?
    /// `opacity` is the value itself, not a part of the node's own: a node at 0 can appear.
    public var absolute = false

    public init(scale: Double? = nil, dx: Double? = nil, dy: Double? = nil, opacity: Double? = nil, rotate: Double? = nil, absolute: Bool = false) {
        self.scale = scale
        self.dx = dx
        self.dy = dy
        self.opacity = opacity
        self.rotate = rotate
        self.absolute = absolute
    }
}

/// Dragging on an area: over a grid (`from` and `to` are cells) or freely (points in the canvas, the node following).
public struct SceneDrag: Sendable, Hashable {
    public enum Mode: Sendable, Hashable {
        case free
        case grid(rows: Int, columns: Int)
    }
    public var mode: Mode
    /// A node of the scene stretched from the first cell to the one under the pointer, or moved with it.
    public var ghost: String?
    /// How far the ghost stays inside the cells it covers.
    public var inset: Double = 0
}

/// A key the scene takes while the surface has the keyboard. Command keys, Tab and the frame's own are never offered.
public struct SceneKey: Sendable, Hashable {
    public enum Match: Sendable, Hashable {
        /// One character the person's keyboard types, lowercase.
        case character(String)
        case named(Named)
        /// Any letter, in any script; the move carries it.
        case anyLetter
        case anyDigit
    }
    public enum Named: String, Sendable, Hashable, CaseIterable { case `return`, space, delete, left, right, up, down, escape }

    public var match: Match
    public var id: String
    /// Presses this area instead of sending a key move, with its feedback.
    public var area: String?
    public var value: String?
    /// The key at this place on a US keyboard, whatever the layout: two players' sides.
    public var bySeat = false
    public var timedFrom: Double?
    /// Takes its move while an animation holds the rest.
    public var always = false
}

/// Sidefolk keeps the time: when one ends the extension hears `timer`. The same id on the next scene keeps it running.
public struct SceneTimer: Sendable, Hashable {
    public var id: String
    public var seconds: Double
    public init(id: String, seconds: Double) {
        self.id = id
        self.seconds = seconds
    }
}

/// The companion's reaction, from Sidefolk's fixed lists: no words, nothing it can drive. Paced by `CueLimiter`.
public struct SceneReaction: Sendable, Hashable {
    public var move: Move?
    public var effect: CompanionCue.Effect?
    public var prop: CompanionCue.Prop?
    public var look: Look?

    public init(move: Move? = nil, effect: CompanionCue.Effect? = nil, prop: CompanionCue.Prop? = nil, look: Look? = nil) {
        self.move = move
        self.effect = effect
        self.prop = prop
        self.look = look
    }

    /// The existing moves; `pump`, `flick` and `roll` are a fist pumped, a coin flicked and dice thrown.
    public enum Move: Sendable, Hashable {
        case cue(CompanionCue.Move)
        case pump, flick, roll

        init?(_ raw: String) {
            switch raw {
            case "pump": self = .pump
            case "flick": self = .flick
            case "roll": self = .roll
            default:
                guard let move = CompanionCue.Move(rawValue: raw) else { return nil }
                self = .cue(move)
            }
        }
    }

    public enum Look: String, Sendable, Hashable { case panel, you, away }

    static func parse(_ j: JSONValue?) -> SceneReaction? {
        guard let j, j.objectValue != nil else { return nil }
        let reaction = SceneReaction(move: j["move"]?.stringValue.flatMap(Move.init), effect: j["effect"]?.stringValue.flatMap(CompanionCue.Effect.init(rawValue:)),
                                     prop: j["prop"]?.stringValue.flatMap(CompanionCue.Prop.parse), look: j["look"]?.stringValue.flatMap(Look.init(rawValue:)))
        return reaction == SceneReaction() ? nil : reaction
    }
}

/// One animation of a scene, flattened to curves when it was read, so the app only hands them to Core Animation. The
/// same `id` with the same content on the next scene carries on rather than starting again.
public struct SceneRun: Sendable, Hashable {
    public var id: String?
    public var curves: [SceneCurve] = []
    public var frames: [SceneFrames] = []
    public var events: [SceneEvent] = []
    /// Seconds to its last point, event or frame.
    public var duration: Double = 0
    /// Seconds until moves are taken, from its start; 0 when it holds nothing. `stillBlocks` is the same under Reduce Motion.
    public var blocks: Double = 0
    public var stillBlocks: Double = 0
}

public enum SceneProperty: String, Sendable, Hashable, CaseIterable { case x, y, scale, scaleX, scaleY, rotate, opacity, flip, z }

/// A value over time, for one property of one node: times in seconds from the run's start.
public struct SceneCurve: Sendable, Hashable {
    public var target: String
    public var property: SceneProperty
    public var times: [Double]
    public var values: [Double]
    /// One for each span between points.
    public var eases: [SceneEase]
    /// Keeps moving under Reduce Motion (when the movement is the point). Otherwise it is skipped and the end shows at once.
    public var essential: Bool
}

public enum SceneEase: String, Sendable, Hashable { case linear, easeIn = "in", easeOut = "out", easeInOut = "in_out", spring, step }

/// A picture swapped over time (dice tumbling): frames from the pack.
public struct SceneFrames: Sendable, Hashable {
    public var target: String
    public var times: [Double]
    public var paths: [String]
    public var essential: Bool
}

/// Something that happens at a moment of a run: a sound, the companion's reaction, what VoiceOver hears.
public struct SceneEvent: Sendable, Hashable {
    public var at: Double
    public var sound: String?
    public var react: SceneReaction?
    public var announce: String?
}
