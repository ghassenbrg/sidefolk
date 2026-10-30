import Foundation
import Testing
@testable import SidefolkCore

/// Settings › Extensions' search and filter (D39): every word somewhere, case, accents and width aside; All, On, Off.
@Suite struct ExtensionListQueryTests {
    struct Entry: ExtensionListEntry {
        var name: String
        var isOn: Bool
        var searchTexts: [String]

        init(_ name: String, on: Bool = true, _ more: String...) {
            self.name = name
            isOn = on
            searchTexts = [name] + more
        }
    }

    let list = [
        Entry("Météo", on: true, "Today's weather and the week ahead", "Rain soon", "Can use the internet"),
        Entry("Archives", on: false, "Make a zip file", "Open a zip file"),
        Entry("World Clock", on: true, "Time around the world"),
        Entry("GitHub", on: false, "MCP server", "npx -y @modelcontextprotocol/server-github@2025.4.8"),
    ]

    private func names(_ query: ExtensionListQuery) -> [String] { query.filter(list).map(\.name) }

    @Test func noWordsAndAllShowEverything() {
        let query = ExtensionListQuery()
        #expect(names(query) == ["Météo", "Archives", "World Clock", "GitHub"])
        #expect(!query.isSearching)
        #expect(!query.isNarrowed)
        #expect(!ExtensionListQuery(text: "   \n ").isSearching, "blank words are no search")
        #expect(ExtensionListQuery(show: .off).isNarrowed)
    }

    @Test func caseAccentsAndWidthDoNotMatter() {
        #expect(names(ExtensionListQuery(text: "meteo")) == ["Météo"])
        #expect(names(ExtensionListQuery(text: "MÉTÉO")) == ["Météo"])
        #expect(names(ExtensionListQuery(text: "ＺＩＰ")) == ["Archives"], "full-width letters, as a Japanese keyboard types them")
        #expect(names(ExtensionListQuery(text: "world CLOCK")) == ["World Clock"])
    }

    @Test func everyWordMustAppearSomewhereNotNecessarilyTogether() {
        #expect(names(ExtensionListQuery(text: "rain internet")) == ["Météo"], "two words from two lines")
        #expect(names(ExtensionListQuery(text: "zip internet")).isEmpty)
        #expect(names(ExtensionListQuery(text: "modelcontext")) == ["GitHub"], "a server is found by its command")
        #expect(names(ExtensionListQuery(text: "“zip”,")) == ["Archives"], "quotes and commas around a word don't count")
        #expect(names(ExtensionListQuery(text: "@2025.4.8")) == ["GitHub"], "punctuation inside a word does")
    }

    @Test func theFilterShowsOneStateAndTheCountsFollowTheWordsOnly() {
        #expect(names(ExtensionListQuery(show: .on)) == ["Météo", "World Clock"])
        #expect(names(ExtensionListQuery(show: .off)) == ["Archives", "GitHub"])
        #expect(names(ExtensionListQuery(text: "zip", show: .on)).isEmpty)

        #expect(ExtensionListQuery().counts(list) == .init(all: 4, on: 2, off: 2))
        // While "zip" is looked for among those switched on, the counts say where it is: under Off.
        let counts = ExtensionListQuery(text: "zip", show: .on).counts(list)
        #expect(counts == .init(all: 1, on: 0, off: 1))
        #expect(counts[.off] == 1 && counts[.on] == 0 && counts[.all] == 1)
        #expect(counts + counts == .init(all: 2, on: 0, off: 2))
    }

    @Test func aHitNamesTheFirstLineThatMatched() {
        #expect(ExtensionListQuery(text: "rain").hit(in: list[0].searchTexts) == "Rain soon")
        #expect(ExtensionListQuery(text: "nothing here").hit(in: list[0].searchTexts) == nil)
        #expect(ExtensionListQuery().hit(in: list[0].searchTexts) == nil, "no words, no hit")
    }

    /// Core's texts for an installed extension read what it may do, but not "No access to your files or the internet".
    @Test func whatItMayDoIsSearchedButNotWhatItCannot() {
        func info(_ name: String, _ permissions: ExtensionPermissions) -> ExtensionInfo {
            ExtensionInfo(id: "dev.example." + name.lowercased(), name: name, version: "1.0.0", kind: .sidefolk, enabled: true,
                          running: false, lastError: nil, description: "Says hello.", folk: nil, author: "Jane Doe", origin: nil,
                          iconPath: nil, summary: PermissionSummary.forExtension(permissions), command: nil,
                          tools: [ExtensionToolInfo(name: "ext.\(name.lowercased()).greet", title: "Greet someone", risk: .low, quarantined: false)],
                          watchers: [])
        }
        let offline = ExtensionListQuery.texts(for: info("Offline", ExtensionPermissions()))
        let online = ExtensionListQuery.texts(for: info("Online", ExtensionPermissions(network: true)))
        let internet = ExtensionListQuery(text: "internet")
        #expect(!internet.matches(offline), "\(offline)")
        #expect(internet.matches(online), "\(online)")
        for word in ["greet", "ext.offline.greet", "jane", "dev.example.offline", "hello"] {
            #expect(ExtensionListQuery(text: word).matches(offline), "\(word)")
        }
    }

    /// The built-ins and the gallery's extensions as installed, found by the words a person would try.
    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func theShippedBuiltInsAreFoundByTheirToolsAndPermissions() async throws {
        struct Row: ExtensionListEntry {
            var info: ExtensionInfo
            var isOn: Bool { info.enabled }
            var searchTexts: [String] { ExtensionListQuery.texts(for: info) }
        }
        let h = try HostEnv()
        let bundled = BundledExtensions(directory: ExtFixtures.builtIns)
        await bundled.install(into: h.host)
        for folder in ExtFixtures.addonFolders {
            try await h.host.install(from: ExtFixtures.builtIn(folder), origin: .official, enabled: !["pdf", "qr-codes", "archives", "dev-toolbox", "feeds"].contains(folder))
        }
        let rows = await h.host.extensions().map(Row.init)
        await h.host.shutdown()
        func found(_ text: String) -> Set<String> {
            Set(ExtensionListQuery(text: text).filter(rows).map { $0.info.id.replacingOccurrences(of: "dev.sidefolk.", with: "") })
        }
        #expect(found("sunrise") == ["weather"])
        #expect(found("pull") == ["git"])
        #expect(found("zip").contains("archives"))
        #expect(found("ext.git.clone") == ["git"])
        let online = found("internet")
        #expect(online.isSuperset(of: ["weather", "currency", "feeds"]), "\(online)")
        #expect(online.isDisjoint(with: ["world-clock", "calculator"]), "\(online)")
        #expect(ExtensionListQuery(show: .off).filter(rows).map(\.info.id).contains("dev.sidefolk.pdf"), "PDF Tools starts off")
    }
}
