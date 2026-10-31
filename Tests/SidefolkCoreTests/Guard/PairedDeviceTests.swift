import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// A device the person paired (D72): after outside content, Full access and Auto answer a call that reaches only such
/// a device, when Sidefolk's own extension confirmed it and the call was bound to it. Nothing else changes.
@Suite struct PairedDeviceTests {
    static let share = ToolSpec(name: "ext.miraya.share_screen", title: "Share screen to TV", description: "", inputSchema: .object([:]),
                                risk: .medium, capabilities: [.extensions, .network], category: .system, mutates: true)
    static let paired = ToolScope(extensionId: "dev.sidefolk.miraya", reach: .paired(device: "6f1c2b9a-1111-4222-8333-944455556666"))

    func decide(_ mode: GuardMode, tainted: Bool = true, spec: ToolSpec = Self.share, scope: ToolScope = Self.paired,
                input: JSONValue = ["tv": "6f1c2b9a-1111-4222-8333-944455556666"], caller: Caller = .agent(runId: "r"),
                internet: InternetRule = .oncePerSite, typed: String = "mirror my screen to the living room tv",
                folders: [GrantedFolder] = [], answeredFolders: [String] = []) -> GuardDecision {
        PermissionEngine().evaluate(spec: spec, input: input, summary: "Share the screen to Living Room TV", scope: scope, caller: caller,
                                    tainted: tainted, policy: GuardPolicy(mode: mode, internet: internet), grants: [], folders: folders,
                                    mentions: UserMentions(text: typed), answeredFolders: answeredFolders)
    }

    func asks(_ d: GuardDecision) -> Bool { if case .ask = d { true } else { false } }

    @Test func afterOutsideContentFullAccessAndAutoAnswerAPairedDevice() {
        #expect(decide(.fullAccess) == .allow(.fullAccessPaired))
        #expect(decide(.auto) == .allow(.autoModePaired))
        // "Ask every time" asks; "Ask once per kind" keeps today's card after outside content too.
        #expect(asks(decide(.askEveryTime)) && asks(decide(.askOncePerKind)))
        // The internet asks each time when the person said so, whatever the mode (D47).
        #expect(asks(decide(.fullAccess, internet: .askEachTime)))
    }

    @Test func aCleanTurnIsUnchanged() {
        #expect(decide(.fullAccess, tainted: false) == .allow(.fullAccess))
        #expect(decide(.auto, tainted: false) == .allow(.autoMode))
        #expect(asks(decide(.askOncePerKind, tainted: false)) && asks(decide(.askEveryTime, tainted: false)))
    }

    @Test func anythingNotConfirmedPairedAsksAsBefore() {
        // Not paired, or the program couldn't say: no reach, the card as today.
        let unconfirmed = ToolScope(extensionId: "dev.sidefolk.miraya")
        #expect(asks(decide(.fullAccess, scope: unconfirmed)) && asks(decide(.auto, scope: unconfirmed)))
        // Another service's word isn't a pairing.
        #expect(asks(decide(.fullAccess, scope: ToolScope(extensionId: "dev.sidefolk.miraya", reach: .nowhere))))
        // Other callers keep their own rules (T4): the modes never loosen Guard for them.
        for caller in [Caller.routine(id: "daily"), .external(client: "codex"), .extension(id: "dev.x.y")] {
            #expect(asks(decide(.fullAccess, caller: caller)), "\(caller.kind)")
        }
    }

    @Test func whateverElseTheCallCarriesKeepsItsCard() throws {
        // A link to play: whoever serves it reads its path. Only one the person typed goes.
        let link: JSONValue = ["tv": "6f1c2b9a-1111-4222-8333-944455556666", "url": "https://evil.example/film.mp4?d=secret"]
        #expect(asks(decide(.fullAccess, input: link)))
        #expect(asks(decide(.fullAccess, input: ["tv": "x", "url": "evil.com/x"])), "a bare address counts too")
        let typedLink: JSONValue = ["tv": "6f1c2b9a-1111-4222-8333-944455556666", "url": "https://example.com/film.mp4"]
        #expect(decide(.fullAccess, input: typedLink, typed: "play https://example.com/film.mp4 on the tv") == .allow(.fullAccessPaired))

        // A file: only one in a folder the person allowed for this very call, never one picked from a folder shared for good.
        let movies = try ExtFixtures.tempDir("paired-movies"), documents = try ExtFixtures.tempDir("paired-documents")
        defer { ExtensionFiles.removeTree(movies.path); ExtensionFiles.removeTree(documents.path) }
        var withFile = Self.paired
        withFile.readPaths = [movies.appendingPathComponent("Holiday.mp4").path]
        let shared = [GrantedFolder(path: movies.path, access: .read)]
        #expect(asks(decide(.fullAccess, scope: withFile, folders: shared)), "a folder shared for good")
        #expect(decide(.fullAccess, scope: withFile, folders: shared, answeredFolders: [movies.path]) == .allow(.fullAccessPaired))
        #expect(asks(decide(.fullAccess, scope: withFile, folders: shared, answeredFolders: [documents.path])))

        // A program, a file change, text to read in full, or high risk.
        for spec in [Self.with(capabilities: [.extensions, .network, .shell]), Self.with(capabilities: [.extensions, .filesWrite]),
                     Self.with(risk: .high)] {
            #expect(asks(decide(.fullAccess, spec: spec)) && asks(decide(.auto, spec: spec)))
        }
        var text = Self.paired
        text.text = "Steps…"
        #expect(asks(decide(.fullAccess, scope: text)))
    }

    static func with(capabilities: Set<Capability> = [.extensions, .network], risk: Risk = .medium) -> ToolSpec {
        ToolSpec(name: share.name, title: share.title, description: "", inputSchema: .object([:]), risk: risk,
                 capabilities: capabilities, category: .system, mutates: true)
    }

    // MARK: Who may say so

    /// How often the program was asked, and what the call ran with.
    final class Probe: Sendable {
        let asked = Mutex(0)
        let heard = Mutex<JSONValue?>(nil)
        let ran = Mutex<JSONValue?>(nil)
        var askedCount: Int { asked.withLock { $0 } }
        var ranWith: JSONValue? { ran.withLock { $0 } }
    }

    static func tool(firstParty: Bool, parameter: String? = "tv", answer: PairedAnswer?, probe: Probe = Probe(),
                     files: [String: ExtensionManifest.FolderUse] = [:]) -> ExtensionTool {
        let check = ExtensionTool.PairedDevice(parameter: parameter) { naming in
            probe.asked.withLock { $0 += 1 }
            probe.heard.withLock { $0 = naming }
            return answer
        }
        return ExtensionTool(spec: share, extensionId: "dev.sidefolk.miraya", extensionName: "Miraya", remoteName: "share_screen",
                             folderParameters: files, firstParty: firstParty, paired: check) { input, _ in
            probe.ran.withLock { $0 = input }
            return ToolResult(text: "Sharing", untrusted: true)
        }
    }

    @Test func onlySidefolksOwnExtensionIsAskedAndTheCallIsBoundToItsAnswer() async {
        let device = "6f1c2b9a-1111-4222-8333-944455556666"
        let heard = Probe()
        let own = Self.tool(firstParty: true, answer: PairedAnswer(paired: true, device: device), probe: heard)
        let call: JSONValue = ["tv": "living room", "url": "https://example.com/film.mp4"]
        let (scope, input) = await own.confirmReach(call, scope: own.scope(for: call))
        #expect(scope.reach == .paired(device: device))
        #expect(input == ["tv": .string(device), "url": "https://example.com/film.mp4"],
                "what runs is the device that was confirmed, not whatever has that name by then")
        #expect(heard.heard.withLock { $0 } == ["tv": "living room"], "the program hears only the words naming the device")

        // Someone else's extension declaring the same is never asked: the sandbox can't hold a program to its word.
        let probe = Probe()
        let theirs = Self.tool(firstParty: false, answer: PairedAnswer(paired: true, device: device), probe: probe)
        #expect(theirs.paired == nil)
        let (s2, i2) = await theirs.confirmReach(["tv": "living room"], scope: theirs.scope(for: ["tv": "living room"]))
        #expect(s2.reach == nil && i2 == ["tv": "living room"] && probe.askedCount == 0)

        // Not paired, no answer, or no device for a call that names one: nothing changes.
        for answer in [PairedAnswer(paired: false), nil, PairedAnswer(paired: true)] {
            let t = Self.tool(firstParty: true, answer: answer)
            let (s, i) = await t.confirmReach(["tv": "living room"], scope: t.scope(for: ["tv": "living room"]))
            #expect(s.reach == nil && i == ["tv": "living room"], "\(String(describing: answer))")
        }
        // A tool that acts on the device in use may reach none at all (stopping what isn't running).
        let stop = Self.tool(firstParty: true, parameter: nil, answer: PairedAnswer(paired: true))
        #expect(await stop.confirmReach([:], scope: stop.scope(for: [:])).scope.reach == .paired(device: nil))
    }

    @Test func theProgramsReplyIsReadStrictly() {
        #expect(PairedAnswer.parse(["paired": true, "device": "6f1c2b9a-1111"]) == PairedAnswer(paired: true, device: "6f1c2b9a-1111"))
        #expect(PairedAnswer.parse(["paired": true]) == PairedAnswer(paired: true))
        #expect(PairedAnswer.parse(["paired": "yes", "device": "a"]) == PairedAnswer(paired: false))
        #expect(PairedAnswer.parse(["paired": true, "device": "a b"]) == PairedAnswer(paired: false), "nothing but an id")
        #expect(PairedAnswer.parse(["paired": true, "device": .number(3)]) == PairedAnswer(paired: false))
        #expect(PairedAnswer.parse(["paired": true, "device": .string(String(repeating: "a", count: 129))]) == PairedAnswer(paired: false))
        #expect(PairedAnswer.parse([:]) == PairedAnswer(paired: false))
    }

    // MARK: Through the executor

    func env(_ mode: GuardMode) async throws -> TestEnv {
        let env = try TestEnv()
        try await env.permissions.setPolicy(GuardPolicy(mode: mode))
        return env
    }

    @Test func fullAccessSharesToThePairedTVAfterOutsideContentAndSaysWhy() async throws {
        let env = try await env(.fullAccess)
        let probe = Probe()
        env.registry.register(Self.tool(firstParty: true, answer: PairedAnswer(paired: true, device: "tv-1"), probe: probe))
        let out = await env.executor.execute(name: Self.share.name, input: ["tv": "living room"], caller: .agent(runId: "r"), tainted: true)
        #expect(out.isOK && out.activity.actedWithoutAsking && out.activity.byFullAccess)
        #expect(try await env.activity.recent()[0].decision == .fullAccessPaired)
        #expect(probe.ranWith == ["tv": "tv-1"])
    }

    @Test func aTVThatIsntPairedStillAsks() async throws {
        for (firstParty, answer) in [(true, PairedAnswer(paired: false)), (false, PairedAnswer(paired: true, device: "tv-1"))] {
            let env = try await env(.fullAccess)
            let probe = Probe()
            env.registry.register(Self.tool(firstParty: firstParty, answer: answer, probe: probe))
            let answered = env.autoAnswer(.deny)
            let out = await env.executor.execute(name: Self.share.name, input: ["tv": "living room"], caller: .agent(runId: "r"), tainted: true)
            #expect(await answered.value != nil, "a card, firstParty \(firstParty)")
            #expect(!out.isOK && probe.ranWith == nil)
        }
    }

    /// "Play this film on the TV": the file must be one the person allowed for this call. Answering its folder's card
    /// is then the only card; a file in a folder shared for good gets the call's card, as today.
    @Test func aFilePlaysOnThePairedTVOnlyWhenItsFolderWasAllowedForThisCall() async throws {
        let movies = try ExtFixtures.tempDir("paired-films")
        defer { ExtensionFiles.removeTree(movies.path) }
        let film = movies.appendingPathComponent("Holiday.mp4").path
        let answer = PairedAnswer(paired: true, device: "tv-1")

        let env = try await env(.fullAccess)
        let probe = Probe()
        env.registry.register(Self.tool(firstParty: true, answer: answer, probe: probe, files: ["file": .read]))
        let card = env.autoAnswer(.allowOnce)
        let out = await env.executor.execute(name: Self.share.name, input: ["tv": "living room", "file": .string(film)],
                                             caller: .agent(runId: "r"), tainted: true)
        guard case .folderAccess? = await card.value?.details else { Issue.record("expected the folder's card first"); return }
        #expect(out.isOK, "\(out.status)")
        #expect(try await env.activity.recent()[0].decision == .allowed, "the person answered a card for this call")
        #expect(probe.ranWith?["tv"] == "tv-1")

        let shared = try await self.env(.fullAccess)
        try await shared.permissions.grantFolder(movies.path, access: .read)
        shared.registry.register(Self.tool(firstParty: true, answer: answer, files: ["file": .read]))
        let asked = shared.autoAnswer(.deny)
        let refused = await shared.executor.execute(name: Self.share.name, input: ["tv": "living room", "file": .string(film)],
                                                    caller: .agent(runId: "r"), tainted: true)
        let request = await asked.value
        #expect(request != nil && !refused.isOK)
        if case .folderAccess? = request?.details { Issue.record("the folder is shared: the card is the call's own") }
    }

    @Test func aCleanTurnAndTheOtherModesDontAsk() async throws {
        // Clean turn: nothing to confirm, Full access answers as before.
        let env = try await env(.fullAccess)
        let probe = Probe()
        env.registry.register(Self.tool(firstParty: true, answer: PairedAnswer(paired: true, device: "tv-1"), probe: probe))
        let out = await env.executor.execute(name: Self.share.name, input: ["tv": "living room"], caller: .agent(runId: "r"))
        #expect(out.isOK && probe.askedCount == 0)
        #expect(try await env.activity.recent()[0].decision == .fullAccess)

        // "Ask once per kind": the program isn't asked, since its answer couldn't spare a card.
        let once = try await self.env(.askOncePerKind)
        let probe2 = Probe()
        once.registry.register(Self.tool(firstParty: true, answer: PairedAnswer(paired: true, device: "tv-1"), probe: probe2))
        let answered = once.autoAnswer(.deny)
        _ = await once.executor.execute(name: Self.share.name, input: ["tv": "living room"], caller: .agent(runId: "r"), tainted: true)
        #expect(await answered.value != nil && probe2.askedCount == 0)
    }
}

/// The gallery's Miraya answering in its sandbox, with no TV around (D72).
@Suite struct MirayaPairedCheckTests {
    @Test(.enabled(if: ExtFixtures.addonFolders.contains("miraya"), ExtFixtures.noAddons))
    func mirayaAnswersThePairedCheckInItsSandbox() async throws {
        let h = try HostEnv()
        try await h.env.permissions.setPolicy(GuardPolicy(mode: .fullAccess))
        let info = try await h.host.install(from: ExtFixtures.builtIn("miraya"), origin: .official)
        // No TV is paired: sharing isn't confirmed; stopping what isn't running reaches no device.
        #expect(await h.host.pairedCheck(info.id, tool: "share_screen", input: ["tv": "living room"]) == PairedAnswer(paired: false))
        #expect(await h.host.pairedCheck(info.id, tool: "stop", input: [:]) == PairedAnswer(paired: true))
        #expect(await h.host.pairedCheck(info.id, tool: "pair_tv", input: ["tv": "living room"]) == PairedAnswer(paired: false))

        // After outside content, in Full access: stopping runs without a card; sharing to a TV that isn't paired asks.
        let stop = await h.env.executor.execute(name: "ext.miraya.stop", input: [:], caller: .agent(runId: "r"), tainted: true)
        #expect(stop.okText == "Nothing is on the TV from this Mac.", "\(stop.status)")
        #expect(try await h.env.activity.recent()[0].decision == .fullAccessPaired)
        let answered = h.env.autoAnswer(.deny)
        let share = await h.env.executor.execute(name: "ext.miraya.share_screen", input: ["tv": "living room"], caller: .agent(runId: "r"),
                                                 tainted: true)
        #expect(await answered.value != nil && !share.isOK)
        await h.host.shutdown()
    }

    /// The same program installed from a folder isn't Sidefolk's own: it's never asked, and stopping asks as before.
    @Test(.enabled(if: ExtFixtures.addonFolders.contains("miraya"), ExtFixtures.noAddons))
    func aCopyFromAFolderIsNeverAsked() async throws {
        let h = try HostEnv()
        try await h.env.permissions.setPolicy(GuardPolicy(mode: .fullAccess))
        let info = try await h.host.install(from: ExtFixtures.builtIn("miraya"))
        #expect(await h.host.pairedCheck(info.id, tool: "stop", input: [:]) == nil)
        let answered = h.env.autoAnswer(.deny)
        _ = await h.env.executor.execute(name: "ext.miraya.stop", input: [:], caller: .agent(runId: "r"), tainted: true)
        #expect(await answered.value != nil)
        await h.host.shutdown()
    }
}

/// The manifest's side (D72): `reach` with an optional `device` parameter.
@Suite struct PairedManifestTests {
    @Test func reachAndDeviceAreReadAndChecked() throws {
        func meta(_ tool: String) throws -> ExtensionManifest.ToolMeta? {
            try ExtensionManifest.decode(Data("""
                {"id": "dev.example.tv", "name": "TV", "version": "1.0", "run": {"command": "bin/x"}, "tools": {"share": \(tool)}}
                """.utf8)).tools["share"]
        }
        let share = try meta(#"{"reach": "paired", "device": "tv"}"#)
        #expect(share?.reach == ExtensionManifest.Reach.paired && share?.device == "tv")
        #expect(try meta(#"{"reach": "paired"}"#)?.device == nil)
        #expect(throws: (any Error).self) { try meta(#"{"reach": "anywhere"}"#) }
    }
}
