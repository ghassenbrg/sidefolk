import Foundation
import Testing

/// The founder's rule (D98): everything of an extension lives with the extension, and the app holds only general
/// abilities. This reads every line under `Sources`, comments included: a comment naming an extension is how code
/// written for it starts, and telling the two apart would need a parser for nothing gained. What may name one is
/// `scripts/extension-free-allowlist.json`, the approved exceptions and only those.
@Suite struct ExtensionFreeAppTests {
    /// Flip to true when Playtime has moved (D101): game code and the drop action that waits for Entries (D100) then
    /// fail like everything else, instead of being reported. Nothing else needs changing.
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
    /// What Playtime is moving out (D101), and its name.
    static var gameCode: Regex<Substring> { /\bPlaytime\b|\b(?:Game|Games|Play|Puzzle|Trivia)[A-Z][A-Za-z]*|\b[A-Z][A-Za-z]*(?:Game|Games|Puzzle|Puzzles|Trivia)\b|\bBoardView\b|\bgames\.[a-z]+|\b(?:HandsMatch|HandsReveal|CompanionToss|TossStage|CoinFace|DiceTray|ChanceIntent)\b|\b(?:CompanionPlay(?:er)?|Petting)\b/ }
    /// The drop action that waits for Entries (D100), where it is now.
    static let awaitingEntries = ["Sources/SidefolkApp/AppCoordinator+Ask.swift", "Sources/SidefolkCore/Understanding/DropChoices.swift",
                                  "Sources/SidefolkApp/Ask/DropCard.swift", "Sources/SidefolkApp/Dev/FixtureAskActions.swift",
                                  "Sources/SidefolkApp/Dev/UISnapshots.swift"]

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

    /// Every text file the rule is about, by its path in the repository.
    static func files() -> [String] {
        ["Sources", "Resources/SeedPacks"].flatMap { folder -> [String] in
            let base = root.appendingPathComponent(folder)
            let all = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
            return all.filter { ["swift", "json"].contains($0.pathExtension) }.map { folder + "/" + $0.path.dropFirst(base.path.count + 1) }
        }.sorted()
    }

    static func hits(_ pattern: Regex<Substring>, in lines: [(String, Int, Substring)]) -> [Hit] {
        // Simple boundaries: Unicode's own don't break at the dot in `ext.git.clone`.
        let pattern = pattern.wordBoundaryKind(.simple)
        return lines.flatMap { file, number, text in text.matches(of: pattern).map { Hit(file: file, line: number, found: String(text[$0.range])) } }
    }

    static func lines() throws -> [(String, Int, Substring)] {
        try files().flatMap { file -> [(String, Int, Substring)] in
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { (file, $0.offset + 1, $0.element) }
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
        let lines = try Self.lines()
        let exceptions = try Self.exceptions()
        let details = Self.hits(Self.ids, in: lines) + Self.hits(Self.names, in: lines) + Self.hits(Self.namedInContext, in: lines) + Self.hits(Self.programs, in: lines)
        let games = Self.hits(Self.gameCode, in: lines)
        let detailsLeft = try Self.judged(details, exceptions)
        let gamesLeft = try Self.judged(games, exceptions)

        // Playtime's own id, name and programs, and the drop action, are the two moves still under way.
        let isGameName: (Hit) -> Bool = { $0.found.hasSuffix("playtime") }
        let isDropAction: (Hit) -> Bool = { $0.found.lowercased().hasSuffix("miraya") && Self.awaitingEntries.contains($0.file) }
        let awaiting = detailsLeft.left.filter(isDropAction)
        let mine = detailsLeft.left.filter { !isGameName($0) && !isDropAction($0) }
        #expect(mine.isEmpty, "Extension details in the app (D98):\n\(mine.map(\.description).joined(separator: "\n"))")

        let moving = detailsLeft.left.filter(isGameName) + gamesLeft.left
        if Self.transitionOver {
            #expect(moving.isEmpty, "Game code in the app (D101):\n\(moving.map(\.description).joined(separator: "\n"))")
            #expect(awaiting.isEmpty, "The drop action is still in the app (D100):\n\(awaiting.map(\.description).joined(separator: "\n"))")
            // Stale only once nothing is moving: an exception's symbol may be renamed along the way.
            for index in exceptions.indices where !detailsLeft.used.contains(index) && !gamesLeft.used.contains(index) {
                Issue.record("An exception no longer matches anything, so it should go: \(exceptions[index].file)")
            }
        } else {
            let perFile = Dictionary(grouping: moving, by: \.file).map { "\($0.value.count) \($0.key)" }.sorted()
            print("ExtensionFreeAppTests (reported, not failing, until transitionOver): \(moving.count) lines of game code in \(perFile.count) files;",
                  "\(awaiting.count) lines of the drop action in \(Set(awaiting.map(\.file)).count).\n  " + perFile.joined(separator: "\n  "))
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

        let exception = Exception(why: "", file: "Sources/SidefolkCore/Themes/*", match: #"dev\.sidefolk\.theme"#)
        let theme = Hit(file: "Sources/SidefolkCore/Themes/ThemeLibrary.swift", line: 1, found: "dev.sidefolk.theme")
        let elsewhere = Hit(file: "Sources/SidefolkCore/Other.swift", line: 1, found: "dev.sidefolk.theme")
        #expect(try Self.judged([theme, elsewhere], [exception]).left.map(\.file) == [elsewhere.file])
    }

    /// Every exception is one the founder approved: this list grows only with them.
    @Test func theAllowlistHoldsOnlyTheApprovedExceptions() throws {
        let approved = ["Sources/SidefolkCore/Addons/AddonCatalog.swift", "Resources/SeedPacks/seed-packs.json", "Sources/SidefolkCore/Themes/*",
                        "Sources/SidefolkApp/Dev/*", "Sources/SidefolkApp/Updates/AddonUpdateController.swift",
                        "Sources/*"]
        #expect(Set(try Self.exceptions().map(\.file)) == Set(approved))
    }
}
