import Foundation

/// A theme as written in `theme.json` (D58), format 1. Every section is optional: what's missing comes from Harbor,
/// and the check says so. Nothing in it can run: it names colours, sizes, a few images and the app's own layouts.
public struct ThemeFile: Codable, Sendable, Equatable {
    public struct TypeSection: Codable, Sendable, Equatable {
        public var display: String?
        /// Always "system": body text stays the system face, whatever a theme says.
        public var text: String?
        /// Always "mono", for anything exact.
        public var exact: String?
        public var scale: Double?
        public var density: String?
    }

    public struct Shape: Codable, Sendable, Equatable {
        public var control: Double?
        public var card: Double?
        public var window: Double?
    }

    public struct MaterialSection: Codable, Sendable, Equatable {
        public var sidebar: String?
        /// A PNG tiled faintly over the pages.
        public var grain: String?
        /// A PNG washed in at the top of each page, behind the cards (a sky, a dusk), fading to the page's colour.
        public var page: String?
        /// The same in the dark appearance; without it, a dark page has no wash.
        public var pageDark: String?
    }

    public struct CompanionSection: Codable, Sendable, Equatable {
        public var nook: String?
        /// A PNG behind the companion in its nook, or on its stage.
        public var backdrop: String?
        /// The same in the dark appearance.
        public var backdropDark: String?
        public var suggests: String?
    }

    public struct Art: Codable, Sendable, Equatable {
        /// A PNG for empty pages, in place of the folk.
        public var empty: String?
        /// A PNG for the `art` block: a picture among the cards, never behind words.
        public var tile: String?
    }

    /// Where things go (D62): a preset by name, then anything the theme sets itself.
    public struct LayoutSection: Codable, Sendable, Equatable {
        public var preset: String?
        public var navigation: String?
        public var nook: String?
        /// Rows, each a list of columns; a column is a block ("queue:cards") or {"width": 2, "blocks": [...]}.
        public var today: [[ColumnSection]]?
        public var activity: String?
        public var editor: String?
    }

    public enum ColumnSection: Codable, Sendable, Equatable {
        case block(String)
        case column(width: Double?, page: Bool? = nil, blocks: [String])

        private enum Keys: String, CodingKey { case width, page, blocks }

        public init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer().decode(String.self) {
                self = .block(single)
                return
            }
            let c = try decoder.container(keyedBy: Keys.self)
            self = .column(width: try c.decodeIfPresent(Double.self, forKey: .width),
                           page: try c.decodeIfPresent(Bool.self, forKey: .page),
                           blocks: try c.decodeIfPresent([String].self, forKey: .blocks) ?? [])
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .block(let name):
                var c = encoder.singleValueContainer()
                try c.encode(name)
            case .column(let width, let page, let blocks):
                var c = encoder.container(keyedBy: Keys.self)
                try c.encodeIfPresent(width, forKey: .width)
                try c.encodeIfPresent(page, forKey: .page)
                try c.encode(blocks, forKey: .blocks)
            }
        }

        var width: Double? { if case .column(let w, _, _) = self { w } else { nil } }
        var page: Bool? { if case .column(_, let p, _) = self { p } else { nil } }
        var blocks: [String] {
            switch self {
            case .block(let name): [name]
            case .column(_, _, let blocks): blocks
            }
        }
    }

    public var format: Int
    public var id: String
    public var name: String
    public var author: String?
    public var version: String?
    public var summary: String?
    public var layout: LayoutSection?
    public var type: TypeSection?
    public var shape: Shape?
    public var colors: [String: [String: String]]?
    public var material: MaterialSection?
    public var companion: CompanionSection?
    public var art: Art?
    public var motion: String?

    public static let currentFormat = 1
    /// Larger than any real theme file; anything bigger is refused before it is read.
    public static let maxBytes = 64 * 1024

    /// The images it names, by what they're for.
    public var images: [(role: String, path: String)] {
        [("material.grain", material?.grain), ("material.page", material?.page), ("material.pageDark", material?.pageDark), ("companion.backdrop", companion?.backdrop), ("companion.backdropDark", companion?.backdropDark),
         ("art.empty", art?.empty), ("art.tile", art?.tile)]
            .compactMap { role, path in path.map { (role, $0) } }
    }
}

extension ThemeFile {
    /// A theme file that says exactly what `tokens` are: what `sidefolk theme new` starts from.
    public init(_ tokens: ThemeTokens, id: String, name: String, author: String? = nil) {
        self.init(format: Self.currentFormat, id: id, name: name, author: author, version: "1.0.0",
                  summary: "A theme for Sidefolk.",
                  layout: LayoutSection(tokens.layout),
                  type: TypeSection(display: tokens.type.display.rawValue, text: "system", exact: "mono",
                                    scale: tokens.type.scale, density: tokens.type.density.rawValue),
                  shape: Shape(control: tokens.radius.control, card: tokens.radius.card, window: tokens.radius.panel),
                  colors: ["light": Self.hexes(tokens.colors, dark: false), "dark": Self.hexes(tokens.colors, dark: true)],
                  material: MaterialSection(sidebar: tokens.material.sidebar.rawValue, grain: nil, page: nil, pageDark: nil),
                  companion: CompanionSection(nook: tokens.nook.style.rawValue, backdrop: nil, backdropDark: nil, suggests: tokens.nook.suggests?.rawValue),
                  art: nil, motion: tokens.motion.rawValue)
    }

}

extension ThemeFile.LayoutSection {
    /// A layout written out in full, so whoever starts from it sees every block and can move it.
    public init(_ layout: ThemeLayout) {
        self.init(preset: nil, navigation: layout.navigation.rawValue, nook: layout.nook.rawValue,
                  today: layout.today.map { row in
                      row.map { column in
                          column.width == 1 && column.blocks.count == 1 && !column.page
                              ? .block(column.blocks[0].description)
                              : .column(width: column.width, page: column.page ? true : nil, blocks: column.blocks.map(\.description))
                      }
                  },
                  activity: layout.activity.rawValue, editor: layout.editor.rawValue)
    }
}

extension ThemeFile {
    private static func hexes(_ colors: ThemeTokens.Colors, dark: Bool) -> [String: String] {
        Dictionary(uniqueKeysWithValues: ThemeTokens.Colors.roles.map { role in
            let pair = colors[keyPath: role.key]
            return (role.name, String(format: "#%06X", dark ? pair.dark : pair.light))
        })
    }

    /// Pretty JSON with its keys in order, as written to a theme folder.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// "#RRGGBB" (or "RRGGBB") as 0xRRGGBB.
    static func colour(_ text: String) -> UInt32? {
        let hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(hex, radix: 16)
    }
}
