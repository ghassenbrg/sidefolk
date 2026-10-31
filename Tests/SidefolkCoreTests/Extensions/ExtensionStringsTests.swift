import Foundation
import Testing
@testable import SidefolkCore

/// An extension's words in other languages (D76): what the validator accepts in `strings/`, which language is shown,
/// and that a manifest written before them is read as before.
@Suite final class ExtensionStringsTests {
    let root: URL
    let paths: SidefolkPaths
    static let resolver = InterpreterResolver { name in ["python3", "sh", "node"].contains(name) ? ["/bin/sh"] : [] }

    init() throws {
        root = try ExtFixtures.tempDir("strings")
        paths = SidefolkPaths(home: root.appendingPathComponent("home", isDirectory: true))
    }

    deinit { ExtensionFiles.removeTree(root.path) }

    static let manifest = ExtFixtures.manifest(tools: ["echo": ["title": "Echo", "risk": "low"]], extra: [
        "tagline": "Says it back", "description": "Says back what it hears.",
        "watchers": ["done": ["title": "Done", "description": "When it's done."]],
        "pages": ["main": ["title": "Sample"]],
        "palettes": ["list": ["title": "Sample list", "placeholder": "Search"]],
    ])

    static let english = #"{"text": {"Hello": "Hello", "{count} apps": {"one": "{count} app", "other": "{count} apps"}, "Hi {name}": "Hi {name}"}}"#

    func validate(_ files: [String: String], manifest: JSONValue = ExtensionStringsTests.manifest, folder: String = "dev.test.sample") throws -> ValidationReport {
        let dir = try ExtFixtures.makeExtension(at: root.appendingPathComponent(UUID().uuidString).appendingPathComponent(folder, isDirectory: true),
                                                manifest: manifest, files: files.merging(["server.py": "print()"]) { a, _ in a })
        return ManifestValidator(paths: paths, resolver: Self.resolver).validate(folder: dir)
    }

    func fields(_ files: [String: String]) throws -> [String] { try validate(files).errors.map(\.field) }

    @Test func aCompleteTranslationIsValid() throws {
        let french = #"""
        {"name": "Exemple", "tagline": "Le répète", "description": "Répète ce qu’il entend.",
         "tools": {"echo": {"title": "Écho"}}, "watchers": {"done": {"title": "Fini", "description": "Quand c’est fini."}},
         "pages": {"main": {"title": "Exemple"}}, "palettes": {"list": {"title": "Liste", "placeholder": "Rechercher"}},
         "text": {"Hello": "Bonjour", "{count} apps": {"one": "{count} app", "other": "{count} apps"}, "Hi {name}": "Salut {name}"}}
        """#
        let arabic = #"{"name": "مثال", "text": {"{count} apps": {"zero": "لا تطبيقات", "one": "تطبيق واحد", "two": "تطبيقان", "few": "{count} تطبيقات", "many": "{count} تطبيقًا", "other": "{count} تطبيق"}}}"#
        let report = try validate(["strings/en.json": Self.english, "strings/fr.json": french, "strings/ar.json": arabic])
        #expect(report.isValid, "\(report.errors)")
        #expect(report.strings?.words(for: "fr")?.name == "Exemple")
        #expect(report.strings?.words(for: "fr")?.tools["echo"] == "Écho")
        #expect(report.strings?.words(for: "fr")?.text["Hi {name}"] == .plain("Salut {name}"))
        #expect(report.text.contains("Languages: en, fr, ar"))
        // The install sheet's words, in the person's language, with the manifest's for what isn't translated.
        let shown = report.shownWords(language: "ar", official: false)
        #expect(shown?.name == "مثال" && shown?.description == "Says back what it hears." && shown?.tools == ["Echo"])
        #expect(report.shownWords(language: "fr", official: false)?.pages == ["Exemple"])
    }

    @Test func onlyLanguagesSidefolkSpeaks() throws {
        #expect(try fields(["strings/fr.json": "{}", "strings/nl.json": "{}"]) == ["strings/nl.json"])
        #expect(try fields(["strings/French.json": "{}"]) == ["strings/French.json"])
        #expect(try fields(["strings/fr.json": "[1]"]) == ["strings/fr.json"])
        #expect(try fields(["strings": "not a folder"]) == ["strings"])
    }

    @Test func onlyWordsTheManifestHas() throws {
        #expect(try fields(["strings/de.json": #"{"homepage": "x"}"#]) == ["strings/de.json.homepage"])
        #expect(try fields(["strings/de.json": #"{"tools": {"nope": {"title": "Nein"}}}"#]) == ["strings/de.json.tools.nope"])
        #expect(try fields(["strings/de.json": #"{"tools": {"echo": {"title": "Echo", "risk": "high"}}}"#]) == ["strings/de.json.tools.echo.risk"])
        #expect(try fields(["strings/de.json": #"{"network_purpose": "um zu streamen"}"#]) == ["strings/de.json.network_purpose"],
                "the manifest has no network purpose to translate")
        // English is the manifest itself: en.json lists only the program's texts.
        #expect(try fields(["strings/en.json": #"{"name": "Other"}"#]) == ["strings/en.json.name"])
    }

    @Test func theSameLimitsAsTheManifest() throws {
        // Half as long again as the manifest's limit (60 for a name), languages running longer than English.
        #expect(try fields(["strings/de.json": #"{"name": "\#(String(repeating: "x", count: 90))"}"#]).isEmpty)
        let long = String(repeating: "x", count: 91)
        #expect(try fields(["strings/ja.json": #"{"name": "\#(long)"}"#]) == ["strings/ja.json.name"])
        #expect(try fields(["strings/ja.json": #"{"name": "  "}"#]) == ["strings/ja.json.name"])
        #expect(try fields(["strings/ja.json": #"{"tagline": "one\ntwo"}"#]) == ["strings/ja.json.tagline"])
        // Hidden characters can disguise a name (T13), in any language.
        #expect(try fields(["strings/ar.json": #"{"name": "‮elpmas"}"#]) == ["strings/ar.json.name"])
        #expect(try fields(["strings/ko.json": #"{"pages": {"main": {"title": "\#(String(repeating: "가", count: 61))"}}}"#]) == ["strings/ko.json.pages.main.title"])
    }

    @Test func textsFollowTheEnglish() throws {
        // A text needs the English list, and only its keys.
        #expect(try fields(["strings/fr.json": #"{"text": {"Hello": "Bonjour"}}"#]) == ["strings/fr.json.text"])
        #expect(try fields(["strings/en.json": Self.english, "strings/fr.json": #"{"text": {"Bye": "Salut"}}"#]) == [#"strings/fr.json.text["Bye"]"#])
        // Every placeholder kept, no new one.
        #expect(try fields(["strings/en.json": Self.english, "strings/fr.json": #"{"text": {"Hi {name}": "Salut"}}"#]) == [#"strings/fr.json.text["Hi {name}"]"#])
        #expect(try fields(["strings/en.json": Self.english, "strings/fr.json": #"{"text": {"Hi {name}": "Salut {nom}"}}"#]) == [#"strings/fr.json.text["Hi {name}"]"#])
        // Counts: the language's own forms, "other" always; "one" may leave the number out.
        #expect(try fields(["strings/en.json": Self.english, "strings/ja.json": #"{"text": {"{count} apps": {"one": "1", "other": "{count}個"}}}"#])
                == [#"strings/ja.json.text["{count} apps"]"#])
        #expect(try fields(["strings/en.json": Self.english, "strings/de.json": #"{"text": {"{count} apps": {"one": "eine App"}}}"#])
                == [#"strings/de.json.text["{count} apps"]"#])
        #expect(try fields(["strings/en.json": Self.english, "strings/de.json": #"{"text": {"{count} apps": {"one": "eine App", "other": "{count} Apps"}}}"#]).isEmpty)
        #expect(try fields(["strings/en.json": Self.english, "strings/es.json": #"{"text": {"Hello": ""}}"#]) == [#"strings/es.json.text["Hello"]"#])
    }

    /// `pt` finds `pt-BR`, a Chinese Mac in Simplified or Traditional script finds `zh-Hans`
    /// (the nearest Sidefolk speaks, as the Kit's `Localized` decides), and English is the manifest.
    @Test func theClosestLanguageOrTheManifest() {
        var strings = ExtensionStrings()
        var pt = ExtensionStrings.Words(), zh = ExtensionStrings.Words(), en = ExtensionStrings.Words()
        pt.name = "Exemplo"
        zh.name = "示例"
        en.text = ["Hello": .plain("Hello")]
        strings.tables = ["pt-BR": pt, "zh-Hans": zh, "en": en]
        #expect(strings.words(for: "pt-BR")?.name == "Exemplo")
        #expect(strings.words(for: "pt")?.name == "Exemplo")
        #expect(strings.words(for: "zh-Hans-CN")?.name == "示例")
        #expect(strings.words(for: "zh-CN")?.name == "示例")
        #expect(strings.words(for: "zh-Hant")?.name == "示例")
        #expect(strings.words(for: "en") == nil)
        #expect(strings.words(for: "fr") == nil)
    }

    /// Older copies of Sidefolk refuse a manifest with a key they don't know (T13), so translations live in their own
    /// folder: a manifest without one, or one with it, decodes exactly as before.
    @Test func manifestsWithoutStringsAreReadAsBefore() throws {
        let plain = try validate([:])
        #expect(plain.isValid && plain.strings == nil)
        let withKey = ExtFixtures.manifest(extra: ["localized": ["fr": ["name": "Exemple"]]])
        #expect(try validate([:], manifest: withKey).errors.map(\.field) == ["localized"])
    }

    @Test func installedWordsFollowThePersonsLanguage() async throws {
        let french = #"{"name": "Exemple", "tools": {"echo": {"title": "Écho"}}, "watchers": {"done": {"title": "Fini"}}, "pages": {"main": {"title": "Page"}}}"#
        for (language, name, tool, watcher) in [("fr", "Exemple", "Écho", "Fini"), ("de", "Sample", "Echo", "Done")] {
            let h = try HostEnv { $0.language = { language } }
            let folder = try h.source("dev.test.sample", manifest: Self.manifest, files: ["server.py": ExtFixtures.server, "strings/fr.json": french])
            guard ExtFixtures.hasPython else { return }
            let info = try await h.host.install(from: folder)
            #expect(info.name == name)
            #expect(info.tools.first?.title == tool)
            #expect(await h.host.watcherKinds().first?.title == watcher)
            #expect(await h.host.pages().first?.extensionName == name)
            await h.host.shutdown()
        }
    }

    @Test func galleryEntriesCarryTheirWordsLeniently() throws {
        let json = #"""
        {"format": 1, "addons": [{"id": "dev.sidefolk.sample", "kind": "extension", "name": "Sample", "tagline": "Says it back",
          "description": "Says back.", "author": "Sidefolk", "version": "1.0.0", "file": "sample-1.0.0.zip", "bytes": 10,
          "sha256": "\#(String(repeating: "a", count: 64))",
          "localized": {"fr": {"name": "Exemple", "tagline": "Le répète"}, "de": {"name": "‮X", "tagline": 3}, "xx": {"name": "Q"}}}]}
        """#
        let catalog = try AddonCatalog.parse(Data(json.utf8), folder: root, fetched: Date())
        let entry = try #require(catalog.addons.first)
        #expect(entry.localized?.words(for: "fr")?.name == "Exemple")
        #expect(entry.localized?.words(for: "de")?.name == nil && entry.localized?.words(for: "de")?.tagline == nil, "a bad field is left out, never the entry")
        #expect(entry.localized?.tables["xx"] == nil)
        // A catalog from before D76, or one this copy can't read the words of, still lists the entry.
        let older = json.replacingOccurrences(of: #""localized""#, with: #""localized_old""#)
        #expect(try AddonCatalog.parse(Data(older.utf8), folder: root, fetched: Date()).addons.count == 1)
    }
}

/// Numbers, sizes and paths in extension text, drawn right to left (D76).
struct BidiTextTests {
    let lri = "\u{2066}", pdi = "\u{2069}"

    @Test func leftToRightIsUntouched() {
        #expect(BidiText.shown("3024 × 1964", rightToLeft: false) == "3024 × 1964")
        #expect(BidiText.shown("Saved to ~/Desktop/qr.png.", rightToLeft: false) == "Saved to ~/Desktop/qr.png.")
    }

    @Test func numbersAloneReadLeftToRight() {
        #expect(BidiText.shown("3024 × 1964", rightToLeft: true) == lri + "3024 × 1964" + pdi)
        #expect(BidiText.shown("12 %", rightToLeft: true) == lri + "12 %" + pdi)
        #expect(BidiText.shown("⌘1", rightToLeft: true) == lri + "⌘1" + pdi)
        // Words of either direction set their own: nothing to add.
        #expect(BidiText.shown("Xcode", rightToLeft: true) == "Xcode")
        #expect(BidiText.shown("الذاكرة", rightToLeft: true) == "الذاكرة")
        #expect(BidiText.shown("", rightToLeft: true) == "")
    }

    @Test func pathsAndSizesInsideArabicKeepTheirOrder() {
        #expect(BidiText.shown("حُفظ في ~/Desktop/qr.png.", rightToLeft: true) == "حُفظ في \(lri)~/Desktop/qr.png\(pdi).")
        #expect(BidiText.shown("الدقة 3024 × 1964 بكسل", rightToLeft: true) == "الدقة \(lri)3024 × 1964\(pdi) بكسل")
        #expect(BidiText.shown("افتح https://example.com/a?b=1", rightToLeft: true) == "افتح \(lri)https://example.com/a?b=1\(pdi)")
        // A Latin sentence in an Arabic layout already reads left to right.
        #expect(BidiText.shown("Saved to ~/Desktop", rightToLeft: true) == "Saved to ~/Desktop")
    }
}
