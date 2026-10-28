import Foundation
import Testing
@testable import SidefolkCore

/// Extensions whose author decides what answers at once, without the AI (D50): sentences with typed slots, matched
/// whole after every core intent, refused when they could swallow what people say, and run through Guard.
@Suite struct ExtensionCommandTests {
    static func sentence(_ text: String, words: [String: [String]] = [:]) throws -> CommandSentence {
        try CommandSentence(text, words: words)
    }

    static func problem(_ text: String, words: [String: [String]] = [:]) -> String? {
        do { _ = try CommandSentence(text, words: words); return nil } catch { return error.message }
    }

    // MARK: Sentences and slots

    @Test func aSentenceMatchesWholeInAnyCaseAndSpacing() throws {
        let s = try Self.sentence("time in {place:place}")
        #expect(s.match("Time in Tokyo") == ["place": "Tokyo"])
        #expect(s.match("time   in  New York") == ["place": "New York"])
        #expect(s.shown == "time in …")
        #expect(s.match("the time in Tokyo") == nil)
        #expect(s.match("time in") == nil)
        #expect(s.match("time in Tokyo and tell me a joke about it right now please") == nil, "a place is six words at most")
        #expect(s.match("time in 42") == nil)
    }

    @Test func expressionsAreSumsNotDatesOrPhoneNumbers() throws {
        let s = try Self.sentence("{sum:expression}")
        #expect(s.match("2+2*3") == ["sum": "2+2*3"])
        #expect(s.match("15% of 80") == ["sum": "15% of 80"])
        #expect(s.match("sqrt(2) * pi") == ["sum": "sqrt(2) * pi"])
        for notASum in ["2026-10-28", "10/28/2026", "555-1234", "1-800-555-1234", "2026", "hello", "2 apples + 3 pears", "10.2.3"] {
            #expect(s.match(notASum) == nil, "\(notASum)")
        }
    }

    @Test func numbersListsDatesAndAddressesComeTyped() throws {
        let n = try Self.sentence("round {value:number}")
        #expect(n.match("round 1,000.5") == ["value": .number(1000.5)])
        #expect(n.match("round -3") == ["value": .number(-3)])
        let i = try Self.sentence("roll {count:integer} times")
        #expect(i.match("roll 3 times") == ["count": .number(3)])
        #expect(i.match("roll 2.5 times") == nil)
        let list = try Self.sentence("pick one: {choices:list}")
        #expect(list.match("pick one: tea, coffee or juice") == ["choices": ["tea", "coffee", "juice"]])
        #expect(list.match("pick one:tea or coffee") == ["choices": ["tea", "coffee"]])
        #expect(list.match("pick one: tea") == nil, "a list is two things or more")
        let date = try Self.sentence("days until {day:date}")
        #expect(date.match("days until 25 December") == ["day": "25 December"])
        #expect(date.match("days until 2026-12-25") == ["day": "2026-12-25"])
        #expect(date.match("days until christmas") == nil, "a day only the AI can read is the AI's")
        let url = try Self.sentence("qr code for {link:url}")
        #expect(url.match("qr code for example.com/a") == ["link": "https://example.com/a"])
        #expect(url.match("qr code for nothing") == nil)
    }

    @Test func anExtensionsOwnWordsMakeASlot() throws {
        let words = ["unit": ["km", "miles", "fl oz", "in"]]
        let s = try Self.sentence("{value:number} {from:unit} in {to:unit}", words: words)
        #expect(s.match("5 km in miles") == ["value": 5, "from": "km", "to": "miles"])
        #expect(s.match("2 fl  oz in in") == ["value": 2, "from": "fl oz", "to": "in"])
        #expect(s.match("5 kg in miles") == nil)
        let glued = try Self.sentence("{value:number}{from:unit} to {to:unit}", words: words)
        #expect(glued.match("5km to miles") == ["value": 5, "from": "km", "to": "miles"])
    }

    @Test func sentencesThatCouldSwallowWordsAreRefused() {
        #expect(Self.problem("{anything}")?.contains("word of its own") == true)
        #expect(Self.problem("{anything} please")?.contains("can't start with {anything}") == true)
        #expect(Self.problem("{n:number} please") == nil, "a number can start a sentence")
        #expect(Self.problem("tell {who} {what}")?.contains("needs a word between") == true)
        #expect(Self.problem("yes")?.contains("reply anyone might type") == true)
        #expect(Self.problem("thank you")?.contains("reply") == true)
        #expect(Self.problem("convert {a:number} {b:number} {c:number} {d:number}")?.contains("at most 3 slots") == true)
        #expect(Self.problem("time in {place:city}")?.contains("doesn't know") == true)
        #expect(Self.problem("time in {Place}")?.contains("lowercase") == true)
        #expect(Self.problem("time in {place")?.contains("without its") == true)
        #expect(Self.problem("time in place}")?.contains("without its") == true)
        #expect(Self.problem("say {a} and {a}")?.contains("twice") == true)
        #expect(Self.problem(String(repeating: "a", count: 81))?.contains("1–80") == true)
    }

    // MARK: The manifest's rules

    static func manifest(_ tools: [String: ExtensionManifest.ToolMeta], words: [String: [String]] = [:]) -> ExtensionManifest {
        ExtensionManifest(id: "dev.test.sample", name: "Sample", version: "1.0.0", run: .init(command: "bin/x"), tools: tools, words: words)
    }

    @Test func theValidatorNamesEachMistake() {
        func issues(_ meta: ExtensionManifest.ToolMeta, words: [String: [String]] = [:]) -> [String] {
            ExtensionCommandRules.check(Self.manifest(["t": meta], words: words)).map(\.description)
        }
        #expect(issues(.init(ai: false)).contains { $0.contains("tools.t.ai") && $0.contains("nothing can reach it") })
        #expect(issues(.init(commands: [.init(say: ["time in {place:place}", "clock {zone:word}"])]))
            .contains { $0.contains("same slots in every sentence") })
        #expect(issues(.init(commands: [.init(say: ["time in {place:place}"], input: ["places": ["{city}"]])]))
            .contains { $0.contains("names {city}, which no sentence has") })
        #expect(issues(.init(commands: [.init(say: ["time in {place:place}"], input: ["zone": "UTC"])]))
            .contains { $0.contains("doesn't use {place}") })
        #expect(issues(.init(commands: [.init(say: ["time in {place:place}"], input: ["places": "in {place}"])]))
            .contains { $0.contains("whole slot") })
        #expect(issues(.init(commands: [.init(say: ["uuid", "UUID!"])])).contains { $0.contains("says the same as") })
        #expect(issues(.init(commands: [.init(say: ["uuid"])]), words: ["text": ["a"]]).contains { $0.contains("words.text") })
        #expect(issues(.init(commands: [.init(say: ["uuid"])]), words: ["unit": [" km"]]).contains { $0.contains("words.unit[0]") })
        #expect(issues(.init(commands: [.init(say: ["time in {place:place}"], input: ["places": ["{place}"]])])).isEmpty)
    }

    @Test func everyShippedManifestsCommandsAreValid() throws {
        for folder in ExtFixtures.builtInFolders {
            let data = try Data(contentsOf: ExtFixtures.repoRoot.appendingPathComponent("extensions/\(folder)/sidefolk-extension.json"))
            let manifest = try ExtensionManifest.decode(data)
            #expect(ExtensionCommandRules.check(manifest).isEmpty, "\(folder): \(ExtensionCommandRules.check(manifest))")
        }
    }

    @Test func theInputPutsAListWhereTheArrayIs() {
        let built = ToolCommands.build(["kind": "pick", "choices": ["{choices}"], "count": 1], ["choices": ["a", "b"]])
        #expect(built == ["kind": "pick", "choices": ["a", "b"], "count": 1])
        #expect(ToolCommands.build(nil, ["place": "Tokyo"]) == ["place": "Tokyo"])
    }

    // MARK: Matching among extensions

    static func tool(_ ext: String, _ name: String, _ say: [String], input: [String: JSONValue]? = nil, words: [String: [String]] = [:],
                     schema: JSONValue = .object([:]), ai: Bool = true) -> ExtensionTool {
        let spec = ToolSpec(name: "ext.\(ext).\(name)", title: name, description: "", inputSchema: schema, risk: .low,
                            capabilities: [.extensions], category: .extensions, mutates: false, offeredToModel: ai)
        return ExtensionTool(spec: spec, extensionId: "dev.test.\(ext)", extensionName: ext.capitalized, remoteName: name,
                             commands: ToolCommands([.init(say: say, input: input)], words: words)) { _, _ in ToolResult(text: "ok") }
    }

    static func parser(_ tools: [ExtensionTool]) -> IntentParser {
        IntentParser(when: TimeTest.parser(), home: "/Users/test", commandTools: tools)
    }

    @Test func aCommandRunsWithItsInputAndSaysSoBeforeEnter() throws {
        let clock = Self.tool("clock", "now", ["time in {place:place}"], input: ["places": ["{place}"]])
        let parsed = try #require(Self.parser([clock]).parse("Please, time in Fukuoka?", now: TimeTest.wednesday10))
        guard case .extensionCommand(let call) = parsed.intent else { Issue.record("\(parsed.intent)"); return }
        #expect(call.tool == "ext.clock.now" && call.extensionId == "dev.test.clock")
        #expect(call.input == ["places": ["Fukuoka"]])
        #expect(parsed.hint.hasPrefix("Clock · now") && parsed.hint.hasSuffix("no AI"), "\(parsed.hint)")
    }

    @Test func coreIntentsComeFirst() throws {
        let greedy = Self.tool("greedy", "remind", ["remind me {what}"])
        let parsed = try #require(Self.parser([greedy]).parse("remind me at 5pm to stretch", now: TimeTest.wednesday10))
        guard case .remind = parsed.intent else { Issue.record("core lost to an extension: \(parsed.intent)"); return }
    }

    @Test func twoExtensionsClaimingOneSentenceLeaveItToTheAI() {
        let a = Self.tool("one", "time", ["time in {place:place}"])
        let b = Self.tool("two", "time", ["time in {place:place}"])
        #expect(Self.parser([a, b]).parse("time in Tokyo", now: TimeTest.wednesday10) == nil)
        // Within one extension the first tool by name answers.
        let c = Self.tool("one", "zone", ["time in {place:place}"])
        guard case .extensionCommand(let call)? = Self.parser([c, a]).parse("time in Tokyo", now: TimeTest.wednesday10)?.intent else {
            Issue.record("expected a command"); return
        }
        #expect(call.tool == "ext.one.time")
    }

    @Test func aNumberBecomesTextWhereTheToolWantsText() throws {
        let schema: JSONValue = ["type": "object", "properties": ["value": ["type": "string"], "count": ["type": "integer"]]]
        let stamp = Self.tool("dev", "timestamp", ["timestamp {value:integer}"], schema: schema)
        guard case .extensionCommand(let call)? = Self.parser([stamp]).parse("timestamp 1730000000", now: TimeTest.wednesday10)?.intent else {
            Issue.record("expected a command"); return
        }
        #expect(call.input == ["value": "1730000000"])
    }

    // MARK: Guard

    static func decide(_ spec: ToolSpec, rule: InternetRule = .oncePerSite, grants: [Grant] = []) -> GuardDecision {
        PermissionEngine().evaluate(spec: spec, input: .object([:]), summary: "s", scope: ToolScope(extensionId: "dev.test.poster"),
                                    caller: .command(extensionId: "dev.test.poster"), tainted: false,
                                    policy: GuardPolicy(mode: .askOncePerKind, internet: rule), grants: grants, folders: [],
                                    mentions: UserMentions(text: "post hello"))
    }

    static let plain = ToolSpec(name: "ext.poster.count", title: "Count", description: "", inputSchema: .object([:]), risk: .low,
                                capabilities: [.extensions], category: .extensions, mutates: false)
    static let online = ToolSpec(name: "ext.poster.post", title: "Post", description: "", inputSchema: .object([:]), risk: .medium,
                                 capabilities: [.extensions, .network], category: .extensions, mutates: true)

    @Test func aCommandIsNeverAFreePassForTheExtension() {
        #expect(Self.decide(Self.plain) == .allow(.auto), "nothing leaves the Mac: no card")
        guard case .ask(let card) = Self.decide(Self.online) else { Issue.record("a network extension must ask"); return }
        #expect(card.canAlways)
        // "Always allow" given to Sidefolk's AI covers the typed command too, and the other way round.
        let grant = Grant(tool: "ext.poster.post", scope: ["extension": "dev.test.poster"], callerKind: "agent")
        #expect(Self.decide(Self.online, grants: [grant]) == .allow(.always))
        #expect(Caller.command(extensionId: "x").grantKind == "agent")
        // The person's "Ask each time" holds for commands as for the AI.
        guard case .ask = Self.decide(Self.online, rule: .askEachTime, grants: [grant]) else { Issue.record("must ask each time"); return }
    }

    @Test func aCommandCantBuildExtensionsOrWriteSkills() {
        let context = ToolContext(caller: .command(extensionId: "dev.test.x"), now: Date())
        #expect(ExtensionBuilderTools.refusal(context) != nil)
        #expect(ToolContext(caller: .command(extensionId: "dev.test.x"), now: Date()).provenanceTag == "command:dev.test.x")
    }

    // MARK: The model

    @Test func aToolLeftToCommandsNeverReachesTheModel() async throws {
        let w = try await World([])
        w.env.registry.register(Self.tool("coin", "flip", ["flip a coin"], ai: false), owner: "dev.test.coin")
        w.env.registry.register(Self.tool("clock", "now", ["time in {place:place}"]), owner: "dev.test.clock")
        let sent = await w.runtime.preview(AgentRequest(text: "hello"))
        #expect(!sent.tools.contains("ext_coin_flip"))
        #expect(sent.tools.contains("ext_clock_now"))
    }
}
