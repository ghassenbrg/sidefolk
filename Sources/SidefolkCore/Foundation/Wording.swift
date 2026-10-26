import Foundation

/// Helpers for text people read (DECISIONS D28). Its words come from the string catalog through
/// `String(localized:)`; text a model reads stays English and uses `ToolFormat` instead.
public enum Wording {
    /// For lists and sizes in such text, in the same language as its words: the app's language in the
    /// app, English in tests (their runner has no translations), whatever the Mac is set to.
    public static var locale: Locale {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: language == "Base" ? "en" : language)
    }

    /// "a, b, c", or "a, b, c and 2 more" past `max`.
    public static func names(_ names: [String], max: Int = 3) -> String {
        guard names.count > max else { return list(names) }
        return String(localized: "\(list(Array(names.prefix(max)))) and \(names.count - max) more")
    }

    /// "a, b, c" with the language's own separators.
    public static func list(_ items: [String]) -> String {
        items.formatted(.list(type: .and, width: .narrow).locale(locale))
    }

    /// "123 KB".
    public static func bytes(_ count: Int64) -> String {
        count.formatted(ByteCountFormatStyle(style: .file, locale: locale))
    }
}
