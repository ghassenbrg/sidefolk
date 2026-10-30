import Foundation

/// Where things go and how they look, as data (D62). Today is rows of columns of blocks; each block is one of the
/// app's own pieces (what needs you, your day, watching…) in one of its styles. A theme arranges and dresses them;
/// it never brings views of its own. The boards' layouts are presets written the same way.
public struct ThemeLayout: Sendable, Equatable {
    public enum Navigation: String, Sendable, Equatable, CaseIterable { case sidebar, pills, rail, ribbons }
    /// Where the companion's nook sits in a sidebar; `none` when the layout gives the companion a block of its own.
    public enum NookPlace: String, Sendable, Equatable, CaseIterable { case top, foot, none }
    public enum Activity: String, Sendable, Equatable, CaseIterable { case table, log, diary }
    public enum Editor: String, Sendable, Equatable, CaseIterable { case rich, markdown }

    /// One of the app's pieces of Today, in one of its styles.
    public struct Block: Sendable, Equatable, Hashable, CustomStringConvertible {
        public enum Kind: String, Sendable, Equatable, CaseIterable {
            case header, queue, day, watching, agents, recent, notes, art, companion

            /// The styles each piece comes in, the first being what a bare name gets. Only styles the app draws are
            /// here; a theme naming another gets the first, and the check says so.
            public var styles: [String] {
                switch self {
                case .header: ["line", "large", "console", "page"]
                case .queue: ["rows", "cards", "stack", "index"]
                case .day: ["rail", "list", "compact", "stickers", "ruled"]
                case .watching: ["tiles", "list", "signals", "badges", "margin"]
                case .agents: ["rows", "card", "steps", "helpers"]
                case .recent: ["rows"]
                case .notes: ["cards", "chips"]
                case .art: ["tile"]
                // The stage holds what needs you too, as speech bubbles.
                case .companion: ["stage", "sticker"]
                }
            }

            /// A piece with no style drawn yet isn't offered at all.
            public static var available: [Kind] { allCases.filter { !$0.styles.isEmpty } }
        }

        public var kind: Kind
        public var style: String

        public init(_ kind: Kind, _ style: String? = nil) {
            self.kind = kind
            self.style = style ?? kind.styles.first ?? ""
        }

        /// "queue:cards", as a theme file writes it.
        public var description: String { "\(kind.rawValue):\(style)" }
    }

    /// A column of blocks, as wide as its share of the row, on the page or on a sheet of its own (`page`).
    public struct Column: Sendable, Equatable {
        public var width: Double
        public var page: Bool
        public var blocks: [Block]

        public init(width: Double = 1, page: Bool = false, _ blocks: [Block]) {
            self.width = width
            self.page = page
            self.blocks = blocks
        }

        /// Whether it holds what needs you (a queue, or a stage that speaks it).
        public var holdsQueue: Bool { blocks.contains { $0.kind == .queue || ($0.kind == .companion && $0.style == "stage") } }
    }

    public var navigation: Navigation
    public var nook: NookPlace
    /// Today, top to bottom; a row's columns sit side by side when the window has room, else one under the other.
    public var today: [[Column]]
    public var activity: Activity
    public var editor: Editor

    public init(navigation: Navigation = .sidebar, nook: NookPlace = .top, today: [[Column]], activity: Activity = .table,
                editor: Editor = .rich) {
        self.navigation = navigation
        self.nook = nook
        self.today = today
        self.activity = activity
        self.editor = editor
    }

    /// The choices the app draws today; a theme naming another gets the first, and the check says so.
    public static let drawnNavigation: [Navigation] = [.sidebar, .rail, .pills, .ribbons]
    public static let drawnNook: [NookPlace] = [.top, .foot, .none]
    public static let drawnActivity: [Activity] = [.table, .log, .diary]
    public static let drawnEditor: [Editor] = [.rich, .markdown]
    /// Most rows and columns a layout may have: more would be a page nobody can take in.
    public static let maxRows = 8
    public static let maxColumns = 4

    /// Every block, in order, for checks and tests.
    public var blocks: [Block] { today.flatMap { $0.flatMap(\.blocks) } }
}

extension ThemeLayout {
    /// Harbor's: decisions and the day on the left, what's watched, who's working and what just happened on the right.
    public static let desk = ThemeLayout(today: [
        [Column([Block(.header, "line")])],
        [Column(width: 2, [Block(.queue, "rows"), Block(.day, "rail")]),
         Column(width: 1, [Block(.watching, "tiles"), Block(.agents, "rows"), Block(.recent, "rows")])],
    ])

    /// Daylight's, Night Studio's and Paper Garden's: decisions as a row of cards, the day, watches and agents side by
    /// side, then the notebook beside the theme's picture; the companion at the foot of the sidebar.
    public static let board = ThemeLayout(nook: .foot, today: [
        [Column([Block(.header, "large")])],
        [Column([Block(.queue, "cards")])],
        [Column([Block(.day, "list")]), Column([Block(.watching, "list")]),
         Column([Block(.agents, "card")])],
        [Column(width: 3, [Block(.notes, "cards")]), Column([Block(.art, "tile")])],
    ])

    /// Night Shift's: the queue, every agent's steps, and signals with what's next, side by side; dense and in mono where
    /// words are exact.
    public static let console = ThemeLayout(navigation: .rail, nook: .none, today: [
        [Column([Block(.header, "console")])],
        [Column([Block(.queue, "stack")]), Column(width: 1.25, [Block(.agents, "steps")]),
         Column([Block(.watching, "signals"), Block(.day, "compact")])],
    ], activity: .log, editor: .markdown)

    /// Marshmallow's: the companion big on its stage, saying what needs you; the day as stickers, watches as round badges,
    /// helpers and what was jotted today beside it.
    public static let stage = ThemeLayout(navigation: .pills, nook: .none, today: [
        [Column(width: 1, [Block(.companion, "stage")]),
         Column(width: 1.15, [Block(.day, "stickers"), Block(.watching, "badges"), Block(.agents, "helpers"), Block(.notes, "chips")])],
    ])

    /// Field Notes': an open spread, the day on ruled lines on the left page; decisions as index cards, watches in the
    /// margin and the companion as a sticker on the right one.
    public static let planner = ThemeLayout(navigation: .ribbons, nook: .none, today: [
        [Column(page: true, [Block(.header, "page"), Block(.day, "ruled")]),
         Column(page: true, [Block(.queue, "index"), Block(.watching, "margin"), Block(.companion, "sticker")])],
    ], activity: .diary)

    /// The layouts a theme can start from by name, written the same way a theme writes its own.
    public static var presets: [String: ThemeLayout] {
        ["desk": desk, "board": board, "console": console, "stage": stage, "planner": planner]
    }
}
