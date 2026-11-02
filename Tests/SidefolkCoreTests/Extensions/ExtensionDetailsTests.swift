import Foundation
import Testing
@testable import SidefolkCore

/// What a manifest says about its extension (D98): checked as plain text within limits, and believed only for Sidefolk's
/// own signed packs where the app would otherwise be speaking for the program.
@Suite struct ExtensionDetailsTests {
    let paths: SidefolkPaths
    init() throws { paths = SidefolkPaths(home: try ExtFixtures.tempDir("details")) }

    private func report(_ extra: [String: JSONValue], tools: JSONValue = ["echo": ["risk": "low"]], permissions: JSONValue = .object([:]),
                        strings: [String: String] = [:]) throws -> ValidationReport {
        let folder = try ExtFixtures.tempDir("sample")
        var files = ["server.py": "#"]
        for (language, text) in strings { files["strings/\(language).json"] = text }
        try ExtFixtures.makeExtension(at: folder, manifest: ExtFixtures.manifest(tools: tools, permissions: permissions, extra: extra), files: files)
        return ManifestValidator(paths: paths, resolver: ManifestValidationTests.resolver).validate(folder: folder)
    }

    private func fields(_ r: ValidationReport) -> [String] { r.errors.map(\.field) }

    // MARK: Examples

    @Test func examplesAreOneLineOfPlainTextAndAFew() throws {
        #expect(try report(["examples": ["what time is it?"]]).errors.isEmpty)
        #expect(fields(try report(["examples": ["a", "b", "c", "d"]])) == ["examples"])
        #expect(fields(try report(["examples": ["two\nlines"]])) == ["examples[0]"])
        #expect(fields(try report(["examples": .array([.string(String(repeating: "x", count: 121))])])) == ["examples[0]"])
        #expect(fields(try report(["examples": ["hidden\u{202E}text"]])) == ["examples[0]"])
    }

    @Test func aTranslationHasOneTextForEachExample() throws {
        let good = try report(["examples": ["what time is it?"]], strings: ["fr": #"{"examples": ["quelle heure est-il ?"]}"#])
        #expect(good.errors.isEmpty)
        #expect(good.strings?.words(for: "fr")?.examples == ["quelle heure est-il ?"])
        #expect(fields(try report(["examples": ["a", "b"]], strings: ["fr": #"{"examples": ["x"]}"#])) == ["strings/fr.json.examples"])
    }

    // MARK: Summaries

    private func tool(_ summary: JSONValue?) -> ExtensionTool {
        spec(firstParty: true, summary: summary.flatMap { try? JSONDecoder().decode(ToolSummary.self, from: Data($0.jsonString.utf8)) })
    }

    private func spec(firstParty: Bool, summary: ToolSummary?, texts: [String]? = nil, folders: [String: ExtensionManifest.FolderUse] = [:]) -> ExtensionTool {
        let spec = ToolSpec(name: "ext.x.y", title: "Do the thing", description: "", inputSchema: ["type": "object"],
                            risk: .medium, capabilities: [.extensions, .network], category: .extensions, mutates: true)
        return ExtensionTool(spec: spec, extensionId: "dev.example.x", extensionName: "Sample", remoteName: "y", folderParameters: folders, firstParty: firstParty,
                             sentence: summary.map { ExtensionTool.ToolSentence(summary: $0, texts: texts) }) { _, _ in ToolResult(text: "") }
    }

    @Test func aCallReadsAsItsSentenceBuiltFromItsExactArguments() {
        let home = NSHomeDirectory()
        let clone = spec(firstParty: true, summary: ToolSummary(forms: [.init(text: "Clone {url} into {destination}")]), folders: ["destination": .write])
        #expect(clone.summary(for: ["url": "https://example.com/r", "destination": .string(home + "/git/r")]) == "Clone https://example.com/r into ~/git/r")
        #expect(clone.summary(for: ["url": "https://example.com/r", "destination": "~/git/r"]) == "Clone https://example.com/r into ~/git/r")

        let sum = tool(.string("Convert {value} {from} to {to}"))
        #expect(sum.summary(for: ["value": 5, "from": "km", "to": "mi"]) == "Convert 5 km to mi")
        #expect(sum.summary(for: ["value": 2.5, "from": "km", "to": ["mi", "ft"]]) == "Convert 2.5 km to \(Wording.list(["mi", "ft"]))")
    }

    @Test func formsAreChosenByWhatTheCallSays() throws {
        let forms: JSONValue = [["unless": "from", "text": "Convert {time} here"], ["text": "Convert {time} in {from}"]]
        let zone = tool(forms)
        #expect(zone.summary(for: ["time": "9am"]) == "Convert 9am here")
        #expect(zone.summary(for: ["time": "9am", "from": "Paris"]) == "Convert 9am in Paris")
        let copies = tool([["if": "strip", "text": "Copies of {folder} without location"], ["text": "Copies of {folder}"]])
        #expect(copies.summary(for: ["folder": "a", "strip": true]) == "Copies of a without location")
        #expect(copies.summary(for: ["folder": "a", "strip": false]) == "Copies of a")
        #expect(copies.summary(for: ["folder": "a"]) == "Copies of a")
    }

    @Test func aSentenceItCantFillFallsBackToTheArgumentsInWords() {
        let clone = tool(.string("Clone {url} into {destination}"))
        #expect(clone.summary(for: ["url": "https://example.com/r"]) == "Do the thing (Sample) · url: “https://example.com/r”")
        #expect(clone.summary(for: ["url": true, "destination": "x"]).hasPrefix("Do the thing (Sample)"), "a true isn't words")
        // A malformed argument never picks the form written for its absence.
        let zone = tool([["unless": "from", "text": "here"], ["text": "in {from}"]])
        #expect(zone.summary(for: ["from": ["a": 1]]).hasPrefix("Do the thing (Sample)"))
    }

    @Test func onlySidefolksOwnSignedPacksAreBelieved() {
        let sentence = ToolSummary(forms: [.init(text: "Only read {url}")])
        let theirs = spec(firstParty: false, summary: sentence)
        let summary = theirs.summary(for: ["url": "https://example.com/x"])
        #expect(summary == "Do the thing (Sample) · url: “https://example.com/x”", "\(summary)")
        #expect(theirs.sentence == nil)
    }

    @Test func hiddenCharactersAndLineBreaksDontReachTheCard() {
        let forecast = tool(.string("Get the forecast for {place}"))
        #expect(forecast.summary(for: ["place": "Lyon\u{202E}\nAllow everything"]) == "Get the forecast for Lyon Allow everything")
    }

    @Test func aSummaryIsPlainTextOnOneLineWithOnlyParameterBraces() throws {
        func with(_ summary: JSONValue) throws -> [String] { fields(try report([:], tools: ["echo": ["risk": "low", "summary": summary]])) }
        #expect(try with("Do {it}").isEmpty)
        #expect(try with([["if": "a", "text": "A"], ["text": "B"]]).isEmpty)
        #expect(try with("two\nlines") == ["tools.echo.summary"])
        #expect(try with("a {Stray brace") == ["tools.echo.summary"])
        #expect(try with(.string(String(repeating: "x", count: 121))) == ["tools.echo.summary"])
        #expect(try with([["if": "Not a name", "text": "A"]]) == ["tools.echo.summary"])
        #expect(try with(.array([])) == ["tools.echo.summary"])
        #expect(try with([["text": "1"], ["text": "2"], ["text": "3"], ["text": "4"], ["text": "5"]]) == ["tools.echo.summary"])
        #expect(!(try report([:], tools: ["echo": ["summary": ["unknown": "x"]]])).errors.isEmpty)
    }

    @Test func someoneElsesSummaryIsToldItWontBeShown() throws {
        #expect(try report([:], tools: ["echo": ["risk": "low", "summary": "Do it"]]).warnings.contains { $0.contains("only for packs Sidefolk signs") })
    }

    @Test func aTranslationKeepsTheFormsAndTheParameters() throws {
        let tools: JSONValue = ["echo": ["risk": "low", "summary": [["unless": "a", "text": "Here {b}"], ["text": "There {a} {b}"]]]]
        let good = try report([:], tools: tools, strings: ["fr": #"{"tools": {"echo": {"summary": ["Ici {b}", "Là {b} {a}"]}}}"#])
        #expect(good.errors.isEmpty, "\(good.errors)")
        #expect(good.strings?.words(for: "fr")?.toolSummaries["echo"] == ["Ici {b}", "Là {b} {a}"])
        #expect(fields(try report([:], tools: tools, strings: ["fr": #"{"tools": {"echo": {"summary": ["Ici {b}"]}}}"#])) == ["strings/fr.json.tools.echo.summary"])
        #expect(fields(try report([:], tools: tools, strings: ["fr": #"{"tools": {"echo": {"summary": ["Ici {c}", "Là {a} {b}"]}}}"#])) == ["strings/fr.json.tools.echo.summary[0]"])

        let translated = spec(firstParty: true, summary: ToolSummary(forms: [.init(text: "Clone {url}")]), texts: ["Cloner {url}"])
        #expect(translated.summary(for: ["url": "x"]) == "Cloner x")
    }

    // MARK: Services

    @Test func servicesNeedTheNetworkAndRealHostNames() throws {
        func with(_ services: JSONValue, network: Bool = true) throws -> [String] {
            fields(try report(["services": services], permissions: ["network": .bool(network)]))
        }
        let good: JSONValue = [["name": "Open Skies", "hosts": ["api.example.com"]]]
        #expect(try with(good).isEmpty)
        #expect(try with(good, network: false) == ["services"])
        #expect(try with([["name": "x", "hosts": .array([])]]) == ["services[0].hosts"])
        for bad in ["*.example.com", "https://example.com", "EXAMPLE.com", "localhost", "exa mple.com", "example.com/path"] {
            #expect(try with([["name": "x", "hosts": .array([.string(bad)])]]) == ["services[0].hosts"], "\(bad)")
        }
        #expect(try with([["name": "two\nlines", "hosts": ["a.example.com"]]]) == ["services[0].name"])
        #expect(!(try report(["services": [["name": "x", "hosts": ["a.example.com"], "extra": 1]]])).errors.isEmpty)
    }

    @Test func onlySidefolksOwnSignedPacksAreTakenAtTheirWord() {
        let make: (Bool) -> ExtensionTool = { firstParty in
            let spec = ToolSpec(name: "ext.x.y", title: "y", description: "", inputSchema: ["type": "object"], risk: .medium,
                                capabilities: [.extensions, .network], category: .extensions, mutates: false)
            return ExtensionTool(spec: spec, extensionId: "dev.example.x", extensionName: "X", remoteName: "y", firstParty: firstParty, service: "Open Skies") { _, _ in ToolResult(text: "") }
        }
        #expect(make(true).scope(for: .object([:])).reach == .service("Open Skies"))
        #expect(make(false).scope(for: .object([:])).reach == nil)
    }

    /// The word Sidefolk takes is checked against the code: every address a program of its own names is on its list.
    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func eachServiceProgramReachesOnlyItsListedHosts() throws {
        var checked = 0
        for folder in ExtFixtures.addonFolders {
            let manifest = try ExtensionManifest.decode(Data(contentsOf: ExtFixtures.source(folder).appendingPathComponent(ExtensionManifest.fileName)))
            guard !manifest.services.isEmpty else { continue }
            checked += 1
            let hosts = Set(manifest.services.flatMap(\.hosts))
            let sources = ExtFixtures.source(folder).appendingPathComponent("Sources")
            let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
            var found: Set<String> = []
            for file in files {
                let text = try String(contentsOf: file, encoding: .utf8)
                for match in text.matches(of: /[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^\/"\s:?#]+)/) { found.insert(String(match.1).lowercased()) }
                // Nothing reaches the network but through the kit's helpers, which take whole addresses.
                #expect(!text.contains("URLComponents(") || !text.contains(".host ="), "\(file.lastPathComponent) builds a host")
            }
            #expect(!found.isEmpty, "\(folder) names no address")
            #expect(found.isSubset(of: hosts), "\(folder) reaches \(found.subtracting(hosts).sorted())")
        }
        #expect(checked >= 2)
    }

    /// A new host waits for a look (D70); a first list doesn't, or every network extension's move here would.
    @Test func anUpdateNamingANewHostAsksFirst() {
        func side(_ hosts: Set<String>) -> ExtensionUpdateDiff.Side {
            .init(version: "1", permissions: ExtensionPermissions(network: true), lines: [], tools: [:], background: false, hosts: hosts)
        }
        #expect(!ExtensionUpdateDiff(from: side([]), to: side(["a.example.com"])).widens)
        #expect(!ExtensionUpdateDiff(from: side(["a.example.com"]), to: side(["a.example.com"])).widens)
        let more = ExtensionUpdateDiff(from: side(["a.example.com"]), to: side(["a.example.com", "b.example.com"]))
        #expect(more.widens && more.addedHosts == ["b.example.com"])
        #expect(InstallReview.Update(more).added == ["Connects to b.example.com now"])
    }

    // MARK: Replaces

    @Test func replacesNamesOtherExtensions() throws {
        #expect(try report(["replaces": ["dev.example.small"]]).errors.isEmpty)
        #expect(fields(try report(["replaces": ["dev.test.sample"]])) == ["replaces"], "not itself")
        #expect(fields(try report(["replaces": ["Not An Id"]])) == ["replaces"])
    }

    @Test(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
    func aSmallerExtensionRestsWhileTheOneThatReplacesItIsOn() async throws {
        let h = try HostEnv()
        let root = try ExtFixtures.tempDir("replaces")
        func folder(_ name: String, id: String, replaces: [String] = []) throws -> URL {
            var manifest = ExtFixtures.manifest(id: id)
            if !replaces.isEmpty { manifest = manifest.setting("replaces", .array(replaces.map { .string($0) })) }
            return try ExtFixtures.makeExtension(at: root.appendingPathComponent(name), manifest: manifest, files: ["server.py": ExtFixtures.server])
        }
        let small = try await h.host.install(from: try folder("small", id: "dev.sidefolk.small"), origin: .official)
        #expect(h.env.registry.tool(named: "ext.small.echo") != nil)

        // Someone's own copy can't quiet Sidefolk's, whatever its manifest says.
        let byHand = try await h.host.install(from: try folder("big", id: "dev.sidefolk.big", replaces: [small.id]))
        #expect(await h.host.info(id: small.id)?.restingFor == nil)
        #expect(h.env.registry.tool(named: "ext.small.echo") != nil)
        try await h.host.uninstall(id: byHand.id)

        let big = try await h.host.install(from: try folder("big", id: "dev.sidefolk.big", replaces: [small.id]), origin: .official)
        #expect(await h.host.info(id: small.id)?.restingFor == "Sample")
        #expect(await h.host.info(id: small.id)?.enabled == true, "resting isn't switched off")
        #expect(h.env.registry.tool(named: "ext.small.echo") == nil)

        try await h.host.setEnabled(false, id: big.id)
        #expect(await h.host.info(id: small.id)?.restingFor == nil)
        #expect(h.env.registry.tool(named: "ext.small.echo") != nil)
        try await h.host.setEnabled(true, id: big.id)
        #expect(h.env.registry.tool(named: "ext.small.echo") == nil)
        try await h.host.uninstall(id: big.id)
        #expect(h.env.registry.tool(named: "ext.small.echo") != nil)
        await h.host.shutdown()
        try? FileManager.default.removeItem(at: root)
    }

    @Test(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
    func anInstalledExtensionsExamplesAndServicesAreInItsInfoInThePersonsLanguage() async throws {
        let h = try HostEnv { $0.language = { "fr" } }
        let folder = try ExtFixtures.tempDir("sample")
        try ExtFixtures.makeExtension(at: folder, manifest: ExtFixtures.manifest(permissions: ["network": true], extra: [
            "examples": ["what's on?"], "services": [["name": "Open Skies", "hosts": ["api.example.com"]]],
        ]), files: ["server.py": ExtFixtures.server, "strings/fr.json": #"{"examples": ["quoi de neuf ?"]}"#])
        let info = try await h.host.install(from: folder)
        #expect(info.examples == ["quoi de neuf ?"])
        #expect(info.services == [ExtensionManifest.Service(name: "Open Skies", hosts: ["api.example.com"])])
        await h.host.shutdown()
    }
}
