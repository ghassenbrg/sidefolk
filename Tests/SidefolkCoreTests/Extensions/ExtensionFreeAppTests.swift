import Foundation
import Testing
@testable import SidefolkCore

/// The founder's rule (D98): everything of an extension lives with the extension, and the app holds only general
/// abilities. This reads every line under `Sources`, comments included: a comment naming an extension is how code
/// written for it starts, and telling the two apart would need a parser for nothing gained. What may name one is
/// `scripts/extension-free-allowlist.json`, the approved exceptions and only those.
///
/// What it can't see: a name built while the app runs ("mir" + "aya"). No pattern can; `scripts/extension-free-binary.sh` looks
/// at what a built app really holds, which catches names joined when it is compiled, and nothing catches one read from outside.
@Suite struct ExtensionFreeAppTests {
    /// Flip to true when Playtime has moved (D101): game code then fails like everything else, instead of being
    /// reported. Nothing else needs changing.
    static let transitionOver = false

    /// Ids and names of every extension Sidefolk has published. Companions aren't extensions (D55), so their
    /// `dev.sidefolk.companions.` ids aren't looked for.
    static var ids: Regex<Substring> { /dev\.sidefolk\.(?!companions\b)[a-z0-9-]+/ }
    /// Names that mean nothing else in this code.
    static var names: Regex<Substring> { /\b(?:Miraya|System Vitals\+?|Keep Awake|Dev Toolbox|World Clock|PDF Tools|QR Codes|Git|Currency|Feeds|Archives|Calculator)\b/ }
    /// Words the app has its own feature for (its clipboard tools, its weather watch), so only where they name something.
    static var namedInContext: Regex<Substring> { /(?:[nN]ame|title): "(?:Clipboard|Weather|Images|Your Mac)"|\b(?:Clipboard|Weather|Images|Your Mac) extension\b/ }
    /// A program or a registered tool of one (`ext-weather`, `ext.world-clock.convert_time`).
    static var programs: Regex<Substring> { /\bext[-.](?:weather|world-clock|calculator|system-vitals(?:-plus)?|git|currency|images|pdf|qr-codes|archives|dev-toolbox|feeds|clipboard|keep-awake|miraya|playtime)\b/ }
    /// What Playtime is moving out (D101), and its name; `openGame`, `.gameCenter` and the like too.
    static var gameCode: Regex<Substring> { /\bPlaytime\b|\b(?:Game|Games|Play|Puzzle|Trivia)[A-Z][A-Za-z]*|\b[A-Z][A-Za-z]*(?:Game|Games|Puzzle|Puzzles|Trivia)\b|\b[a-z]+(?:Game|Games|Puzzle|Puzzles|Trivia)(?:[A-Z][A-Za-z]*)?\b|\b(?:game|games|puzzle|trivia)[A-Z][A-Za-z]*\b|\bBoardView\b|\bgames\.[a-z]+|\b(?:HandsMatch|HandsReveal|CompanionToss|TossStage|CoinFace|DiceTray|ChanceIntent)\b|\b(?:CompanionPlay(?:er)?|Petting)\b/ }

    /// Words that are the app's own as much as an extension's (its clipboard tools, its weather watch): `namedInContext` and `names`
    /// look for those where they name something. Every other extension's name and id, from its own manifest, means nothing else here.
    static let commonWords: Set<String> = ["archives", "calculator", "clipboard", "currency", "feeds", "git", "images", "pdf", "weather", "your mac", "system vitals plus"]

    /// What the gallery's manifests say, read when the test runs, so a new extension needs no hand-kept list. Nil with no add-ons
    /// checkout at hand: the patterns above still run.
    static func manifestWords() -> (details: [String], moving: [String])? {
        let env = ProcessInfo.processInfo.environment["SIDEFOLK_ADDONS_REPO"].map { URL(fileURLWithPath: $0) }
        let repo = env ?? root.deletingLastPathComponent().appendingPathComponent("sidefolk-addons")
        let folder = repo.appendingPathComponent("extensions")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        func spoken(_ s: String) -> String { s.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").lowercased() }
        var details: Set<String> = [], moving: Set<String> = []
        for name in names {
            let file = folder.appendingPathComponent(name).appendingPathComponent(ExtensionManifest.fileName)
            guard let data = try? Data(contentsOf: file), let m = try? JSONDecoder().decode(JSONValue.self, from: data), let id = m["id"]?.stringValue else { continue }
            let own = [String(id.split(separator: ".").last ?? ""), m["name"]?.stringValue ?? ""].map(spoken).filter { !$0.isEmpty && !commonWords.contains($0) }
            if id.hasSuffix(".playtime") { moving.formUnion(own) } else { details.formUnion(own) }
            for key in ["games", "surfaces"] {
                for (game, meta) in m[key]?.objectValue ?? [:] {
                    moving.insert(spoken(game))
                    if let title = meta["title"]?.stringValue { moving.insert(spoken(title)) }
                }
            }
        }
        return (details.sorted(), moving.sorted())
    }

    /// One of those words, whatever its case, however it is joined up: `Keep Awake`, `keep-awake`, `KeepAwake`, `keep_awake`.
    static func anyOf(_ words: [String]) throws -> Regex<Substring>? {
        guard !words.isEmpty else { return nil }
        let parts = words.map { $0.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[ _-]?") }
        return try Regex("(?i)\\b(?:\(parts.joined(separator: "|")))\\b", as: Substring.self)
    }

    struct Exception: Decodable {
        var why: String
        var file: String
        var match: String

        /// `folder/*` covers everything under it.
        func covers(file path: String) -> Bool {
            file.hasSuffix("/*") ? path.hasPrefix(file.dropLast()) : path == file
        }
    }

    struct Hit: CustomStringConvertible {
        var file: String
        var line: Int
        var found: String
        var description: String { "\(file):\(line) \(found)" }
    }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func exceptions() throws -> [Exception] {
        struct File: Decodable { var exceptions: [Exception] }
        let data = try Data(contentsOf: root.appendingPathComponent("scripts/extension-free-allowlist.json"))
        return try JSONDecoder().decode(File.self, from: data).exceptions
    }

    /// Everything under these, by its path in the repository, as a name to read: a picture named for an extension is as much in
    /// the app as a line of code.
    static func everything() -> [String] {
        ["Sources", "Resources"].flatMap { folder -> [String] in
            let base = root.appendingPathComponent(folder)
            let all = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey])?.compactMap { $0 as? URL } ?? []
            return all.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.map { folder + "/" + $0.path.dropFirst(base.path.count + 1) }
        }.sorted()
    }

    /// Every text file the rule is about. Info.plist's words reach the person in the system's own permission prompts and the catalog
    /// is what they read, so they count as much as any screen; Package.swift says what ships. A vendored library isn't ours to read.
    static func files() -> [String] {
        let text: Set<String> = ["swift", "json", "xcstrings", "md", "js", "html", "plist", "entitlements", "txt"]
        return (everything().filter { text.contains(($0 as NSString).pathExtension) && !$0.contains("/vendor/") } + ["Package.swift"]).sorted()
    }

    /// Names of files, as lines of their own.
    static func nameLines() -> [(String, Int, Substring)] { everything().map { ($0, 0, Substring(($0 as NSString).lastPathComponent)) } }

    static func hits(_ pattern: Regex<Substring>, in lines: [(String, Int, Substring)]) -> [Hit] {
        // Simple boundaries: Unicode's own don't break at the dot in `ext.git.clone`.
        let pattern = pattern.wordBoundaryKind(.simple)
        return lines.flatMap { file, number, text in text.matches(of: pattern).map { Hit(file: file, line: number, found: String(text[$0.range])) } }
    }

    static func lines() throws -> [(String, Int, Substring)] {
        try files().flatMap { file -> [(String, Int, Substring)] in
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            let all = text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { (file, $0.offset + 1, $0.element) }
            // The catalog's English keys are what the app says; its nine translations and comments are the same again, many times over.
            return file.hasSuffix(".xcstrings") ? all.filter { $0.2.hasPrefix("    \"") } : all
        }
    }

    /// Hits no exception covers, and the exceptions that covered nothing.
    static func judged(_ hits: [Hit], _ exceptions: [Exception]) throws -> (left: [Hit], used: Set<Int>) {
        let patterns = try exceptions.map { try Regex($0.match) }
        var used = Set<Int>()
        let left = hits.filter { hit in
            let covering = exceptions.indices.first { exceptions[$0].covers(file: hit.file) && hit.found.contains(patterns[$0]) }
            if let covering { used.insert(covering) }
            return covering == nil
        }
        return (left, used)
    }

    @Test func nothingButTheApprovedExceptionsNamesAnExtension() throws {
        let lines = try Self.lines() + Self.nameLines()
        let exceptions = try Self.exceptions()
        // A folder a skill sorts downloads into can be called Archives: the names that are also plain words count in code and data.
        let code = lines.filter { !$0.0.hasSuffix(".md") }
        var details = Self.hits(Self.ids, in: lines) + Self.hits(Self.names, in: code) + Self.hits(Self.namedInContext, in: lines) + Self.hits(Self.programs, in: lines)
        var games = Self.hits(Self.gameCode, in: lines)
        if let words = Self.manifestWords() {
            if let pattern = try Self.anyOf(words.details) { details += Self.hits(pattern, in: lines) }
            if let pattern = try Self.anyOf(words.moving) { games += Self.hits(pattern, in: lines) }
        }
        let detailsLeft = try Self.judged(details, exceptions)
        let gamesLeft = try Self.judged(games, exceptions)

        // Playtime's own id, name and programs are the one move still under way.
        let isGameName: (Hit) -> Bool = { $0.found.hasSuffix("playtime") }
        let mine = detailsLeft.left.filter { !isGameName($0) }
        #expect(mine.isEmpty, "Extension details in the app (D98):\n\(mine.map(\.description).joined(separator: "\n"))")

        let moving = detailsLeft.left.filter(isGameName) + gamesLeft.left
        if Self.transitionOver {
            #expect(!FileManager.default.fileExists(atPath: Self.root.appendingPathComponent("Sources/SidefolkApp/Play").path), "The Play folder is gone (D101).")
            #expect(moving.isEmpty, "Game code in the app (D101):\n\(moving.map(\.description).joined(separator: "\n"))")
            // Stale only once nothing is moving: an exception's symbol may be renamed along the way.
            for index in exceptions.indices where !detailsLeft.used.contains(index) && !gamesLeft.used.contains(index) {
                Issue.record("An exception no longer matches anything, so it should go: \(exceptions[index].file)")
            }
        } else {
            let perFile = Dictionary(grouping: moving, by: \.file).map { "\($0.value.count) \($0.key)" }.sorted()
            print("ExtensionFreeAppTests (reported, not failing, until transitionOver): \(moving.count) lines of game code in \(perFile.count) files.\n  "
                  + perFile.joined(separator: "\n  "))
        }
    }

    /// The guard itself: what it is meant to catch, comments included, is caught.
    @Test func theGuardSeesWhatItShould() throws {
        let lines: [(String, Int, Substring)] = [("Sources/A.swift", 1, "// the World Clock extension"), ("Sources/A.swift", 2, #"case "dev.sidefolk.weather":"#),
                                                 ("Sources/A.swift", 3, #"ExtensionLook(name: "Weather")"#), ("Sources/A.swift", 4, "tool: ext.git.clone"),
                                                 ("Sources/A.swift", 5, "the weather in Lyon, and the clipboard")]
        let found = Self.hits(Self.ids, in: lines) + Self.hits(Self.names, in: lines) + Self.hits(Self.namedInContext, in: lines) + Self.hits(Self.programs, in: lines)
        #expect(Set(found.map(\.line)) == [1, 2, 3, 4])
        #expect(Self.hits(Self.ids, in: [("Sources/A.swift", 1, "dev.sidefolk.companions.kiko")]).isEmpty)

        // However it is cased or joined, in code or in a file's name.
        let joined: [(String, Int, Substring)] = [#"id.hasSuffix(".miraya")"#, #""dev.sidefolk." + "miraya""#, #"name.lowercased() == "miraya""#, #"case "miraya":"#,
                                                  "struct MirayaView", "keep_awake", "KeepAwake", "game-miraya.webp", "dropMirayaFile"].enumerated().map { ("Sources/A.swift", $0.offset, Substring($0.element)) }
        let word = try #require(try Self.anyOf(["miraya", "keep awake"]))
        let caught = Set(Self.hits(word, in: joined).map(\.line))
        #expect(caught.isSuperset(of: [0, 1, 2, 3, 5, 6, 7]), "\(caught)")
        let code: [(String, Int, Substring)] = ["openGame()", "gameShelf", ".gameCenter", "gamesMenuSentences", "struct SudokuBoardGame"].enumerated().map { ("Sources/A.swift", $0.offset, Substring($0.element)) }
        #expect(Set(Self.hits(Self.gameCode, in: code).map(\.line)) == [0, 1, 2, 3, 4])

        let exception = Exception(why: "", file: "Sources/SidefolkCore/Themes/*", match: #"dev\.sidefolk\.theme"#)
        let theme = Hit(file: "Sources/SidefolkCore/Themes/ThemeLibrary.swift", line: 1, found: "dev.sidefolk.theme")
        let elsewhere = Hit(file: "Sources/SidefolkCore/Other.swift", line: 1, found: "dev.sidefolk.theme")
        #expect(try Self.judged([theme, elsewhere], [exception]).left.map(\.file) == [elsewhere.file])
    }

    /// Every exception is one the founder approved: this list grows only with them.
    @Test func theAllowlistHoldsOnlyTheApprovedExceptions() throws {
        let approved = ["Sources/SidefolkCore/Addons/AddonCatalog.swift", "Resources/SeedPacks/seed-packs.json", "Sources/SidefolkCore/Themes/*", "Resources/Themes/*",
                        "Sources/SidefolkApp/Dev/*", "Sources/SidefolkApp/Updates/AddonUpdateController.swift",
                        "Sources/*"]
        #expect(Set(try Self.exceptions().map(\.file)) == Set(approved))
    }
}
