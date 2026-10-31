import Foundation

/// Words in the person's language for an extension that speaks it (D75). Sidefolk passes `language` with every page,
/// game and palette request (`en`, `fr`, `es`, `de`, `it`, `pt-BR`, `ja`, `ko`, `zh-Hans`, `ar`); the extension keeps a
/// table of its words per language, English first, and asks for each by key. A word missing in a language falls back
/// to English, so a half-done table still shows everything.
///
/// ```swift
/// let words = Localized(request.language, [
///     "en": ["start": "Start", "of": "%1$@ of %2$@"],
///     "fr": ["start": "Commencer", "of": "%1$@ sur %2$@"],
/// ])
/// words["start"]                                  // "Commencer"
/// words("of", words.number(3), words.number(10))   // "3 sur 10", numbers as the language writes them
/// ```
public struct Localized {
    /// The languages Sidefolk ships in.
    public static let languages = ["en", "fr", "es", "de", "it", "pt-BR", "ja", "ko", "zh-Hans", "ar"]

    /// One of `languages`.
    public let language: String
    private let words: [String: String]
    private let english: [String: String]

    public init(_ language: String?, _ tables: [String: [String: String]]) {
        self.language = Self.normalized(language)
        english = tables["en"] ?? [:]
        words = tables[self.language] ?? english
    }

    /// `fr-CA` is `fr`, `pt` is `pt-BR`, `zh`, `zh-CN` and `zh-Hans-CN` are `zh-Hans`; anything else is English.
    public static func normalized(_ code: String?) -> String {
        guard let code = code?.replacingOccurrences(of: "_", with: "-"), !code.isEmpty else { return "en" }
        if languages.contains(code) { return code }
        let lower = code.lowercased()
        if lower.hasPrefix("pt") { return "pt-BR" }
        if lower.hasPrefix("zh") { return "zh-Hans" }
        let base = String(lower.prefix { $0 != "-" })
        return languages.contains(base) ? base : "en"
    }

    /// The word for `key`, in English when this language lacks it, or the key itself when English does too.
    public subscript(_ key: String) -> String { words[key] ?? english[key] ?? key }

    /// The word for `key` with its `%@` (or numbered `%1$@`) filled in. Pass numbers through `number(_:)`: formatting
    /// with a locale would wrap each piece in invisible direction marks, which Sidefolk removes from what it shows.
    public func callAsFunction(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: self[key], arguments: arguments)
    }

    public var locale: Locale { Locale(identifier: language) }

    /// A whole number as this language writes it ("١٢" in Arabic).
    public func number(_ n: Int) -> String { n.formatted(.number.grouping(.never).locale(locale)) }

    /// Right to left (Arabic): Sidefolk lays the panel out that way; text that joins pieces may need to know.
    public var rightToLeft: Bool { language == "ar" }
}
