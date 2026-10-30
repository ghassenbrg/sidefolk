import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A theme ready to use: its tokens, and its images as Sidefolk's own copies.
public struct InstalledTheme: Sendable, Equatable {
    public var tokens: ThemeTokens
    /// By role ("material.grain", "companion.backdrop", "art.empty").
    public var images: [String: URL]
    /// Where Sidefolk keeps it; nil for a built-in.
    public var folder: URL?

    public var id: String { tokens.id }

    public init(tokens: ThemeTokens, images: [String: URL] = [:], folder: URL? = nil) {
        self.tokens = tokens
        self.images = images
        self.folder = folder
    }

    public static let harbor = InstalledTheme(tokens: .harbor)
}

/// The themes Sidefolk can use (D58): its built-ins, and themes added from a folder, which are checked and copied into
/// `<home>/Themes/<id>/` with every image decoded and written again by Sidefolk, so only plain pixels are kept.
public struct ThemeLibrary: Sendable {
    public static let builtIn: [ThemeTokens] = [.harbor]

    let directory: URL

    public init(paths: SidefolkPaths) {
        directory = paths.themes
    }

    /// The built-ins, then the added themes by name.
    public func all() -> [InstalledTheme] {
        let added = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .compactMap(installed).sorted { $0.tokens.name.localizedStandardCompare($1.tokens.name) == .orderedAscending }
        return Self.builtIn.map { InstalledTheme(tokens: $0) } + added
    }

    /// The theme with this id, or Harbor when there's none (removed, or never there).
    public func theme(id: String) -> InstalledTheme {
        all().first { $0.id == id } ?? .harbor
    }

    /// Checks the theme in `folder` and keeps a copy; a theme with the same id is replaced.
    public func install(from folder: URL) throws -> (theme: InstalledTheme, report: ThemeReport) {
        let report = ThemeCheck.check(folder: folder)
        guard report.isUsable, let file = report.file else {
            throw UserFacingError("This theme can't be used yet.",
                                  detail: report.problems.filter { $0.level == .error }.map(\.message).joined(separator: "\n"))
        }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".\(file.id)-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        try file.encoded().write(to: staging.appendingPathComponent("theme.json"))
        for (role, path) in file.images {
            guard let source = report.images[role] else { continue }
            try Self.reencode(source, to: staging.appendingPathComponent(path))
        }
        let target = directory.appendingPathComponent(file.id, isDirectory: true)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: staging, to: target)
        guard let theme = installed(target) else { throw UserFacingError("The theme was copied but couldn't be read back.") }
        return (theme, report)
    }

    /// Takes an added theme away; a built-in can't be.
    public func remove(id: String) throws {
        guard !Self.builtIn.contains(where: { $0.id == id }) else { return }
        let target = directory.appendingPathComponent(id, isDirectory: true)
        guard target.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: target)
    }

    private func installed(_ folder: URL) -> InstalledTheme? {
        guard !folder.lastPathComponent.hasPrefix(".") else { return nil }
        let report = ThemeCheck.check(folder: folder)
        guard report.isUsable else { return nil }
        return InstalledTheme(tokens: report.tokens, images: report.images, folder: folder)
    }

    /// Decodes an image and writes its pixels as a new PNG, leaving behind anything else the file carried.
    static func reencode(_ source: URL, to target: URL) throws {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(input, 0, nil) else {
            throw UserFacingError("“\(source.lastPathComponent)” couldn't be read as an image.")
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let output = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw UserFacingError("“\(target.lastPathComponent)” couldn't be written.")
        }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw UserFacingError("“\(target.lastPathComponent)” couldn't be written.") }
    }

    // MARK: Starting a theme

    /// A new theme folder at `folder`, copied from Harbor, with a short guide: what `sidefolk theme new` makes.
    public static func start(_ name: String, at folder: URL) throws -> URL {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: folder.appendingPathComponent("theme.json").path) else {
            throw UserFacingError("\(folder.path) already has a theme.json.")
        }
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        let file = ThemeFile(.harbor, id: "com.example.\(slug.isEmpty ? "theme" : slug)", name: name.clipped(40))
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try file.encoded().write(to: folder.appendingPathComponent("theme.json"))
        try guide.write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        return folder
    }

    static let guide = """
        # A Sidefolk theme

        `theme.json` starts as a copy of Harbor. Change what you like, then:

        - `sidefolk theme check <this folder>` says what's wrong, in words, and how well each text colour reads.
        - Settings › General › Theme › Load from Folder… uses it and repaints every window each time you save.

        **id**: yours, lowercase, like `com.you.sunset`. **name**: up to 40 characters.

        **colors**: `light` and `dark`, each with every role as `#RRGGBB`: ink, inkMuted, inkFaint (text, strongest to
        faintest); surface, surfaceSunken, surfaceRaised, line (what things sit on); accent, onAccent, accentSoft (fills
        and the text on them); link (the accent as text); danger, dangerSoft, onDanger; success, successSoft. Text must
        read at 4.5:1 on every surface; the check tells you which pair doesn't.

        **type**: `display` is system, rounded or serif (headings); `scale` 0.9 to 1.15; `density` compact, regular or
        relaxed. Body text is always the system face.

        **shape**: corner radii for `control` (4 to 999), `card` and `window` (0 to 28).

        **motion**: calm, bouncy or none (Reduce Motion always wins). **material**: `sidebar` solid or translucent;
        `grain`, a PNG tiled faintly over the pages. **companion**: `nook` cushion, badge or sticker; `backdrop`, a PNG
        behind it; `suggests`, a companion the theme was drawn for. **art**: `empty`, a PNG for empty pages.

        Images are PNGs inside this folder, 2 MB and 2048 pixels a side at most. A theme can't run anything.
        """
}
