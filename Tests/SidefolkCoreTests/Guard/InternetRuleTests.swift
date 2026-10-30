import Foundation
import Testing
@testable import SidefolkCore

/// Using the internet without a card every time (D47): sites and built-in services the person allowed hold even
/// after outside content was read; nothing a steered model writes reaches a new site without the person.
@Suite struct InternetRuleTests {
    let engine = PermissionEngine()

    // The tools the rules tell apart.
    static let fetch = ToolSpec(name: "web.fetch", title: "Read a web page", description: "", inputSchema: .object([:]),
                                risk: .low, capabilities: [.network], category: .web, mutates: false)
    static let watch = ToolSpec(name: "watch.create", title: "Watch", description: "", inputSchema: .object([:]),
                                risk: .low, capabilities: [.watch, .network, .filesRead], category: .watch, mutates: true)
    static let report = ToolSpec(name: "watch.report", title: "Report", description: "", inputSchema: .object([:]),
                                 risk: .low, capabilities: [.watch, .network], category: .watch, mutates: true)
    /// Weather's forecast: a built-in extension that only talks to Open-Meteo.
    static let forecast = ToolSpec(name: "ext.weather.forecast", title: "Forecast", description: "", inputSchema: .object([:]),
                                   risk: .medium, capabilities: [.extensions, .network], category: .extensions, mutates: false)
    /// Someone else's extension with the network: it may post anything anywhere.
    static let poster = ToolSpec(name: "ext.poster.post", title: "Post", description: "", inputSchema: .object([:]),
                                 risk: .medium, capabilities: [.extensions, .network], category: .extensions, mutates: true)

    static let page = "https://docs.example.com/guide"
    static let weather = ToolScope(extensionId: "dev.sidefolk.weather", reach: .service("Open-Meteo"))
    static let siteGrant = Grant(tool: "web.fetch", scope: ["host": "docs.example.com"], callerKind: "agent")
    static let weatherGrant = Grant(tool: "ext.weather.forecast", scope: ["extension": "dev.sidefolk.weather"], callerKind: "agent")

    func decide(_ spec: ToolSpec = Self.fetch, url: String? = Self.page, scope: ToolScope? = nil, caller: Caller = .agent(runId: "r"),
                tainted: Bool = false, rule: InternetRule = .oncePerSite, mode: GuardMode = .askOncePerKind,
                grants: [Grant] = [], typed: String = "") -> GuardDecision {
        engine.evaluate(spec: spec, input: .object([:]), summary: "s", scope: scope ?? ToolScope(url: url), caller: caller,
                        tainted: tainted, policy: GuardPolicy(mode: mode, internet: rule), grants: grants, folders: [],
                        mentions: UserMentions(text: typed))
    }

    func card(_ d: GuardDecision, sourceLocation: SourceLocation = #_sourceLocation) -> ApprovalRequest? {
        guard case .ask(let r) = d else { Issue.record("expected a card, got \(d)", sourceLocation: sourceLocation); return nil }
        return r
    }

    // MARK: Ask once for each site (the default)

    @Test func aPageSidefolkChoseAsksOnceThenTheSiteHolds() {
        let r = card(decide())
        #expect(r?.canAlways == true)
        #expect(r?.site == "docs.example.com")
        #expect(r?.effect == .usesInternet)
        #expect(decide(grants: [Self.siteGrant]) == .allow(.always))
        #expect(decide(url: "https://www.docs.example.com/guide", grants: [Self.siteGrant]) == .allow(.always))
        // A site grant never covers a query (audit F1), so that card still offers "Always" for the site.
        #expect(card(decide(url: "https://docs.example.com/search?q=swift", grants: [Self.siteGrant]))?.canAlways == true)
    }

    @Test func anAllowedSiteHoldsAfterOutsideContent() {
        #expect(decide(tainted: true, grants: [Self.siteGrant]) == .allow(.always))
        // A grant saved with "www." by an older version names the same site.
        let www = Grant(tool: "web.fetch", scope: ["host": "www.docs.example.com"], callerKind: "agent")
        #expect(decide(tainted: true, grants: [www]) == .allow(.always))
    }

    @Test func afterOutsideContentANewSiteAsksWithoutAlways() {
        // Injection-shaped: a page told the model to send what it knows to a site of its choosing.
        let r = card(decide(url: "https://collector.test/c?d=dXNlcjpzZWNyZXQ", tainted: true, grants: [Self.siteGrant]))
        #expect(r?.canAlways == false)
        #expect(r?.tainted == true)
        #expect(r?.canAllowForRequest == false)
        // Even with the person's own site in its name, or a label of data in front of it.
        _ = card(decide(url: "https://docs.example.com.collector.test/x", tainted: true, grants: [Self.siteGrant]))
        _ = card(decide(url: "https://c2VjcmV0.docs.example.com/x", tainted: true, grants: [Self.siteGrant]))
    }

    @Test func afterOutsideContentAnAllowedSiteStillAsksForAQueryOrFragment() {
        let r = card(decide(url: "https://docs.example.com/search?q=secret", tainted: true, grants: [Self.siteGrant]))
        #expect(r?.canAlways == false)
        _ = card(decide(url: "https://docs.example.com/guide#secret", tainted: true, grants: [Self.siteGrant]))
    }

    @Test func onlyReadingGetsTheSiteAfterOutsideContent() {
        // A watcher keeps fetching on its own; it asks while tainted, as before.
        let watchGrant = Grant(tool: "watch.create", scope: ["host": "docs.example.com"], callerKind: "agent")
        _ = card(decide(Self.watch, tainted: true, grants: [watchGrant]))
        // A grant with no site in it never stands for a site after outside content.
        let unscoped = Grant(tool: "web.fetch", callerKind: "agent")
        #expect(decide(grants: [unscoped]) == .allow(.always))
        _ = card(decide(tainted: true, grants: [unscoped]))
    }

    @Test func aTypedAddressNeverAsks() {
        #expect(decide(tainted: true, typed: "read \(Self.page) please") == .allow(.auto))
        #expect(decide(rule: .askEachTime, typed: "read \(Self.page)") == .allow(.auto))
    }

    // MARK: Built-in services

    @Test func aBuiltInServiceIsAllowedOnceForGood() {
        let r = card(decide(Self.forecast, scope: Self.weather))
        #expect(r?.canAlways == true)
        #expect(r?.service == "Open-Meteo")
        #expect(decide(Self.forecast, scope: Self.weather, grants: [Self.weatherGrant]) == .allow(.always))
        // After outside content the person's grant holds: the model can't choose where it goes.
        #expect(decide(Self.forecast, scope: Self.weather, tainted: true, grants: [Self.weatherGrant]) == .allow(.always))
        #expect(decide(Self.forecast, scope: Self.weather, tainted: true, mode: .fullAccess, grants: [Self.weatherGrant]) == .allow(.always))
    }

    @Test func afterOutsideContentABuiltInServiceIsNeverAllowedForGood() {
        // What goes in it may be steered, so the grant must come from a clean turn (or Settings' rule).
        let r = card(decide(Self.forecast, scope: Self.weather, tainted: true))
        #expect(r?.canAlways == false)
        #expect(r?.canAllowForRequest == false)
        _ = card(decide(Self.forecast, scope: Self.weather, tainted: true, mode: .fullAccess))
        _ = card(decide(Self.forecast, scope: Self.weather, tainted: true, mode: .auto))
        // A grant for the tool with no service in it never stands for one.
        let unscoped = Grant(tool: "ext.weather.forecast", callerKind: "agent")
        _ = card(decide(Self.forecast, scope: Self.weather, tainted: true, grants: [unscoped]))
    }

    @Test func someoneElsesNetworkExtensionKeepsItsRules() {
        let scope = ToolScope(extensionId: "com.acme.poster")
        let grant = Grant(tool: "ext.poster.post", scope: ["extension": "com.acme.poster"], callerKind: "agent")
        #expect(decide(Self.poster, scope: scope, grants: [grant]) == .allow(.always))
        // It may send anything anywhere: after outside content it asks, with no "Always", whatever the setting.
        for rule in InternetRule.allCases {
            let r = card(decide(Self.poster, scope: scope, tainted: true, rule: rule, grants: [grant]))
            #expect(r?.canAlways == false)
        }
        _ = card(decide(Self.poster, scope: scope, tainted: true, mode: .fullAccess, grants: [grant]))
        _ = card(decide(Self.poster, scope: scope, rule: .withoutAsking))
    }

    @Test func aBuiltInServiceClaimDoesNotCoverOtherCapabilities() {
        let writer = ToolSpec(name: "ext.weather.save", title: "Save", description: "", inputSchema: .object([:]),
                              risk: .medium, capabilities: [.extensions, .network, .filesWrite], category: .extensions, mutates: true)
        let grant = Grant(tool: "ext.weather.save", scope: ["extension": "dev.sidefolk.weather"], callerKind: "agent")
        let r = card(decide(writer, scope: Self.weather, tainted: true, grants: [grant]))
        #expect(r?.canAlways == false)
        #expect(r?.service == nil)
    }

    @Test func reportsOfThisMacReachNothingAndWeatherReportsOnlyOpenMeteo() {
        let openMeteo = ToolScope(reach: .service("Open-Meteo"))
        #expect(decide(Self.report, scope: ToolScope(reach: .nowhere), tainted: true) == .allow(.auto))
        #expect(decide(Self.report, scope: openMeteo) == .allow(.auto))
        // After outside content a steered place name would reach Open-Meteo: it asks, unless the person said so.
        _ = card(decide(Self.report, scope: openMeteo, tainted: true))
        let grant = Grant(tool: "watch.report", scope: PermissionEngine.grantScope(for: openMeteo), callerKind: "agent")
        #expect(grant.scope.string("service") == "Open-Meteo")
        #expect(decide(Self.report, scope: openMeteo, tainted: true, grants: [grant]) == .allow(.always))
        #expect(decide(Self.report, scope: openMeteo, tainted: true, rule: .withoutAsking) == .allow(.webSetting))
        // Without a reach, a report could go anywhere: it asks after outside content, as before.
        _ = card(decide(Self.report, scope: .none, tainted: true))
    }

    // MARK: Don't ask before reading

    @Test func withoutAskingReadsAndUsesServices() {
        #expect(decide(rule: .withoutAsking) == .allow(.webSetting))
        #expect(decide(url: "https://news.example.org/search?q=swift", rule: .withoutAsking) == .allow(.webSetting))
        #expect(decide(Self.forecast, scope: Self.weather, tainted: true, rule: .withoutAsking) == .allow(.webSetting))
    }

    @Test func withoutAskingStillAsksForANewSiteAfterOutsideContent() {
        let r = card(decide(url: "https://collector.test/x?d=secret", tainted: true, rule: .withoutAsking))
        #expect(r?.canAlways == false)
        #expect(decide(tainted: true, rule: .withoutAsking, grants: [Self.siteGrant]) == .allow(.always))
        // Making a watcher is a change, not a read.
        _ = card(decide(Self.watch, rule: .withoutAsking))
    }

    // MARK: Ask each time

    @Test func askEachTimeAsksEveryTimeWhateverTheMode() {
        for mode in GuardMode.allCases {
            let r = card(decide(rule: .askEachTime, mode: mode, grants: [Self.siteGrant]))
            #expect(r?.canAlways == false)
            _ = card(decide(Self.forecast, scope: Self.weather, rule: .askEachTime, mode: mode, grants: [Self.weatherGrant]))
        }
        // Even what never asked before: a weather report reaches Open-Meteo.
        _ = card(decide(Self.report, scope: ToolScope(reach: .service("Open-Meteo")), rule: .askEachTime))
        #expect(decide(Self.report, scope: ToolScope(reach: .nowhere), rule: .askEachTime) == .allow(.auto))
    }

    // MARK: Who it applies to

    @Test func otherCallersKeepTheirRules() {
        let routine = Caller.routine(id: "morning")
        _ = card(decide(caller: routine, tainted: true, grants: [Grant(tool: "web.fetch", scope: ["host": "docs.example.com"], callerKind: "routine")]))
        _ = card(decide(caller: routine, rule: .withoutAsking))
        #expect(decide(caller: routine, rule: .askEachTime,
                       grants: [Grant(tool: "web.fetch", scope: ["host": "docs.example.com"], callerKind: "routine")]) == .allow(.always))
    }

    @Test func turningTheNetworkOffStillWins() {
        let off = GuardPolicy(disabled: [.network], internet: .withoutAsking)
        let d = engine.evaluate(spec: Self.fetch, input: .object([:]), summary: "s", scope: ToolScope(url: Self.page), caller: .agent(runId: "r"),
                                tainted: false, policy: off, grants: [Self.siteGrant], folders: [])
        guard case .deny = d else { Issue.record("expected deny"); return }
    }

    // MARK: Storage

    @Test func theRuleIsSavedAndOlderPoliciesReadAsTheDefault() throws {
        let saved = try JSONEncoder().encode(GuardPolicy(internet: .withoutAsking))
        #expect(try JSONDecoder().decode(GuardPolicy.self, from: saved).internet == .withoutAsking)
        let older = Data(#"{"mode":"auto","disabled":[]}"#.utf8)
        #expect(try JSONDecoder().decode(GuardPolicy.self, from: older).internet == .oncePerSite)
        let unknown = Data(#"{"mode":"auto","internet":"never"}"#.utf8)
        let policy = try JSONDecoder().decode(GuardPolicy.self, from: unknown)
        #expect(policy.internet == .oncePerSite)
        #expect(policy.mode == .auto)
    }

    @Test func aSiteFromSettingsIsTheGrantACardMakes() async throws {
        let store = PermissionStore(try AppDatabase.inMemory())
        #expect(try await store.allowSite("  https://www.Docs.Example.com/guide?x=1 ") == "docs.example.com")
        #expect(try await store.allowSite("docs.example.com") == "docs.example.com")
        let grants = try await store.grants()
        #expect(grants.count == 1)
        #expect(decide(tainted: true, grants: grants) == .allow(.always))
        for bad in ["localhost", "192.168.1.20", "not a site", "com", "file:///etc/passwd", ""] {
            await #expect(throws: UserFacingError.self) { try await store.allowSite(bad) }
        }
    }
}

/// Where a call may go once Guard let it through for one site (D47).
@Suite struct InternetSiteHoldTests {
    @Test func aSiteAllowedAfterOutsideContentIsTheOnlyOneTheFetchMayReach() async throws {
        let env = try TestEnv()
        let fetcher = ScriptedFetcher()
        fetcher.serve(InternetRuleTests.page, html: "<p>Guide</p>")
        fetcher.serve("https://news.example.org/a", html: "<p>News</p>")
        env.registry.register(WebFetchTool(fetcher: fetcher))
        try await env.permissions.addGrant(InternetRuleTests.siteGrant)

        let held = await env.executor.execute(name: "web.fetch", input: ["url": .string(InternetRuleTests.page)],
                                              caller: .agent(runId: "r"), tainted: true)
        #expect(held.isOK)
        // In a clean turn the person's grant has nothing to hold back.
        let clean = await env.executor.execute(name: "web.fetch", input: ["url": .string(InternetRuleTests.page)], caller: .agent(runId: "r"))
        #expect(clean.isOK)
        // An address the person typed goes where its site sends it.
        let typed = await env.executor.execute(name: "web.fetch", input: ["url": "https://news.example.org/a"], caller: .agent(runId: "r"),
                                               tainted: true, mentions: UserMentions(text: "read https://news.example.org/a"))
        #expect(typed.isOK)
        #expect(fetcher.sites == ["docs.example.com", nil, nil])
    }

    @Test func withoutAskingIsLoggedAsTheWebSetting() async throws {
        let env = try TestEnv()
        let fetcher = ScriptedFetcher()
        fetcher.serve(InternetRuleTests.page, html: "<p>Guide</p>")
        env.registry.register(WebFetchTool(fetcher: fetcher))
        try await env.permissions.setPolicy(GuardPolicy(internet: .withoutAsking))
        let out = await env.executor.execute(name: "web.fetch", input: ["url": .string(InternetRuleTests.page)], caller: .agent(runId: "r"))
        #expect(out.isOK)
        #expect(try await env.activity.recent()[0].decision == .webSetting)
    }
}

/// Sidefolk's word for its own programs (`BuiltInServices`) is checked against their code.
@Suite struct BuiltInServicesTests {
    @Test func eachServiceProgramReachesOnlyItsListedHosts() throws {
        for (id, service) in BuiltInServices.byExtension {
            // Currency is in the add-on gallery (D55): read when a checkout of it is beside this one.
            let folder = ExtFixtures.source(String(id.split(separator: ".").last!)).appendingPathComponent("Sources")
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
            #expect(!files.isEmpty, "\(id) has no sources at \(folder.path)")
            var found: Set<String> = []
            for file in files {
                let text = try String(contentsOf: file, encoding: .utf8)
                for match in text.matches(of: /[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^\/"\s:?#]+)/) { found.insert(String(match.1).lowercased()) }
                // Nothing reaches the network but through the kit's helpers, which take whole addresses.
                #expect(!text.contains("URLComponents(") || !text.contains(".host ="), "\(file.lastPathComponent) builds a host")
            }
            #expect(!found.isEmpty, "\(id) names no address")
            #expect(found.isSubset(of: Set(service.hosts)), "\(id) reaches \(found.subtracting(service.hosts).sorted())")
        }
    }

    @Test func onlyTheAppsOwnCopyIsTakenAtItsWord() {
        let spec = InternetRuleTests.forecast
        let bundled = ExtensionTool(spec: spec, extensionId: "dev.sidefolk.weather", extensionName: "Weather", remoteName: "forecast",
                                    firstParty: true) { _, _ in ToolResult(text: "") }
        let installed = ExtensionTool(spec: spec, extensionId: "dev.sidefolk.weather", extensionName: "Weather", remoteName: "forecast",
                                      firstParty: false) { _, _ in ToolResult(text: "") }
        #expect(bundled.scope(for: .object([:])).reach == .service("Open-Meteo"))
        #expect(installed.scope(for: .object([:])).reach == nil)
    }
}
