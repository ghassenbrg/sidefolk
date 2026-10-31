import Foundation

/// An extension's words in the languages Sidefolk speaks (D76): `strings/<language>.json` beside the manifest. A
/// language's file may translate what the manifest shows people (name, tagline, description, tool, watcher, page and
/// palette and game titles, the network's purpose) and carries the program's own sentences under `text`, which `strings/en.json`
/// lists in English. Files of their own rather than a manifest key, because older copies of Sidefolk refuse a manifest
/// with a key they don't know (T13), and ignore a folder they don't read.
public struct ExtensionStrings: Sendable, Hashable {
    public static let folder = "strings"
    /// The languages Sidefolk ships (the app's `AppLanguage.supported`), English first.
    public static let languages = ["en", "fr", "es", "de", "it", "pt-BR", "ja", "ko", "zh-Hans", "ar"]
    public static let maxBytes = 256 * 1024
    public static let maxTexts = 2000

    /// One language's file.
    public struct Words: Sendable, Hashable {
        public var name: String?
        public var tagline: String?
        public var description: String?
        public var networkPurpose: String?
        public var tools: [String: String] = [:]
        public var watchers: [String: Watcher] = [:]
        public var pages: [String: String] = [:]
        public var palettes: [String: Palette] = [:]
        /// Game titles (D75), shown in the Play menu, the panel's header and `games.open`.
        public var games: [String: String] = [:]
        /// The program's sentences by their English key: one text, or forms by count (`one`, `other`…).
        public var text: [String: Text] = [:]

        public init() {}
    }

    public struct Watcher: Sendable, Hashable {
        public var title: String?
        public var description: String?
    }

    public struct Palette: Sendable, Hashable {
        public var title: String?
        public var placeholder: String?
    }

    public enum Text: Sendable, Hashable {
        case plain(String)
        case plural([String: String])

        /// Every form's text, "other" first.
        var forms: [(form: String?, text: String)] {
            switch self {
            case .plain(let s): [(nil, s)]
            case .plural(let f): f.keys.sorted { $0 == "other" ? true : $1 == "other" ? false : $0 < $1 }.map { ($0, f[$0] ?? "") }
            }
        }
    }

    /// The language Sidefolk speaks now (the app's translation, which a change in Settings sets at the next launch):
    /// what extensions are told and which of their words are shown. English in tests, whose runner has no translations.
    public static var current: String {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return language == "Base" ? "en" : language
    }

    /// By language code, English included when the folder has `en.json`.
    public var tables: [String: Words]

    public init(tables: [String: Words] = [:]) { self.tables = tables }

    /// The table for `language` (`fr`, `pt-BR`, `zh-Hans`, or a system code like `pt` or `zh-Hans-CN`), nil for
    /// English or a language the extension doesn't have: then the manifest's own words are shown.
    public func words(for language: String) -> Words? {
        guard let code = Self.match(language, in: Set(tables.keys)), code != "en" else { return nil }
        return tables[code]
    }

    /// The best of `available` for `language`: the same code, else the same language (`pt` → `pt-BR`, `zh-Hans-CN` and
    /// `zh-Hant` → `zh-Hans`). One rule with the Kit's `Localized.normalized`: the nearest language Sidefolk speaks, so a
    /// Traditional-script reader gets Simplified Chinese from the extension rather than its English.
    static func match(_ language: String, in available: Set<String>) -> String? {
        if available.contains(language) { return language }
        let wanted = Locale.Language(identifier: language)
        return available.sorted().first { Locale.Language(identifier: $0).languageCode == wanted.languageCode }
    }

    /// Forms a count may take in each language (CLDR); every language has `other`, which stands in for a missing one.
    public static func pluralForms(_ language: String) -> Set<String> {
        switch Locale.Language(identifier: language).languageCode?.identifier {
        case "ar": ["zero", "one", "two", "few", "many", "other"]
        case "ja", "ko", "zh": ["other"]
        case "fr", "es", "it", "pt": ["one", "many", "other"]
        default: ["one", "other"]
        }
    }

    /// `{name}` placeholders in a text, which every translation keeps.
    static func placeholders(_ text: String) -> Set<String> {
        Set(text.matches(of: /\{([a-z_][a-z0-9_]{0,31})\}/).map { String($0.1) })
    }
}

// MARK: Reading and checking

extension ExtensionStrings {
    /// Reads `strings/` in an extension folder and checks it against the manifest: known languages only, the same
    /// limits as the manifest's own words, only keys the manifest (or `en.json`'s `text`) has, every placeholder kept.
    /// Nil without a `strings` folder.
    static func load(folder: String, manifest: ExtensionManifest, issues: inout [ValidationIssue]) -> ExtensionStrings? {
        let dir = folder + "/" + Self.folder
        guard let st = ExtensionFS.lstat(dir) else { return nil }
        guard ExtensionFS.isDirectory(st) else {
            issues.append(ValidationIssue(field: "strings", message: "must be a folder (not a link)."))
            return nil
        }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0 != ".DS_Store" }.sorted()
        var raw: [String: Any] = [:]
        for name in names {
            let field = "strings/\(name)"
            let code = (name as NSString).deletingPathExtension
            guard name.hasSuffix(".json"), languages.contains(code) else {
                issues.append(ValidationIssue(field: field, message: "isn't a language Sidefolk speaks: name files \(languages.map { "\($0).json" }.joined(separator: ", "))."))
                continue
            }
            let path = dir + "/" + name
            guard let fst = ExtensionFS.lstat(path), ExtensionFS.isRegular(fst), Int(fst.st_size) <= maxBytes,
                  let data = FileManager.default.contents(atPath: path) else {
                issues.append(ValidationIssue(field: field, message: "must be a file (not a link) of at most 256 KiB."))
                continue
            }
            guard (try? JSONValue.checkDepth(data)) != nil, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                issues.append(ValidationIssue(field: field, message: "isn't a JSON object."))
                continue
            }
            raw[code] = object
        }
        var strings = ExtensionStrings()
        // English first: it lists the program's sentences the others translate.
        let english = raw["en"].map { decode($0, file: "strings/en.json", code: "en", manifest: manifest, base: [:], issues: &issues) }
        if let english { strings.tables["en"] = english }
        for code in languages where code != "en" {
            guard var object = raw[code] as? [String: Any] else { continue }
            let file = "strings/\(code).json"
            if english == nil, object["text"] != nil {
                issues.append(ValidationIssue(field: "\(file).text", message: "needs strings/en.json, which lists the English of every text."))
                object["text"] = nil
            }
            strings.tables[code] = decode(object, file: file, code: code, manifest: manifest, base: english?.text ?? [:], issues: &issues)
        }
        return strings
    }

    private static func decode(_ any: Any, file: String, code: String, manifest m: ExtensionManifest, base: [String: Text],
                               issues: inout [ValidationIssue]) -> Words {
        var w = Words()
        guard let o = any as? [String: Any] else { return w }
        let english = code == "en"
        let allowed: Set<String> = english ? ["text"] : ["name", "tagline", "description", "network_purpose", "tools", "watchers", "pages", "palettes", "games", "text"]
        for key in o.keys.sorted() where !allowed.contains(key) {
            let why = english ? "isn't allowed in English: the manifest has the English words; en.json lists only `text`." : "isn't a known key."
            issues.append(ValidationIssue(field: "\(file).\(key)", message: why))
        }
        func line(_ value: Any?, _ field: String, max limit: Int, oneLine: Bool = true, base: String?) -> String? {
            guard let value else { return nil }
            // Most languages run longer than English: a translation may take half as much room again as the manifest's
            // own limit (German, French), still bounded, so no translation can flood a row or a sheet.
            let max = limit * 3 / 2
            guard base != nil else {
                issues.append(ValidationIssue(field: field, message: "translates something the manifest doesn't have."))
                return nil
            }
            guard let s = value as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty, s.count <= max, ExtensionText.clean(s) == s,
                  !oneLine || !s.contains(where: \.isNewline) else {
                issues.append(ValidationIssue(field: field, message: "must be \(oneLine ? "one line of " : "")1–\(max) characters of plain text."))
                return nil
            }
            return s
        }
        func object(_ key: String, names: Set<String>) -> [String: Any] {
            guard let value = o[key] else { return [:] }
            guard let dict = value as? [String: Any] else {
                issues.append(ValidationIssue(field: "\(file).\(key)", message: "should be an object."))
                return [:]
            }
            for name in dict.keys.sorted() where !names.contains(name) {
                issues.append(ValidationIssue(field: "\(file).\(key).\(name)", message: "isn't in the manifest's \(key)."))
            }
            return dict.filter { names.contains($0.key) }
        }
        func fields(_ any: Any, _ field: String, _ allowed: Set<String>) -> [String: Any] {
            guard let d = any as? [String: Any] else {
                issues.append(ValidationIssue(field: field, message: "should be an object."))
                return [:]
            }
            for k in d.keys.sorted() where !allowed.contains(k) { issues.append(ValidationIssue(field: "\(field).\(k)", message: "isn't a known key.")) }
            return d
        }
        w.name = line(o["name"], "\(file).name", max: 60, base: m.name)
        w.tagline = line(o["tagline"], "\(file).tagline", max: 60, base: m.tagline)
        w.description = line(o["description"], "\(file).description", max: 300, oneLine: false, base: m.description)
        w.networkPurpose = line(o["network_purpose"], "\(file).network_purpose", max: 120, base: m.permissions.networkPurpose)
        for (name, value) in object("tools", names: Set(m.tools.keys)) {
            let f = fields(value, "\(file).tools.\(name)", ["title"])
            w.tools[name] = line(f["title"], "\(file).tools.\(name).title", max: 80, base: m.tools[name]?.title ?? name)
        }
        for (name, value) in object("watchers", names: Set(m.watchers.keys)) {
            let f = fields(value, "\(file).watchers.\(name)", ["title", "description"])
            w.watchers[name] = Watcher(title: line(f["title"], "\(file).watchers.\(name).title", max: 60, base: m.watchers[name]?.title),
                                       description: line(f["description"], "\(file).watchers.\(name).description", max: 300, oneLine: false,
                                                         base: m.watchers[name]?.description))
        }
        for (name, value) in object("pages", names: Set(m.pages.keys)) {
            let f = fields(value, "\(file).pages.\(name)", ["title"])
            w.pages[name] = line(f["title"], "\(file).pages.\(name).title", max: 40, base: m.pages[name]?.title)
        }
        for (name, value) in object("palettes", names: Set(m.palettes.keys)) {
            let f = fields(value, "\(file).palettes.\(name)", ["title", "placeholder"])
            w.palettes[name] = Palette(title: line(f["title"], "\(file).palettes.\(name).title", max: 40, base: m.palettes[name]?.title),
                                       placeholder: line(f["placeholder"], "\(file).palettes.\(name).placeholder", max: 60,
                                                         base: m.palettes[name]?.placeholder))
        }
        for (name, value) in object("games", names: Set(m.games.keys)) {
            let f = fields(value, "\(file).games.\(name)", ["title"])
            w.games[name] = line(f["title"], "\(file).games.\(name).title", max: 40, base: m.games[name]?.title)
        }
        w.text = texts(o["text"], file: file, code: code, base: base, issues: &issues)
        return w
    }

    private static func texts(_ any: Any?, file: String, code: String, base: [String: Text], issues: inout [ValidationIssue]) -> [String: Text] {
        guard let any else { return [:] }
        guard let dict = any as? [String: Any] else {
            issues.append(ValidationIssue(field: "\(file).text", message: "should be an object of texts by their English."))
            return [:]
        }
        if dict.count > maxTexts { issues.append(ValidationIssue(field: "\(file).text", message: "can hold at most \(maxTexts) texts.")) }
        let english = code == "en", forms = pluralForms(code)
        var out: [String: Text] = [:]
        for key in dict.keys.sorted() {
            let field = "\(file).text[\"\(key.prefix(40))\"]"
            guard key.count <= 500, ExtensionText.clean(key) == key, !key.isEmpty else {
                issues.append(ValidationIssue(field: field, message: "has a key that isn't 1–500 characters of plain text."))
                continue
            }
            let source = base[key]
            if !english, source == nil {
                issues.append(ValidationIssue(field: field, message: "isn't in strings/en.json."))
                continue
            }
            let value: Text
            if let s = dict[key] as? String {
                value = .plain(s)
            } else if let p = dict[key] as? [String: Any], !p.isEmpty, p.values.allSatisfy({ $0 is String }), p["other"] != nil {
                value = .plural(p.compactMapValues { $0 as? String })
            } else {
                issues.append(ValidationIssue(field: field, message: "must be a text, or forms by count with at least “other”."))
                continue
            }
            // The English placeholders, from the key: a count's forms may leave out {count} ("one apple").
            let wanted = placeholders(key)
            var ok = true
            for (form, text) in value.forms {
                if let form, !forms.contains(form) {
                    issues.append(ValidationIssue(field: field, message: "has the form “\(form)”, which \(code) doesn't use (it has \(forms.sorted().joined(separator: ", ")))."))
                    ok = false
                }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000 || ExtensionText.clean(text) != text {
                    issues.append(ValidationIssue(field: field, message: "must be 1–2000 characters of plain text."))
                    ok = false
                    continue
                }
                let got = placeholders(text)
                let dropsCount = ["zero", "one", "two"].contains(form ?? "") && got == wanted.subtracting(["count"])
                if got != wanted, !dropsCount {
                    let list = { (s: Set<String>) in s.isEmpty ? "none" : s.sorted().map { "{\($0)}" }.joined(separator: " ") }
                    issues.append(ValidationIssue(field: field, message: "has placeholders \(list(got)) but the English has \(list(wanted))."))
                    ok = false
                }
            }
            if ok { out[key] = value }
        }
        return out
    }
}

// MARK: An install sheet's words

/// What an install sheet names, in the person's language (D76): the extension's own translation, then for Sidefolk's own
/// from the gallery the app's catalog (packs from before `strings/`), then the manifest.
public struct ExtensionShownWords: Sendable, Hashable {
    public var name: String
    public var description: String
    /// Titles in the order of the manifest's sorted names.
    public var tools: [String]
    public var watchers: [String]
    public var pages: [String]
}

extension ValidationReport {
    public func shownWords(language: String = ExtensionStrings.current, official: Bool) -> ExtensionShownWords? {
        guard let m = manifest else { return nil }
        let w = strings?.words(for: language)
        let id = m.id
        return ExtensionShownWords(
            name: w?.name ?? (official ? BuiltInExtensionWords.name(id) : nil) ?? m.name,
            description: w?.description ?? (official ? BuiltInExtensionWords.description(id) : nil) ?? m.description ?? "",
            tools: m.tools.keys.sorted().map { w?.tools[$0] ?? (official ? BuiltInExtensionWords.tool(id, $0) : nil) ?? m.tools[$0]?.title ?? $0 },
            watchers: m.watchers.keys.sorted().map { w?.watchers[$0]?.title ?? (official ? BuiltInExtensionWords.watcher(id, $0) : nil) ?? m.watchers[$0]?.title ?? $0 },
            pages: m.pages.keys.sorted().compactMap { w?.pages[$0] ?? (official ? BuiltInExtensionWords.page(id, $0) : nil) ?? m.pages[$0]?.title })
    }

    /// The permissions as the sheet words them: the network's purpose in the person's language when the extension
    /// translated it. Only the wording; what is granted stays `permissions`.
    public func shownPermissions(language: String = ExtensionStrings.current) -> ExtensionPermissions? {
        guard var p = permissions else { return nil }
        if p.networkPurpose != nil, let purpose = strings?.words(for: language)?.networkPurpose { p.networkPurpose = purpose }
        return p
    }
}
