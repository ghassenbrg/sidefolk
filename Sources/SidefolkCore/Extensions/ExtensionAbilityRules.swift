import Foundation

/// What `ManifestValidator` checks in what an extension declares beyond its tools (D100): its settings, entries, drop
/// actions, its use of the AI and its one-time settings. A mistake is a plain message at install, never a row that
/// quietly isn't there.
enum ExtensionAbilityRules {
    static let maxSettings = 64
    static let maxEntries = 8
    static let maxEntryItems = 32
    static let maxDrops = 6
    static let maxDropMenu = 12

    /// A fixed list and not macOS's own, which knows more on a Mac with more apps and includes words like PATCH and GUIDE.
    static let formatNames: Set<String> = ["JPEG", "JPG", "PNG", "HEIC", "HEIF", "AVIF", "TIFF", "GIF", "BMP", "WEBP", "ICO", "PSD", "SVG", "PDF", "M4A", "MP3", "AAC", "FLAC", "WAV", "AIFF", "OPUS", "OGG", "CAF", "MP4", "M4V", "MOV", "MKV", "WEBM", "CSV", "TSV", "JSON", "PLIST", "XML", "YAML", "TXT", "RTF", "DOCX", "XLSX", "PPTX", "EPUB", "SRT", "VTT", "ZIP", "7Z", "TAR", "GZ", "TGZ", "BZ2", "XZ", "RAR", "TAR.GZ"]

    static func isFormatName(_ tag: String) -> Bool { formatNames.contains(tag) }
    static let maxPatterns = 16

    static func check(_ m: ExtensionManifest) -> [ValidationIssue] {
        settingIssues(m) + entryIssues(m) + dropIssues(m) + aiIssues(m) + actIssues(m) + carriedIssues(m)
    }

    private static func isName(_ s: String) -> Bool { s.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil }
    private static func isPlain(_ s: String, _ longest: Int, oneLine: Bool = true) -> Bool {
        !s.trimmingCharacters(in: .whitespaces).isEmpty && s.count <= longest && ExtensionText.clean(s) == s && (!oneLine || !s.contains(where: \.isNewline))
    }
    private static func isSymbol(_ s: String) -> Bool { s.count <= 64 && s.range(of: ManifestValidator.symbolPattern, options: .regularExpression) != nil }

    // MARK: Settings

    private static func settingIssues(_ m: ExtensionManifest) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if m.settings.count > maxSettings { issues.append(ValidationIssue(field: "settings", message: "can declare at most \(maxSettings) settings.")) }
        var seen: Set<String> = []
        for (i, s) in m.settings.enumerated() {
            let field = "settings[\(i)]"
            if !isName(s.key) { issues.append(ValidationIssue(field: "\(field).key", message: "isn't a valid key (lowercase letters, digits and _).")) }
            if !seen.insert(s.key).inserted { issues.append(ValidationIssue(field: "\(field).key", message: "“\(s.key)” is there twice.")) }
            if !isPlain(s.title, 60) { issues.append(ValidationIssue(field: "\(field).title", message: "must be one line of 1–60 characters of plain text.")) }
            if let d = s.detail, !isPlain(d, 240, oneLine: false) {
                issues.append(ValidationIssue(field: "\(field).detail", message: "must be 1–240 characters of plain text."))
            }
            switch s.type {
            case .choice:
                if !(2...12).contains(s.options.count) { issues.append(ValidationIssue(field: "\(field).options", message: "must hold 2–12 options.")) }
                if Set(s.options.map(\.value)).count != s.options.count {
                    issues.append(ValidationIssue(field: "\(field).options", message: "must have different values."))
                }
                for (j, o) in s.options.enumerated() {
                    if o.value.isEmpty || o.value.count > 40 || ExtensionText.clean(o.value) != o.value {
                        issues.append(ValidationIssue(field: "\(field).options[\(j)].value", message: "must be 1–40 characters of plain text."))
                    }
                    if !isPlain(o.title, 30) { issues.append(ValidationIssue(field: "\(field).options[\(j)].title", message: "must be one line of 1–30 characters of plain text.")) }
                }
            case .number:
                guard let low = s.minimum, let high = s.maximum, low < high, low.isFinite, high.isFinite else {
                    issues.append(ValidationIssue(field: field, message: "a number needs a minimum below its maximum."))
                    break
                }
                if let step = s.step, step <= 0 || step > high - low { issues.append(ValidationIssue(field: "\(field).step", message: "must be above 0 and fit between the minimum and maximum.")) }
            case .text:
                if let n = s.length, !(1...ExtensionManifest.SettingMeta.longestText).contains(n) {
                    issues.append(ValidationIssue(field: "\(field).length", message: "must be 1–\(ExtensionManifest.SettingMeta.longestText)."))
                }
            case .switch:
                break
            }
            if s.type != .choice, !s.options.isEmpty { issues.append(ValidationIssue(field: "\(field).options", message: "is for a choice.")) }
            if s.type != .number, s.minimum != nil || s.maximum != nil || s.step != nil { issues.append(ValidationIssue(field: field, message: "minimum, maximum and step are for a number.")) }
            if s.type != .text, s.length != nil { issues.append(ValidationIssue(field: "\(field).length", message: "is for a text.")) }
            if let value = s.default, s.checked(value) == nil { issues.append(ValidationIssue(field: "\(field).default", message: "isn't a value this setting can hold.")) }
            if s.segmented, s.type != .choice || s.options.count > 4 { issues.append(ValidationIssue(field: "\(field).segmented", message: "is for a choice of at most 4 options.")) }
            if let key = s.follows {
                let followed = m.settings.first { $0.key == key }
                if followed == nil || followed?.key == s.key || followed?.type != s.type || followed?.follows != nil {
                    issues.append(ValidationIssue(field: "\(field).follows", message: "must name another setting of the same type that follows nothing itself."))
                }
            }
        }
        return issues
    }

    // MARK: Entries

    private static func entryIssues(_ m: ExtensionManifest) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if m.entries.count > maxEntries { issues.append(ValidationIssue(field: "entries", message: "can declare at most \(maxEntries) entries.")) }
        if m.entries.filter({ $0.places.contains(.ask) }).count > 1 {
            issues.append(ValidationIssue(field: "entries", message: "can have only one tab in Ask."))
        }
        var ids: Set<String> = []
        func visit(_ entry: ExtensionManifest.EntryMeta, _ field: String, depth: Int) {
            if !isName(entry.id) { issues.append(ValidationIssue(field: "\(field).id", message: "isn't a valid id (lowercase letters, digits and _).")) }
            if !ids.insert(entry.id).inserted { issues.append(ValidationIssue(field: "\(field).id", message: "“\(entry.id)” is there twice.")) }
            if !isPlain(entry.title, 40) { issues.append(ValidationIssue(field: "\(field).title", message: "must be one line of 1–40 characters of plain text.")) }
            if let s = entry.symbol, !isSymbol(s) { issues.append(ValidationIssue(field: "\(field).symbol", message: "must be an SF Symbol name, like leaf.")) }
            if depth == 0, entry.places.isEmpty { issues.append(ValidationIssue(field: "\(field).places", message: "must name companion, pocket or ask.")) }
            // A tab opens one thing: a menu of items doesn't fit one.
            if entry.places.contains(.ask), !entry.items.isEmpty { issues.append(ValidationIssue(field: "\(field).places", message: "can't put a menu of items in Ask: a tab opens one tool or page.")) }
            if depth > 0, !entry.places.isEmpty { issues.append(ValidationIssue(field: "\(field).places", message: "is only for a top-level entry.")) }
            if depth >= 2, !entry.items.isEmpty { issues.append(ValidationIssue(field: "\(field).items", message: "goes two levels deep at most.")) }
            if entry.items.count > maxEntryItems { issues.append(ValidationIssue(field: "\(field).items", message: "can hold at most \(maxEntryItems) items.")) }
            // Exactly one thing to do: its tool, its page, its surface, or a menu of items.
            let does = [entry.tool != nil, entry.page != nil, entry.surface != nil, !entry.items.isEmpty].filter { $0 }.count
            if does != 1 { issues.append(ValidationIssue(field: field, message: "must have one of tool, page, surface or items.")) }
            if let state = entry.state, entry.page == nil || JSONValue.object(state).jsonString.utf8.count > PageState.maxBytes {
                issues.append(ValidationIssue(field: "\(field).state", message: "needs a page, and at most \(PageState.maxBytes) bytes."))
            }
            if let surface = entry.surface, m.surfaces[surface] == nil { issues.append(ValidationIssue(field: "\(field).surface", message: "“\(surface)” isn't one of its surfaces.")) }
            if let tool = entry.tool, m.tools[tool] == nil { issues.append(ValidationIssue(field: "\(field).tool", message: "“\(tool)” isn't one of its tools.")) }
            if let page = entry.page, m.pages[page] == nil { issues.append(ValidationIssue(field: "\(field).page", message: "“\(page)” isn't one of its pages.")) }
            if entry.input != nil, entry.tool == nil, entry.surface == nil { issues.append(ValidationIssue(field: "\(field).input", message: "is for a tool or a surface.")) }
            if let input = entry.input, JSONValue.object(input).jsonString.utf8.count > 4096 {
                issues.append(ValidationIssue(field: "\(field).input", message: "is larger than 4 KB."))
            }
            for (i, item) in entry.items.enumerated() { visit(item, "\(field).items[\(i)]", depth: depth + 1) }
        }
        for (i, entry) in m.entries.enumerated() { visit(entry, "entries[\(i)]", depth: 0) }
        return issues
    }

    // MARK: Drops

    private static func dropIssues(_ m: ExtensionManifest) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if m.drops.count > maxDrops { issues.append(ValidationIssue(field: "drops", message: "can declare at most \(maxDrops) drop actions.")) }
        var ids: Set<String> = []
        for (i, drop) in m.drops.enumerated() {
            let field = "drops[\(i)]"
            if !isName(drop.id) { issues.append(ValidationIssue(field: "\(field).id", message: "isn't a valid id (lowercase letters, digits and _).")) }
            if !ids.insert(drop.id).inserted { issues.append(ValidationIssue(field: "\(field).id", message: "“\(drop.id)” is there twice.")) }
            if !isPlain(drop.title, 30) { issues.append(ValidationIssue(field: "\(field).title", message: "must be one line of 1–30 characters of plain text.")) }
            if let d = drop.detail, !isPlain(d, 80) { issues.append(ValidationIssue(field: "\(field).detail", message: "must be one line of 1–80 characters of plain text.")) }
            if let s = drop.symbol, !isSymbol(s) { issues.append(ValidationIssue(field: "\(field).symbol", message: "must be an SF Symbol name, like tv.")) }
            if drop.kinds.isEmpty { issues.append(ValidationIssue(field: "\(field).kinds", message: "must name file, folder, link or text.")) }
            if drop.patterns.count > maxPatterns { issues.append(ValidationIssue(field: "\(field).patterns", message: "can hold at most \(maxPatterns) patterns.")) }
            for (j, p) in drop.patterns.enumerated() where p.isEmpty || p.count > 200 || ExtensionText.clean(p) != p || p.contains(where: \.isWhitespace) {
                issues.append(ValidationIssue(field: "\(field).patterns[\(j)]", message: "must be 1–200 characters without spaces."))
            }
            guard let tool = m.tools[drop.tool] else {
                issues.append(ValidationIssue(field: "\(field).tool", message: "“\(drop.tool)” isn't one of its tools."))
                continue
            }
            // Only a format's name, from a fixed list, so a tag can't say anything else.
            if let tag = drop.tag, !Self.isFormatName(tag) {
                issues.append(ValidationIssue(field: "\(field).tag", message: "must be a file format's name in capitals, like JPEG or TAR.GZ."))
            }
            if let mark = drop.mark, PackAssets.picturePath(mark) == nil || m.assets == nil {
                issues.append(ValidationIssue(field: "\(field).mark", message: "must be a picture in its assets folder."))
            }
            if drop.menu.count > Self.maxDropMenu { issues.append(ValidationIssue(field: "\(field).menu", message: "can hold at most \(Self.maxDropMenu) choices.")) }
            for (j, item) in drop.menu.enumerated() {
                if !isPlain(item.title, 30) { issues.append(ValidationIssue(field: "\(field).menu[\(j)].title", message: "must be one line of 1–30 characters of plain text.")) }
                if item.input.values.contains(.string("{value}")) || item.input.values.contains(.string("{values}")) || item.input.count > 8 {
                    issues.append(ValidationIssue(field: "\(field).menu[\(j)].input", message: "adds at most 8 arguments, and what was dropped goes in the action's own input."))
                }
            }
            let carriers = drop.input.filter { $0.value == .string("{value}") }.map(\.key)
            let lists = drop.input.filter { $0.value == .string("{values}") }.map(\.key)
            if !lists.isEmpty {
                if lists.count != 1 || !carriers.isEmpty || tool.fileLists[lists[0]] == nil || drop.kinds != [.file] {
                    issues.append(ValidationIssue(field: "\(field).input", message: "\"{values}\" goes under one argument the tool lists in `file_lists`, for dropped files only."))
                }
            } else if carriers.count != 1 {
                issues.append(ValidationIssue(field: "\(field).input", message: "must put \"{value}\" under one argument: what was dropped goes there."))
            } else if !Set(drop.kinds).isDisjoint(with: [.file, .folder]), tool.paths[carriers[0]] == nil {
                // The sandbox opens a file only through a declared path, and Guard checks it there first (D39).
                issues.append(ValidationIssue(field: "\(field).input", message: "a file or folder goes under an argument the tool lists in `paths`, so Guard can check it."))
            }
        }
        return issues
    }

    // MARK: AI and what it used to have

    private static func aiIssues(_ m: ExtensionManifest) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        // What the person reads before they agree: the same rule as the AI's (D106, D107).
        for (name, purpose) in [("place", m.permissions.place?.purpose), ("schedule", m.permissions.schedule?.purpose)] {
            guard let purpose else { continue }
            if !isPlain(purpose, 120) || (!purpose.hasPrefix("to ") && !purpose.hasPrefix("for ")) {
                issues.append(ValidationIssue(field: "permissions.\(name).purpose", message: "must be one plain line of at most 120 characters starting with “to” or “for”."))
            }
        }
        guard let ai = m.permissions.ai else { return issues }
        if !isPlain(ai.purpose, 120) || (!ai.purpose.hasPrefix("to ") && !ai.purpose.hasPrefix("for ")) {
            issues.append(ValidationIssue(field: "permissions.ai.purpose", message: "must be one plain line of at most 120 characters starting with “to” or “for”."))
        }
        if let cap = ai.dailyCap, !ExtensionManifest.AIMeta.caps.contains(cap) {
            issues.append(ValidationIssue(field: "permissions.ai.daily_cap", message: "must be \(ExtensionManifest.AIMeta.caps.lowerBound)–\(ExtensionManifest.AIMeta.caps.upperBound) requests a day."))
        }
        return issues
    }

    private static func actIssues(_ m: ExtensionManifest) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for (name, meta) in [("act", m.permissions.act), ("events", m.permissions.events)] {
            guard let meta else { continue }
            if !(isPlain(meta.purpose, 120) && (meta.purpose.hasPrefix("to ") || meta.purpose.hasPrefix("for "))) {
                issues.append(ValidationIssue(field: "permissions.\(name).purpose", message: "must be one plain line of at most 120 characters starting with “to” or “for”."))
            }
        }
        return issues
    }

    private static func carriedIssues(_ m: ExtensionManifest) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if let from = m.settingsFrom, !isName(from) {
            issues.append(ValidationIssue(field: "settings_from", message: "isn't a valid name (lowercase letters, digits and _)."))
        }
        let names = #"^[A-Za-z0-9_.-]{1,64}$"#
        if m.carries.store.count > 16 { issues.append(ValidationIssue(field: "carries.store", message: "can name at most 16 values.")) }
        if m.carries.history.count > 8 { issues.append(ValidationIssue(field: "carries.history", message: "can name at most 8 tools.")) }
        for (field, list) in [("carries.store", m.carries.store), ("carries.history", m.carries.history)] {
            for name in list where name.range(of: names, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: field, message: "“\(name)” isn't a valid name."))
            }
        }
        return issues
    }
}

extension ExtensionManifest {
    /// Every entry and item, for their words.
    var allEntries: [EntryMeta] {
        func flat(_ list: [EntryMeta]) -> [EntryMeta] { list.flatMap { [$0] + flat($0.items) } }
        return flat(entries)
    }

    /// The commands' names, for their words in `strings/`.
    var commandNames: Set<String> { Set(tools.values.flatMap(\.commands).compactMap(\.name)) }
}
