import Foundation
import SidefolkExtensionKit
import Testing
@testable import SidefolkCore

/// Sidefolk's own extensions speak all ten languages (D76): every word people see, in every language, the program's
/// sentences included; and they answer in the person's language when Sidefolk says it.
@Suite(.serialized) struct ExtensionLanguagesTests {
    /// Playtime localizes itself on its own branch (team/play); hello-folk is a sample for developers.
    static let folders = (ExtFixtures.builtInFolders + ExtFixtures.addonFolders).filter { $0 != "playtime" }
    static let languages = ExtensionStrings.languages.filter { $0 != "en" }

    /// `L("…")` and `L(one: "…", other: "…")` in a program's sources, as scripts/extension-strings.py reads them.
    static func keys(in sources: URL) -> Set<String> {
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        var keys = Set<String>()
        for file in files {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            for m in text.matches(of: /\bL\(\s*one:\s*"(?:[^"\\\n]|\\.)*"\s*,\s*other:\s*"((?:[^"\\\n]|\\.)*)"/) { keys.insert(unescape(String(m.1))) }
            for m in text.matches(of: /\bL\(\s*"((?:[^"\\\n]|\\.)*)"/) { keys.insert(unescape(String(m.1))) }
        }
        return keys
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: #"\""#, with: "\"").replacingOccurrences(of: #"\n"#, with: "\n").replacingOccurrences(of: #"\\"#, with: "\\")
    }

    @Test(arguments: folders) func everyWordInEveryLanguage(_ folder: String) throws {
        let paths = SidefolkPaths(home: try ExtFixtures.tempDir("languages"))
        let report = ManifestValidator(paths: paths).validate(folder: ExtFixtures.builtIn(folder))
        #expect(report.errors.isEmpty, "\(folder): \(report.errors)")
        let m = try #require(report.manifest)
        let strings = try #require(report.strings, "\(folder) has no strings/")
        let english = try #require(strings.tables["en"], "\(folder) has no strings/en.json")
        // The English list is the program's own: every L(…) in its sources, and nothing it no longer says.
        let used = Self.keys(in: ExtFixtures.source(folder).appendingPathComponent("Sources"))
        #expect(Set(english.text.keys) == used, "\(folder): run scripts/extension-strings.py sync; missing \(used.subtracting(english.text.keys).sorted().prefix(5)), unused \(Set(english.text.keys).subtracting(used).sorted().prefix(5))")
        for language in Self.languages {
            let w = try #require(strings.tables[language], "\(folder) has no \(language)")
            let at = "\(folder) \(language)"
            #expect(w.name != nil, "\(at) name")
            #expect((w.tagline != nil) == (m.tagline != nil), "\(at) tagline")
            #expect((w.description != nil) == (m.description != nil), "\(at) description")
            #expect((w.networkPurpose != nil) == (m.permissions.networkPurpose != nil), "\(at) network purpose")
            #expect(Set(w.tools.keys) == Set(m.tools.filter { $0.value.title != nil }.keys), "\(at) tool titles")
            for (name, watcher) in m.watchers {
                #expect(w.watchers[name]?.title != nil, "\(at) watcher \(name)")
                #expect((w.watchers[name]?.description != nil) == (watcher.description != nil), "\(at) watcher \(name) description")
            }
            #expect(Set(w.pages.keys) == Set(m.pages.keys), "\(at) pages")
            for (name, palette) in m.palettes {
                #expect(w.palettes[name]?.title != nil && (w.palettes[name]?.placeholder != nil) == (palette.placeholder != nil), "\(at) palette \(name)")
            }
            // Every text, its placeholders kept (the validator refused the file otherwise), nothing left empty.
            let missing = Set(english.text.keys).subtracting(w.text.keys)
            #expect(missing.isEmpty, "\(at): \(missing.sorted().prefix(5))")
        }
    }

    /// Sidefolk says the person's language with the call, and the program answers in it.
    @Test func builtInsAnswerInThePersonsLanguage() async throws {
        let h = try HostEnv { $0.language = { "fr" } }
        _ = try await h.host.install(from: ExtFixtures.builtIn("world-clock"))
        let now = try #require(await h.call("ext.world-clock.current_time", ["places": ["UTC", "Narnia"]]).okText)
        #expect(now.hasPrefix("Il est ") && now.contains("en UTC (UTC+0)") && now.contains("Je ne sais pas où se trouve « Narnia »"), "\(now)")
        let info = try #require(await h.host.info(id: "dev.sidefolk.world-clock"))
        #expect(info.name == "Horloge mondiale" && info.tools.contains { $0.title == "L’heure dans le monde" }, "\(info.name) \(info.tools.map(\.title))")
        await h.host.shutdown()

        let ar = try HostEnv { $0.language = { "ar" } }
        _ = try await ar.host.install(from: ExtFixtures.builtIn("calculator"))
        let days = try #require(await ar.call("ext.calculator.date_math", ["date": "2026-12-24", "to": "2027-01-04"]).okText)
        #expect(days.contains("11 يومًا") && days.contains("منها 7 أيام عمل"), "\(days)")
        await ar.host.shutdown()
    }

    /// The Kit's `L` and `Format` (extensions/Kit/Language.swift), as an extension's program uses them.
    @Test func theKitFindsWordsPluralsAndFormats() throws {
        let folder = try ExtFixtures.tempDir("kit-strings")
        try Data(#"{"text": {"Hello {name}": "Bonjour {name}", "{count} apps": {"one": "{count} app", "other": "{count} apps"}}}"#.utf8)
            .write(to: folder.appendingPathComponent("fr.json"))
        try Data(#"{"text": {"{count} apps": {"zero": "لا تطبيقات", "one": "تطبيق واحد", "two": "تطبيقان", "few": "{count} تطبيقات", "many": "{count} تطبيقًا", "other": "{count} تطبيق"}}}"#.utf8)
            .write(to: folder.appendingPathComponent("ar.json"))
        Language.load(from: folder.path)
        defer {
            Language.use("en")
            Language.load(from: "/nonexistent")
        }
        Language.use("fr")
        #expect(L("Hello {name}", ["name": "Ada"]) == "Bonjour Ada")
        #expect(L(one: "{count} app", other: "{count} apps", count: 0) == "0 app", "French says one for 0")
        #expect(L(one: "{count} app", other: "{count} apps", count: 1234) == "1\u{202F}234 apps", "French digits group with a narrow space")
        #expect(L("Not translated") == "Not translated", "English when a language lacks it")
        #expect(L("“{key}” is missing.", ["key": "x"]) == "« x » manque.", "the Kit's own words")
        #expect(Format.percent(0.42) == "42\u{00A0}%" && Format.time(Date(timeIntervalSince1970: 61_200), timeZone: TimeZone(identifier: "UTC")!) == "17:00")
        Language.use("ar")
        #expect([0, 1, 2, 5, 11, 100].map { L(one: "{count} app", other: "{count} apps", count: $0) }
                == ["لا تطبيقات", "تطبيق واحد", "تطبيقان", "5 تطبيقات", "11 تطبيقًا", "100 تطبيق"])
        Language.use("pt-BR")
        #expect(L("Hello {name}", ["name": "Ada"]) == "Hello Ada")
        Language.use("not a language!")
        #expect(Language.code == "pt-BR", "a code that isn't one is ignored")
        Language.use("en")
        #expect(L(one: "{count} app", other: "{count} apps", count: 1) == "1 app" && Format.time(Date(timeIntervalSince1970: 61_200), timeZone: TimeZone(identifier: "UTC")!) == "17:00",
                "English needs no table, and keeps 24 hours")
    }
}
