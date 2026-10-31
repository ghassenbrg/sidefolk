import Foundation

/// What is left of a theme's layout (D64) since each place has one layout (D84): how Home draws its icons. A theme
/// file's other layout keys (`preset`, `navigation`, `nook`, `today`, `activity`, `editor`) still decode, so every
/// theme made for D64 loads as it did, but nothing reads or checks them; a preset lives on only as the icons it chose.
public struct ThemeLayout: Sendable, Equatable {
    /// How Home's navigation draws its icons (D67): `simple`, the glyph in its colour; `colorful`, a white glyph on a
    /// rounded tile of that colour, and each extension page with its extension's own icon. The person may override it
    /// in Settings › Appearance.
    public enum Icons: String, Sendable, Equatable, Codable, CaseIterable { case simple, colorful }

    public var icons: Icons

    public init(icons: Icons = .simple) { self.icons = icons }

    /// Harbor's, and every theme's that says nothing.
    public static let desk = ThemeLayout()

    /// The D64 presets a theme may still name, as the icons each chose (Marshmallow's stage was colourful).
    public static let presets: [String: ThemeLayout] = [
        "desk": desk, "board": desk, "console": desk, "planner": desk, "stage": ThemeLayout(icons: .colorful),
    ]
}
