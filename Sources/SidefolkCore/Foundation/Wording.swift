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

    /// Sentences joined as the language joins them: with a space, or with nothing in Chinese and Japanese.
    public static func sentences(_ parts: [String]) -> String {
        let tight = ["zh", "ja"].contains(locale.language.languageCode?.identifier ?? "")
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: tight ? "" : " ")
    }

    /// `text` without the "Nothing was changed." that ends many errors, in the app's language or in
    /// English, for when something did change. No space is needed before it: Chinese and Japanese have none.
    public static func droppingNothingChanged(from text: String) -> String {
        for ending in [String(localized: "Nothing was changed."), "Nothing was changed."] where text.hasSuffix(ending) {
            return String(text.dropLast(ending.count)).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    /// "123 KB".
    public static func bytes(_ count: Int64) -> String {
        count.formatted(ByteCountFormatStyle(style: .file, locale: locale))
    }
}
