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
    }

    public struct CompanionSection: Codable, Sendable, Equatable {
        public var nook: String?
        /// A PNG behind the companion in its nook.
        public var backdrop: String?
        public var suggests: String?
    }

    public struct Art: Codable, Sendable, Equatable {
        /// A PNG for empty pages, in place of the folk.
        public var empty: String?
    }

    public var format: Int
    public var id: String
    public var name: String
    public var author: String?
    public var version: String?
    public var summary: String?
    public var recipes: [String: String]?
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
        [("material.grain", material?.grain), ("companion.backdrop", companion?.backdrop), ("art.empty", art?.empty)]
            .compactMap { role, path in path.map { (role, $0) } }
    }
}

extension ThemeFile {
    /// A theme file that says exactly what `tokens` are: what `sidefolk theme new` starts from.
    public init(_ tokens: ThemeTokens, id: String, name: String, author: String? = nil) {
        self.init(format: Self.currentFormat, id: id, name: name, author: author, version: "1.0.0",
                  summary: "A theme for Sidefolk.",
                  recipes: ["navigation": tokens.recipes.navigation.rawValue, "today": tokens.recipes.today.rawValue,
                            "activity": tokens.recipes.activity.rawValue, "editor": tokens.recipes.editor.rawValue],
                  type: TypeSection(display: tokens.type.display.rawValue, text: "system", exact: "mono",
                                    scale: tokens.type.scale, density: tokens.type.density.rawValue),
                  shape: Shape(control: tokens.radius.control, card: tokens.radius.card, window: tokens.radius.panel),
                  colors: ["light": Self.hexes(tokens.colors, dark: false), "dark": Self.hexes(tokens.colors, dark: true)],
                  material: MaterialSection(sidebar: tokens.material.sidebar.rawValue, grain: nil),
                  companion: CompanionSection(nook: tokens.nook.style.rawValue, backdrop: nil, suggests: tokens.nook.suggests?.rawValue),
                  art: nil, motion: tokens.motion.rawValue)
    }

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
