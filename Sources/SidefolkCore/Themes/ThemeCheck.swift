import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What a theme folder is worth (D58): the tokens it resolves to, and every problem in plain words. An error stops it
/// from being used; a warning is fixed on the way in (a value clamped, a missing colour taken from Harbor).
public struct ThemeReport: Sendable {
    public struct Problem: Error, Sendable, Equatable, CustomStringConvertible {
        public enum Level: String, Sendable { case error, warning }
        public var level: Level
        public var message: String
        public var description: String { "\(level == .error ? "Error" : "Warning"): \(message)" }
    }

    public var file: ThemeFile?
    public var tokens: ThemeTokens
    public var problems: [Problem] = []
    /// Each image the theme names that passed the check, by role, in the folder.
    public var images: [String: URL] = [:]

    public var isUsable: Bool { file != nil && !problems.contains { $0.level == .error } }

    /// The report as `sidefolk theme check` prints it.
    public var text: String {
        var lines = [isUsable ? "✓ \(tokens.name) (\(tokens.id)) can be used." : "✗ This theme can't be used yet."]
        lines += problems.map(\.description)
        if file != nil {
            lines.append("")
            lines.append("Contrast (text needs 4.5:1):")
            for row in ThemeCheck.contrastRows(tokens.colors) {
                lines.append(String(format: "  %@ %-34@ light %5.2f  dark %5.2f", row.passes ? "✓" : "✗", row.label as NSString,
                                    row.light, row.dark))
            }
        }
        return lines.joined(separator: "\n")
    }
}

public enum ThemeCheck {
    /// Largest image a theme may carry, in bytes and pixels a side.
    public static let maxImageBytes = 2 * 1024 * 1024
    public static let maxImagePixels = 2048
    /// Text must stand out this much from what it's on (WCAG AA for body text).
    public static let textContrast = 4.5

    /// Reads and checks the theme in `folder` (its `theme.json` and the images it names).
    public static func check(folder: URL) -> ThemeReport {
        var report = ThemeReport(tokens: .harbor)
        let manifest = folder.appendingPathComponent("theme.json")
        guard let size = (try? FileManager.default.attributesOfItem(atPath: manifest.path))?[.size] as? Int else {
            report.problems.append(.init(level: .error, message: "There's no theme.json in \(folder.lastPathComponent)."))
            return report
        }
        guard size <= ThemeFile.maxBytes else {
            report.problems.append(.init(level: .error, message: "theme.json is \(size / 1024) KB; a theme file can be 64 KB at most."))
            return report
        }
        let file: ThemeFile
        do {
            file = try JSONDecoder().decode(ThemeFile.self, from: Data(contentsOf: manifest))
        } catch {
            report.problems.append(.init(level: .error, message: "theme.json isn't a theme file: \(describe(error))"))
            return report
        }
        report.file = file
        resolve(file, into: &report)
        for (role, path) in file.images {
            switch image(path, in: folder) {
            case .success(let url): report.images[role] = url
            case .failure(let problem): report.problems.append(.init(level: .error, message: "\(role): \(problem.message)"))
            }
        }
        if file.material?.grain == nil { report.tokens.material.grain = false }
        return report
    }

    // MARK: Values

    private static func resolve(_ file: ThemeFile, into report: inout ThemeReport) {
        func problem(_ level: ThemeReport.Problem.Level, _ message: String) { report.problems.append(.init(level: level, message: message)) }
        if file.format != ThemeFile.currentFormat {
            problem(.error, "format \(file.format) isn't one this Sidefolk reads; it reads format \(ThemeFile.currentFormat).")
        }
        let idOK = !file.id.isEmpty && file.id.count <= 80 && file.id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "." || $0 == "-") }
        if !idOK { problem(.error, "id must be lowercase letters, digits, dots and dashes, like com.you.sunset (80 at most).") }
        let name = file.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.count > 40 { problem(.error, "name must be 1 to 40 characters.") }

        var t = ThemeTokens.harbor
        t.id = file.id
        t.name = name

        // Colours: every role in both appearances, Harbor's for any that's missing.
        var missing: [String] = []
        for appearance in ["light", "dark"] {
            let given = file.colors?[appearance] ?? [:]
            for unknown in given.keys where !ThemeTokens.Colors.roles.contains(where: { $0.name == unknown }) {
                problem(.warning, "colors.\(appearance).\(unknown) isn't a colour role; it's ignored.")
            }
            for role in ThemeTokens.Colors.roles {
                guard let text = given[role.name] else { missing.append("\(appearance).\(role.name)"); continue }
                guard let value = ThemeFile.colour(text) else {
                    problem(.error, "colors.\(appearance).\(role.name) “\(text)” isn't a colour like #1A2B3C.")
                    continue
                }
                if appearance == "light" { t.colors[keyPath: role.key].light = value } else { t.colors[keyPath: role.key].dark = value }
            }
        }
        if !missing.isEmpty { problem(.warning, "Harbor's colour is used for \(missing.joined(separator: ", ")).") }
        for row in contrastRows(t.colors) where !row.passes {
            problem(.error, "\(row.label) is \(String(format: "%.2f", min(row.light, row.dark))):1 in \(row.light < row.dark ? "light" : "dark"); text needs \(textContrast):1.")
        }
        for message in meaningProblems(t.colors) { problem(.error, message) }

        // Type, shape, motion, material, nook and layouts: from the app's own sets, within its limits.
        func pick<E: RawRepresentable & CaseIterable>(_ text: String?, _ key: String, _ fallback: E, level: ThemeReport.Problem.Level = .warning) -> E
            where E.RawValue == String {
            guard let text else { return fallback }
            if let value = E(rawValue: text) { return value }
            problem(level, "\(key) “\(text)” isn't one of \(E.allCases.map(\.rawValue).joined(separator: ", ")); \(fallback.rawValue) is used.")
            return fallback
        }
        let type = file.type
        t.type.display = pick(type?.display, "type.display", t.type.display)
        t.type.density = pick(type?.density, "type.density", t.type.density)
        if let text = type?.text, text != "system" { problem(.warning, "type.text is always the system face, for reading.") }
        if let exact = type?.exact, exact != "mono" { problem(.warning, "type.exact is always the monospaced face.") }
        if let scale = type?.scale {
            let range = ThemeTokens.Typography.scaleRange
            t.type.scale = min(max(scale, range.lowerBound), range.upperBound)
            if t.type.scale != scale { problem(.warning, "type.scale \(scale) is kept between \(range.lowerBound) and \(range.upperBound).") }
        }
        func radius(_ value: Double?, _ key: String, _ limits: ClosedRange<Double>, _ fallback: Double) -> Double {
            guard let value else { return fallback }
            let kept = min(max(value, limits.lowerBound), limits.upperBound)
            if kept != value { problem(.warning, "shape.\(key) \(value) is kept between \(limits.lowerBound) and \(limits.upperBound).") }
            return kept
        }
        t.radius.control = radius(file.shape?.control, "control", 4...999, t.radius.control)
        t.radius.card = radius(file.shape?.card, "card", 0...28, t.radius.card)
        t.radius.panel = radius(file.shape?.window, "window", 0...28, t.radius.panel)
        t.motion = pick(file.motion, "motion", t.motion)
        t.material.sidebar = pick(file.material?.sidebar, "material.sidebar", t.material.sidebar)
        t.material.grain = file.material?.grain != nil
        t.material.page = file.material?.page != nil || file.material?.pageDark != nil
        t.nook.style = pick(file.companion?.nook, "companion.nook", t.nook.style)
        if let suggests = file.companion?.suggests {
            if let choice = CompanionChoice(rawValue: suggests), !choice.isRetired {
                t.nook.suggests = choice
            } else {
                problem(.warning, "companion.suggests “\(suggests)” isn't a companion Sidefolk knows; nothing is suggested.")
            }
        }
        t.layout = layout(file.layout, problem)
        report.tokens = t
    }

    // MARK: Layout

    /// The theme's layout (D64): a preset, then its own choices, each from what the app draws, within limits.
    static func layout(_ section: ThemeFile.LayoutSection?, _ problem: (ThemeReport.Problem.Level, String) -> Void) -> ThemeLayout {
        var layout = ThemeLayout.desk
        guard let section else { return layout }
        if let name = section.preset {
            if let preset = ThemeLayout.presets[name] {
                layout = preset
            } else {
                problem(.warning, "layout.preset “\(name)” isn't one of \(ThemeLayout.presets.keys.sorted().joined(separator: ", ")); desk is used.")
            }
        }
        func pick<E: RawRepresentable>(_ text: String?, _ key: String, _ drawn: [E], _ fallback: E) -> E where E.RawValue == String {
            guard let text else { return fallback }
            if let value = E(rawValue: text), drawn.contains(where: { $0.rawValue == value.rawValue }) { return value }
            problem(.warning, "layout.\(key) “\(text)” isn't one of \(drawn.map(\.rawValue).joined(separator: ", ")); \(fallback.rawValue) is used.")
            return fallback
        }
        layout.navigation = pick(section.navigation, "navigation", ThemeLayout.drawnNavigation, layout.navigation)
        layout.nook = pick(section.nook, "nook", ThemeLayout.drawnNook, layout.nook)
        layout.icons = pick(section.icons, "icons", ThemeLayout.drawnIcons, layout.icons)
        layout.activity = pick(section.activity, "activity", ThemeLayout.drawnActivity, layout.activity)
        layout.editor = pick(section.editor, "editor", ThemeLayout.drawnEditor, layout.editor)
        guard let rows = section.today else { return layout }

        typealias Block = ThemeLayout.Block
        var seen: Set<Block.Kind> = []
        var today: [[ThemeLayout.Column]] = []
        if rows.count > ThemeLayout.maxRows { problem(.warning, "layout.today has \(rows.count) rows; the first \(ThemeLayout.maxRows) are used.") }
        for row in rows.prefix(ThemeLayout.maxRows) {
            if row.count > ThemeLayout.maxColumns {
                problem(.warning, "A row of layout.today has \(row.count) columns; the first \(ThemeLayout.maxColumns) are used.")
            }
            var columns: [ThemeLayout.Column] = []
            for column in row.prefix(ThemeLayout.maxColumns) {
                var blocks: [Block] = []
                for name in column.blocks {
                    guard let block = Self.block(name, problem) else { continue }
                    guard seen.insert(block.kind).inserted else {
                        problem(.warning, "layout.today has \(block.kind.rawValue) twice; the second is left out.")
                        continue
                    }
                    blocks.append(block)
                }
                guard !blocks.isEmpty else { continue }
                var width = column.width ?? 1
                if blocks.contains(where: { $0.kind == .companion && $0.style == "stage" }) { seen.insert(.queue) }
                if !(0.5...4).contains(width) {
                    problem(.warning, "A column's width \(width) is kept between 0.5 and 4.")
                    width = min(max(width, 0.5), 4)
                }
                columns.append(ThemeLayout.Column(width: width, page: column.page ?? false, blocks))
            }
            if !columns.isEmpty { today.append(columns) }
        }
        if today.isEmpty {
            problem(.warning, "layout.today has no block Sidefolk can draw; \(section.preset ?? "desk")'s is used.")
            return layout
        }
        // What needs you must always have a place: it holds Guard's questions.
        if !seen.contains(.queue) {
            problem(.warning, "layout.today has no queue, so what needs you would have nowhere to go; it's added at the top.")
            today.insert([ThemeLayout.Column([Block(.queue)])], at: seen.contains(.header) ? 1 : 0)
        }
        layout.today = today
        return layout
    }

    /// "kind" or "kind:style", from what the app draws.
    static func block(_ name: String, _ problem: (ThemeReport.Problem.Level, String) -> Void) -> ThemeLayout.Block? {
        if name.hasPrefix("extension:") {
            problem(.warning, "“\(name)”: blocks from extensions aren't supported yet; it's left out.")
            return nil
        }
        let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
        guard let kind = parts.first.flatMap(ThemeLayout.Block.Kind.init(rawValue:)), ThemeLayout.Block.Kind.available.contains(kind) else {
            problem(.warning, "“\(name)” isn't one of \(ThemeLayout.Block.Kind.available.map(\.rawValue).joined(separator: ", ")); it's left out.")
            return nil
        }
        guard parts.count == 2 else { return ThemeLayout.Block(kind) }
        if kind.styles.contains(parts[1]) { return ThemeLayout.Block(kind, parts[1]) }
        problem(.warning, "“\(name)”: \(kind.rawValue) comes as \(kind.styles.joined(separator: ", ")); \(kind.styles[0]) is used.")
        return ThemeLayout.Block(kind)
    }

    // MARK: Contrast

    public struct ContrastRow: Sendable {
        public var label: String
        public var light: Double
        public var dark: Double
        public var passes: Bool { min(light, dark) >= ThemeCheck.textContrast }
    }

    /// Every pair of text and what it's drawn on that the app uses.
    public static func contrastRows(_ c: ThemeTokens.Colors) -> [ContrastRow] {
        var rows: [ContrastRow] = []
        func add(_ label: String, _ text: ThemeTokens.Pair, on back: ThemeTokens.Pair) {
            rows.append(ContrastRow(label: label, light: contrast(text.light, back.light), dark: contrast(text.dark, back.dark)))
        }
        for (name, text) in [("ink", c.ink), ("inkMuted", c.inkMuted), ("inkFaint", c.inkFaint), ("link", c.link), ("danger", c.danger),
                             ("warning", c.warning)] {
            for (surface, back) in [("surface", c.surface), ("surfaceSunken", c.surfaceSunken), ("surfaceRaised", c.surfaceRaised)] {
                add("\(name) on \(surface)", text, on: back)
            }
        }
        add("ink on accentSoft", c.ink, on: c.accentSoft)
        add("onAccent on accent", c.onAccent, on: c.accent)
        add("onDanger on danger", c.onDanger, on: c.danger)
        add("ink on warningSoft", c.ink, on: c.warningSoft)
        add("onWarning on warning", c.onWarning, on: c.warning)
        return rows
    }

    // MARK: Meaning

    /// The hues each status role must keep, in degrees, so a theme can't paint a win red or an error green
    /// (StatusTone). Wide enough for rust reds, ochres and sage or teal greens.
    static var meaningHues: [(role: String, key: KeyPath<ThemeTokens.Colors, ThemeTokens.Pair>, looks: String, hues: [ClosedRange<Double>])] { [
        ("danger", \.danger, "red", [0...30, 330...360]),
        ("warning", \.warning, "amber", [30...65]),
        ("success", \.success, "green", [70...200]),
    ] }

    /// Each status role whose colour doesn't look like what it means, in plain words.
    public static func meaningProblems(_ c: ThemeTokens.Colors) -> [String] {
        var problems: [String] = []
        for rule in meaningHues {
            let pair = c[keyPath: rule.key]
            for (appearance, value) in [("light", pair.light), ("dark", pair.dark)] {
                let (hue, saturation) = hueAndSaturation(value)
                if saturation < 0.1 || !rule.hues.contains(where: { $0.contains(hue) }) {
                    problems.append("\(rule.role) in \(appearance) must look \(rule.looks): it means \(meaning(rule.role)) everywhere in Sidefolk.")
                }
            }
        }
        return problems
    }

    private static func meaning(_ role: String) -> String {
        switch role {
        case "danger": "an error or a real risk"
        case "warning": "something waiting or needing a look"
        default: "done, allowed or won"
        }
    }

    /// The HSL hue (0–360) and saturation (0–1) of a 0xRRGGBB colour.
    static func hueAndSaturation(_ hex: UInt32) -> (hue: Double, saturation: Double) {
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        let hi = max(r, g, b), lo = min(r, g, b), d = hi - lo
        guard d > 0 else { return (0, 0) }
        let l = (hi + lo) / 2
        let saturation = d / (1 - abs(2 * l - 1))
        var hue: Double
        if hi == r { hue = ((g - b) / d).truncatingRemainder(dividingBy: 6) } else if hi == g { hue = (b - r) / d + 2 } else { hue = (r - g) / d + 4 }
        hue *= 60
        return (hue < 0 ? hue + 360 : hue, saturation)
    }

    /// WCAG 2 contrast ratio between two 0xRRGGBB colours.
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [16, 8, 0].map { Double((hex >> $0) & 0xFF) / 255 }
                .map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    // MARK: Images

    /// A PNG inside the folder, small enough, that ImageIO reads as an image.
    static func image(_ path: String, in folder: URL) -> Result<URL, ThemeReport.Problem> {
        func no(_ message: String) -> Result<URL, ThemeReport.Problem> { .failure(.init(level: .error, message: message)) }
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), path.lowercased().hasSuffix(".png") else {
            return no("“\(path)” must be a .png inside the theme's folder.")
        }
        let url = folder.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(folder.standardizedFileURL.path + "/") else { return no("“\(path)” is outside the theme's folder.") }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int else { return no("“\(path)” isn't there.") }
        guard size <= maxImageBytes else { return no("“\(path)” is \(size / 1024) KB; images can be 2 MB at most.") }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int else {
            return no("“\(path)” isn't a PNG image.")
        }
        guard max(width, height) <= maxImagePixels else { return no("“\(path)” is \(width)×\(height); images can be 2048 pixels a side at most.") }
        return .success(url)
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }
        switch error {
        case .keyNotFound(let key, _): return "“\(key.stringValue)” is missing."
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            let at = context.codingPath.map(\.stringValue).joined(separator: ".")
            return at.isEmpty ? context.debugDescription : "\(at): \(context.debugDescription)"
        @unknown default: return error.localizedDescription
        }
    }
}
