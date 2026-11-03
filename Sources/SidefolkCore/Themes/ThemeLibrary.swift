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
    /// As its theme.json says, for updates from the gallery.
    public var version: String?

    public var id: String { tokens.id }

    public init(tokens: ThemeTokens, images: [String: URL] = [:], folder: URL? = nil, version: String? = nil) {
        self.tokens = tokens
        self.images = images
        self.folder = folder
        self.version = version
    }

    public static let sidefolk = InstalledTheme(tokens: .sidefolk)
}

/// The themes Sidefolk can use (D58): the default and the others it ships in its Resources (`Themes/<name>/`), and themes added
/// from a folder or the gallery, which are checked and copied into `<home>/Themes/<id>/` with every image decoded and
/// written again by Sidefolk, so only plain pixels are kept.
public struct ThemeLibrary: Sendable {
    /// Ids that are Sidefolk's own: only its Resources and its signed gallery may use them.
    public static let ownPrefix = "dev.sidefolk."
    /// The built-ins in the order they're offered.
    public static let builtInOrder = [ThemeTokens.sidefolk.id, "dev.sidefolk.theme.harbor", "dev.sidefolk.theme.paper-garden", "dev.sidefolk.theme.night-studio", "dev.sidefolk.theme.marshmallow"]

    let directory: URL
    let bundled: URL?

    /// - Parameter bundled: the app's `Resources/Themes`, where the built-ins and the default's art live.
    public init(paths: SidefolkPaths, bundled: URL? = nil) {
        directory = paths.themes
        self.bundled = bundled
    }

    /// The default, with its art when the app ships it, then the themes Sidefolk ships, in their order.
    public func builtIns() -> [InstalledTheme] {
        let shipped = ((try? FileManager.default.contentsOfDirectory(at: bundled ?? directory.appendingPathComponent(".none"),
                                                                     includingPropertiesForKeys: nil)) ?? [])
            .compactMap { folder -> InstalledTheme? in
                let report = ThemeCheck.check(folder: folder)
                guard report.isUsable, Self.isOwn(report.tokens.id) else { return nil }
                return InstalledTheme(tokens: report.tokens, images: report.images, folder: nil)
            }
        let rank = { (id: String) in Self.builtInOrder.firstIndex(of: id) ?? Self.builtInOrder.count }
        let sorted = shipped.sorted { rank($0.id) < rank($1.id) }
        return sorted.first?.id == ThemeTokens.sidefolk.id ? sorted : [.sidefolk] + sorted
    }

    /// The built-ins, then the added themes by name.
    public func all() -> [InstalledTheme] {
        let builtIns = builtIns()
        let added = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .compactMap(installed)
            .filter { theme in !builtIns.contains { $0.id == theme.id } }
            .sorted { $0.tokens.name.localizedStandardCompare($1.tokens.name) == .orderedAscending }
        return builtIns + added
    }

    /// The theme with this id, or the default when there's none (removed, or never there).
    public func theme(id: String) -> InstalledTheme {
        let themes = all()
        return themes.first { $0.id == id } ?? themes.first { $0.id == ThemeTokens.sidefolk.id } ?? .sidefolk
    }

    /// One of Sidefolk's own ids: the default's, what Harbor was when it was the default, or any under the prefix.
    static func isOwn(_ id: String) -> Bool {
        id == ThemeTokens.sidefolk.id || id == "harbor" || id.hasPrefix(ownPrefix)
    }

    /// Checks the theme in `folder` and keeps a copy; a theme with the same id is replaced. Only Sidefolk's signed gallery
    /// (`own`) may install a theme with one of Sidefolk's ids.
    public func install(from folder: URL, own: Bool = false) throws -> (theme: InstalledTheme, report: ThemeReport) {
        // Sidefolk's own gallery was checked when it was published; a newer rule doesn't refuse what it already offers.
        let report = ThemeCheck.check(folder: folder, strict: !own)
        guard report.isUsable, let file = report.file else {
            throw UserFacingError("This theme can't be used yet.",
                                  detail: report.problems.filter { $0.level == .error }.map(\.message).joined(separator: "\n"))
        }
        if !own, Self.isOwn(file.id) {
            throw UserFacingError("This theme's id is one of Sidefolk's own.", recovery: "Give it an id of your own, like com.you.sunset.")
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
        guard !builtIns().contains(where: { $0.id == id }) else { return }
        let target = directory.appendingPathComponent(id, isDirectory: true)
        guard target.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: target)
    }

    private func installed(_ folder: URL) -> InstalledTheme? {
        guard !folder.lastPathComponent.hasPrefix(".") else { return nil }
        // A copy passed the check when it was added: a rule added since warns rather than taking the theme away.
        let report = ThemeCheck.check(folder: folder, strict: false)
        guard report.isUsable else { return nil }
        return InstalledTheme(tokens: report.tokens, images: report.images, folder: folder, version: report.file?.version)
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

    /// A new theme folder at `folder`, copied from the default, with a short guide: what `sidefolk theme new` makes.
    public static func start(_ name: String, at folder: URL) throws -> URL {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: folder.appendingPathComponent("theme.json").path) else {
            throw UserFacingError("\(folder.path) already has a theme.json.")
        }
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        let file = ThemeFile(.sidefolk, id: "com.example.\(slug.isEmpty ? "theme" : slug)", name: name.clipped(40))
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try file.encoded().write(to: folder.appendingPathComponent("theme.json"))
        try guide.write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        return folder
    }

    static let guide = """
        # A Sidefolk theme

        `theme.json` starts as a copy of the default theme. Change what you like, then:

        - `sidefolk theme check <this folder>` says what's wrong, in words, and how well each text colour reads.
        - Settings › Appearance › Theme › Load from folder… uses it and repaints every window each time you save.

        **id**: yours, lowercase, like `com.you.sunset`. **name**: up to 40 characters.

        **colors**: `light` and `dark`, each with every role as `#RRGGBB`: ink, inkMuted, inkFaint (text, strongest to
        faintest); surface, surfaceSunken, surfaceRaised, line (what things sit on); accent, onAccent, accentSoft (fills
        and the text on them); link (the accent as text); danger, dangerSoft, onDanger; success, successSoft; warning,
        warningSoft, onWarning; well (fields, chips and the search, inside cards). Text must read at 4.5:1 on every
        surface; the check tells you which pair doesn't. `glow` and `waitGlow` are light, never text: the pool at the
        companion's feet while it works and when something waits on you. well, glow, waitGlow, sidebar, sidebarInk, sidebarInkMuted,
        sidebarSelected (3:1 from the sidebar), onSidebarSelected, sceneInk and sceneInkMuted may be left out.
        Status colours keep their meaning: danger looks red (an error or a real risk), warning amber (waiting, needs a
        look), success green (done, allowed, won).

        **type**: `display` is system, rounded or serif (headings); `scale` 0.9 to 1.15; `density` compact, regular or
        relaxed. The display face is for titles, the greeting and big numbers; what you read, the companion's words
        included, is always the system face.

        **shape**: corner radii for `control` (4 to 999), `card` and `window` (0 to 28).

        **motion**: calm, bouncy or none (Reduce Motion always wins). **material**: `sidebar` solid or translucent;
        `depth` line or soft, how cards sit on a page; `grain`, a PNG tiled faintly over the pages; `page` and `pageDark`, a
        wide PNG washed in at the top of each page and faded into it; `scene` and `sceneDark`, a wide PNG at the top of Today
        whose sky stays behind the toolbar on every page. **companion**: `header` and `headerDark`, a PNG at the top of the
        sidebar with the companion standing in it, and `logo` true for the wordmark there; `backdrop` and `backdropDark`, a
        PNG faded behind the companion's card when there's no header; `suggests`, a companion the theme was drawn for. **art**: `empty`, a PNG for empty pages.
        A theme dresses Sidefolk, it doesn't arrange it: each place has one layout, and of `layout` only `icons`
        (simple or colorful) is read.

        Images are PNGs inside this folder, 2 MB and 2048 pixels a side at most. A theme can't run anything.
        """
}
