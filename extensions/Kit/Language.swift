import Foundation
import Synchronization

/// The person's language, and the extension's own words in it (Sidefolk D76, docs/EXTENSIONS.md › Languages).
///
/// Sidefolk sends `language` with every tool call, watcher check, page and palette request; the Kit keeps it for the
/// request it answers, and for background work after (the last one heard). Words are looked up by their English in
/// `strings/<language>.json` beside the program (`text`), so the code reads in English and a missing translation shows
/// English:
///
/// ```swift
/// L("Battery low")                                            // "Batterie faible"
/// L("{app} is using {cpu}", ["app": name, "cpu": Format.percent(0.4)])
/// L(one: "{count} app", other: "{count} apps", count: n)     // the language's own plural forms
/// ```
public enum Language {
    private struct State {
        var code = "en"
        var tables: [String: [String: Entry]]?
    }

    enum Entry: Equatable {
        case plain(String)
        case plural([String: String])
    }

    private static let state = Mutex(State())
    /// A language and tables for one piece of work only (`with`), so tests running side by side don't change each other's.
    @TaskLocal private static var scoped: (code: String, tables: [String: [String: Entry]]?)?

    /// The language of the request being answered: `en`, `fr`, `pt-BR`, `zh-Hans`, `ar`… English until Sidefolk says.
    public static var code: String { scoped?.code ?? state.withLock { $0.code } }

    /// For Foundation's formatters (`Format` uses it): the language alone, as Sidefolk's own words are formatted.
    public static var locale: Locale { Locale(identifier: code) }

    /// Whether the language reads right to left. Sidefolk keeps numbers, sizes and paths in extension text the right way
    /// round itself (it removes any direction marks an extension sends), so this is for word order, not for marks.
    public static var rightToLeft: Bool { Locale.Language(identifier: code).characterDirection == .rightToLeft }

    /// Sets the language for what follows. The Kit calls it with each request's `language`, made one of Sidefolk's ten
    /// as `Localized` makes it (`pt` is `pt-BR`, any Chinese `zh-Hans`, a language it doesn't speak English).
    public static func use(_ code: String?) {
        guard let code, code.range(of: #"^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$"#, options: .regularExpression) != nil else { return }
        state.withLock { $0.code = Localized.normalized(code) }
    }

    /// Runs `work` in `code`, with the tables in `strings` (an extension's `strings/` folder) when given, without changing
    /// the language of anything else: for tests, which run side by side.
    public static func with<T>(_ code: String, strings: String? = nil, _ work: () throws -> T) rethrows -> T {
        try $scoped.withValue((code, strings.map(read)), operation: work)
    }

    /// The text for `key` in the current language, nil when the extension's tables don't have it there.
    static func entry(_ key: String) -> Entry? {
        let (code, loaded) = state.withLock { ($0.code, $0.tables) }
        let tables = scoped?.tables ?? loaded ?? {
            let found = read(defaultFolder)
            state.withLock { $0.tables = $0.tables ?? found }
            return found
        }()
        return tables[Localized.normalized(scoped?.code ?? code)]?[key]
    }

    /// A plain word through the Kit's `Localized` (the same lookup Playtime's in-code tables use): the extension's
    /// tables as `Localized` takes them, its English when this language lacks the word, nil when neither has it.
    static func word(_ key: String) -> String? {
        let (code, loaded) = state.withLock { ($0.code, $0.tables) }
        let tables = scoped?.tables ?? loaded ?? [:]
        let plain = tables.mapValues { $0.compactMapValues { if case .plain(let s) = $0 { s } else { nil } } }
        let found = Localized(scoped?.code ?? code, plain)[key]
        return found == key && plain["en"]?[key] == nil && plain[Localized.normalized(scoped?.code ?? code)]?[key] == nil ? nil : found
    }

    /// `strings/` beside `bin/`, where Sidefolk installs the program (`<folder>/bin/<program>`).
    private static var defaultFolder: String {
        let program = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        return program.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("strings").path
    }

    private static func read(_ folder: String) -> [String: [String: Entry]] {
        var out: [String: [String: Entry]] = [:]
        for file in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] where file.hasSuffix(".json") {
            guard let data = FileManager.default.contents(atPath: folder + "/" + file),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = object["text"] as? [String: Any] else { continue }
            out[String(file.dropLast(5))] = text.compactMapValues { value in
                if let s = value as? String { return .plain(s) }
                if let forms = value as? [String: String], forms["other"] != nil { return .plural(forms) }
                return nil
            }
        }
        return out
    }

    /// CLDR's plural form of `n` for a language (the whole numbers rules: what counts of things need).
    static func form(_ n: Int, _ code: String) -> String {
        let n = abs(n), language = String(code.prefix { $0 != "-" })
        switch language {
        case "ar":
            switch n % 100 {
            case _ where n == 0: return "zero"
            case _ where n == 1: return "one"
            case _ where n == 2: return "two"
            case 3...10: return "few"
            case 11...99: return "many"
            default: return "other"
            }
        case "ja", "ko", "zh": return "other"
        case "fr", "pt": return n <= 1 ? "one" : (n != 0 && n % 1_000_000 == 0 ? "many" : "other")
        case "es", "it": return n == 1 ? "one" : (n != 0 && n % 1_000_000 == 0 ? "many" : "other")
        default: return n == 1 ? "one" : "other"
        }
    }
}

/// `key` (its English) in the person's language, with `{name}` placeholders filled from `values`: a string as it is,
/// a whole number in the language's digits. Format other numbers, sizes and dates with `Format` first.
public func L(_ key: String, _ values: [String: Any] = [:]) -> String {
    let text: String
    switch Language.entry(key) {
    case .plural(let forms)?: text = forms["other"] ?? key
    default: text = Language.word(key) ?? KitWords.text(key, Language.code) ?? key
    }
    return fill(text, values)
}

/// A count of something, in the language's plural form: `one` and `other` are the English (`other` is the key the
/// translations use), `{count}` the number in the language's digits.
public func L(one: String, other: String, count: Int, _ values: [String: Any] = [:]) -> String {
    let form = Language.form(count, Language.code)
    let text: String
    switch Language.entry(other) {
    case .plural(let forms)?: text = forms[form] ?? forms["other"] ?? other
    case .plain(let s)?: text = s
    case nil: text = Language.form(count, "en") == "one" ? one : other
    }
    var all = values
    all["count"] = count
    return fill(text, all)
}

private func fill(_ text: String, _ values: [String: Any]) -> String {
    guard text.contains("{") else { return text }
    var out = text
    for (name, value) in values {
        let shown: String
        switch value {
        case let n as Int: shown = Format.integer(n)
        case let n as Int64: shown = Format.integer(Int(n))
        case let s as String: shown = s
        default: shown = String(describing: value)
        }
        out = out.replacingOccurrences(of: "{\(name)}", with: shown)
    }
    return out
}

/// Numbers, sizes, durations and dates in the person's language, as Sidefolk formats its own: Foundation's formatters
/// with `Language.locale`, times on a 24-hour clock.
public enum Format {
    private static var locale: Locale { Language.locale }

    public static func integer(_ n: Int) -> String { n.formatted(.number.locale(locale)) }

    /// At most `digits` decimals, none when they'd be zeros.
    public static func number(_ x: Double, digits: Int = 1) -> String {
        x.formatted(.number.precision(.fractionLength(0...max(0, digits))).locale(locale))
    }

    /// `fraction` 0–1 as a percentage: "42 %" in French, "٤٢٪" in Arabic.
    public static func percent(_ fraction: Double, digits: Int = 0) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0...max(0, digits))).locale(locale))
    }

    /// A number already in percent (42 for 42 %).
    public static func percent(points: Double, digits: Int = 0) -> String { percent(points / 100, digits: digits) }

    /// A file or disk size: "1.2 GB", "1,2 Go".
    public static func bytes(_ n: Int64, style: ByteCountFormatStyle.Style = .file) -> String {
        n.formatted(.byteCount(style: style, spellsOutZero: false).locale(locale))
    }

    /// "1 h 5 min", "3 min", "45 s": the largest two units, abbreviated.
    public static func duration(_ seconds: TimeInterval, units: Set<Duration.UnitsFormatStyle.Unit> = [.days, .hours, .minutes, .seconds],
                                width: Duration.UnitsFormatStyle.UnitWidth = .abbreviated) -> String {
        Duration.seconds(max(0, seconds.rounded())).formatted(.units(allowed: units, width: width, maximumUnitCount: 2).locale(locale))
    }

    /// "18:05": always 24 hours, as Sidefolk writes times.
    public static func time(_ date: Date, timeZone: TimeZone = .current) -> String { pattern("HHmm", date, timeZone) }

    /// "31 Oct", "10月31日"; with `year`, "31 Oct 2026"; with `weekday`, "Fri 31 Oct".
    public static func date(_ date: Date, year: Bool = false, weekday: Bool = false, timeZone: TimeZone = .current) -> String {
        pattern((weekday ? "EEE" : "") + "dMMM" + (year ? "y" : ""), date, timeZone)
    }

    /// "Fri 31 Oct, 18:05" in the language's order, 24 hours.
    public static func dateTime(_ date: Date, timeZone: TimeZone = .current) -> String { pattern("EEEdMMMHHmm", date, timeZone) }

    /// A date in the language's own order for a template's fields; `HH` keeps 24 hours wherever the language would use 12.
    private static func pattern(_ template: String, _ date: Date, _ timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale)
        return f.string(from: date)
    }

    /// "5 minutes ago", "in 2 hours", "yesterday".
    public static func relative(_ date: Date, to now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.dateTimeStyle = .named
        return f.localizedString(for: date, relativeTo: now)
    }

    /// Sentences one after another as the language writes them: with a space, or with none in Japanese and Chinese.
    public static func sentences(_ parts: [String]) -> String {
        let tight = ["ja", "zh"].contains(String(Language.code.prefix { $0 != "-" }))
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: tight ? "" : " ")
    }

    /// "a, b and c" in the language's own words.
    public static func list(_ items: [String], or: Bool = false) -> String {
        items.formatted(.list(type: or ? .or : .and, width: .standard).locale(locale))
    }
}
