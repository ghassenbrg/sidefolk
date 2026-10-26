import Foundation
import SidefolkCore
import Testing

/// The string catalog the app is built with. Tests run without it (their runner has no translations),
/// so a count of one reads as its key there ("1 open tasks"); these check what the app says instead.
@Suite struct CatalogTests {
    /// The catalog's `strings`, read once. Immutable after loading.
    struct Catalog: @unchecked Sendable {
        typealias Entry = [String: Any]
        let strings: [String: Entry]

        init() {
            let url = ExtFixtures.repoRoot.appendingPathComponent("Resources/Localization/Localizable.xcstrings")
            let json = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any]
            strings = json?["strings"] as? [String: Entry] ?? [:]
        }

        /// The English plural forms of `key`, if it has any.
        func english(_ key: String) -> (one: String, other: String)? {
            let en = (strings[key]?["localizations"] as? Entry)?["en"] as? Entry
            let plural = (en?["variations"] as? Entry)?["plural"] as? [String: Entry]
            func value(_ form: String) -> String? { (plural?[form]?["stringUnit"] as? Entry)?["value"] as? String }
            guard let one = value("one"), let other = value("other") else { return nil }
            return (one, other)
        }

        /// What the app shows for `key` with this count (and any text arguments after it).
        func shown(_ key: String, _ count: Int, _ texts: String...) -> String? {
            guard let forms = english(key) else { return nil }
            let args: [any CVarArg] = [count] + texts
            return String(format: count == 1 ? forms.one : forms.other, arguments: args)
        }
    }

    static let catalog = Catalog()

    static func placeholders(_ s: String) -> [String] {
        s.matches(of: /%(?:\d+\$)?(lld|@|d)/).map { String($0.output.1) }
    }

    @Test func theCatalogLoads() {
        #expect(Self.catalog.strings.count > 500)
        #expect(Self.catalog.strings["Today"] != nil)
    }

    @Test func everyPluralKeepsItsPlaceholders() {
        let plurals = Self.catalog.strings.keys.compactMap { key in Self.catalog.english(key).map { (key, $0) } }
        #expect(plurals.count >= 20)
        for (key, forms) in plurals {
            #expect(Self.placeholders(forms.one) == Self.placeholders(key), "\(key)")
            #expect(Self.placeholders(forms.other) == Self.placeholders(key), "\(key)")
            // The form is chosen by the first argument, so the count must come first.
            #expect(Self.placeholders(key).first == "lld", "\(key)")
        }
    }

    /// The app removes "Nothing was changed." from the end of a message when something did change, so
    /// every translation must end such messages with its own translation of that sentence.
    @Test func nothingWasChangedReadsTheSameInEveryLanguage() {
        let c = Self.catalog
        func value(_ key: String, _ language: String) -> String? {
            let unit = ((c.strings[key]?["localizations"] as? Catalog.Entry)?[language] as? Catalog.Entry)?["stringUnit"] as? Catalog.Entry
            return unit?["value"] as? String
        }
        let languages = Set(c.strings.values.flatMap { (($0["localizations"] as? Catalog.Entry) ?? [:]).keys }).subtracting(["en"])
        for language in languages {
            guard let sentence = value("Nothing was changed.", language) else { continue }
            for key in c.strings.keys where key.hasSuffix(" Nothing was changed.") {
                guard let translated = value(key, language) else { continue }
                #expect(translated.hasSuffix(sentence), "\(language): “\(key)”")
            }
        }
    }

    /// Chinese and Japanese put no space between sentences, so the ending goes without one too.
    @Test func nothingWasChangedGoesWithOrWithoutASpace() {
        #expect(Wording.droppingNothingChanged(from: "Stopped. Nothing was changed.") == "Stopped.")
        #expect(Wording.droppingNothingChanged(from: "止まりました。Nothing was changed.") == "止まりました。")
        #expect(Wording.droppingNothingChanged(from: "Saved it.") == "Saved it.")
    }

    @Test func oneIsSingularInEnglish() {
        let c = Self.catalog
        #expect(c.shown("%lld open tasks", 1) == "1 open task")
        #expect(c.shown("%lld open tasks", 2) == "2 open tasks")
        #expect(c.shown("%lld watchers on duty", 1) == "1 watcher on duty")
        #expect(c.shown("Good morning · %lld reminders today", 1) == "Good morning · 1 reminder today")
        #expect(c.shown("Move %lld items to %@", 1, "~/Desktop") == "Move 1 item to ~/Desktop")
        #expect(c.shown("Move %lld items to %@", 3, "~/Desktop") == "Move 3 items to ~/Desktop")
        #expect(c.shown("PDF, %lld pages", 1) == "PDF, 1 page")
        #expect(c.shown("%lld matches for “%@”", 1, "tea") == "1 match for “tea”")
        #expect(c.shown("It's been %lld days. I can start again if you still want it.", 1)
            == "It's been 1 day. I can start again if you still want it.")
        // The app's own counts.
        #expect(c.shown("%lld things need you.", 1) == "1 thing needs you.")
        #expect(c.shown("Watching %lld things", 1) == "Watching 1 thing")
        #expect(c.shown("gone in %lld days", 1) == "gone in 1 day")
        #expect(c.shown("Running with %lld models.", 1) == "Running with 1 model.")
        #expect(c.shown("%lld items in it move to the Trash for 30 days. Restored items go to the Inbox.", 2)
            == "2 items in it move to the Trash for 30 days. Restored items go to the Inbox.")
    }

    /// The app's windows, menus and Settings are collected too (their components take catalog keys),
    /// not only what the core builds.
    @Test func theAppsWordsAreInTheCatalog() {
        let s = Self.catalog.strings
        for key in ["Open at login", "Privacy & Permissions", "Quit Sidefolk", "New collection", "Nothing needs you right now.",
                    "Allow notifications", "Thinking…", "%@ needs you in %@", "Ideas & notes", "%@ is listening"] {
            #expect(s[key] != nil, "\(key)")
        }
    }
}
