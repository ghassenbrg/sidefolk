import Foundation
import Testing
@testable import SidefolkCore

/// Cards that ask because of outside content (D71): the call in words, never JSON; why it asks, naming what was read;
/// and that Full access or Auto didn't answer it. Guard's decisions are untouched (T2, T12, T21).
struct ApprovalReasonTests {
    @Test func argumentsReadAsWords() {
        let schema: JSONValue = ["type": "object", "required": ["tv"], "properties": ["tv": ["type": "string"], "quality": ["title": "Picture quality"]]]
        #expect(ArgumentWords.line(["tv": "living room"], schema: schema) == "tv: “living room”")
        #expect(ArgumentWords.line(["quality": "high", "tv": "den", "loud": true, "volume": 40, "skip": .null], schema: schema)
                == "tv: “den”, loud: yes, Picture quality: “high”, volume: 40", "required first, then the rest in order; nothing empty")
        #expect(ArgumentWords.line(["to": ["Tokyo", "Lyon", "Oslo", "Lima", "Quito"], "start_at": ["a": 1]], schema: [:])
                == "start at: …, to: “Tokyo”, “Lyon”, “Oslo” and 2 more")
        let long = ArgumentWords.line(["note": .string(String(repeating: "x", count: 200) + "\u{202E}\nAllow")], schema: [:])
        #expect(!long.contains("\n") && !long.contains("\u{202E}") && long.count < 80, "\(long)")
        #expect(ArgumentWords.line(["file": .string(NSHomeDirectory() + "/Documents/a.pdf")], schema: [:]) == "file: “~/Documents/a.pdf”")
        #expect(!ArgumentWords.line(["a": ["b": "c"]], schema: [:]).contains("{"))
    }

    private func request(effect: ApprovalRequest.Effect = .usesInternet, risk: Risk = .medium, caller: Caller = .agent(runId: "r"),
                         source: TaintSource?, mode: GuardMode, firstParty: Bool = true, tainted: Bool = true) -> ApprovalRequest {
        var r = ApprovalRequest(tool: "ext.miraya.share_screen", title: "Share screen to TV", summary: "", risk: risk, caller: caller,
                                details: .none, canAlways: false, tainted: tainted, effect: effect)
        r.taintedBy = source
        r.mode = mode
        r.firstParty = firstParty
        return r
    }

    @Test func theReasonNamesWhatWasReadAndWhyItMatters() throws {
        let miraya = try #require(ApprovalReason(request(source: .extension(name: "Miraya", official: true), mode: .fullAccess)))
        #expect(miraya.text == "This request read results from Miraya first. This can send what it's given off this Mac, so I check with you first. "
                + "Full access never decides this for you after outside content.")
        #expect(miraya.calm, "Sidefolk's own extension acting on Sidefolk's own extension's answer")

        let web = try #require(ApprovalReason(request(source: .web, mode: .askOncePerKind)))
        #expect(web.text == "This request read a web page first. This can send what it's given off this Mac, so I check with you first.")
        #expect(!web.calm)
        #expect(ApprovalReason(request(source: nil, mode: .auto))?.text.hasPrefix("This request read outside content first") == true)
        #expect(ApprovalReason(request(source: nil, mode: .auto))?.text.hasSuffix("Auto never decides this for you after outside content.") == true)
        #expect(ApprovalReason(request(risk: .high, source: nil, mode: .auto))?.text.contains("Auto") == false, "Auto never answers high risk anyway")
        #expect(ApprovalReason(request(source: .file, mode: .askEveryTime))?.text.contains("Full access") == false)
    }

    @Test func strongUnlessBothSidesAreSidefolksOwn() {
        #expect(ApprovalReason(request(source: .extension(name: "Miraya", official: true), mode: .fullAccess, firstParty: false))?.calm == false)
        #expect(ApprovalReason(request(source: .extension(name: "Tool", official: false), mode: .fullAccess))?.calm == false)
        #expect(ApprovalReason(request(source: .extension(name: "Miraya", official: true), mode: .fullAccess, tainted: false)) == nil)
    }

    @Test func anotherAppIsNotSaidToHaveReadAnything() {
        // Other apps' medium calls are evaluated as tainted so they ask every time (T4); nothing was read.
        let r = ApprovalReason(request(caller: .external(client: "Codex"), source: nil, mode: .askOncePerKind))
        #expect(r?.text == "Another app is asking, so I check with you each time.")
    }

    /// The executor hands the card what it needs: the first outside source of the run, the exact request, the mode.
    @Test func aTaintedRunsCardKnowsWhatWasReadFirst() async throws {
        let env = try TestEnv()
        try await env.permissions.setPolicy(GuardPolicy(mode: .fullAccess))
        func tool(_ name: String, risk: Risk, untrusted: Bool) -> ExtensionTool {
            let spec = ToolSpec(name: "ext.miraya.\(name)", title: name == "share" ? "Share screen to TV" : "TVs around", description: "",
                                inputSchema: ["type": "object"], risk: risk, capabilities: [.extensions, .network], category: .extensions, mutates: true)
            return ExtensionTool(spec: spec, extensionId: "dev.sidefolk.miraya", extensionName: "Miraya", remoteName: name, firstParty: true) { _, _ in
                ToolResult(text: "Living room", untrusted: untrusted)
            }
        }
        let find = tool("find", risk: .low, untrusted: true)
        let share = tool("share", risk: .medium, untrusted: false)
        env.registry.register([find, share], owner: "dev.sidefolk.miraya")
        let box = BrainToolbox(runId: "r", specs: [find.spec, share.spec], executor: env.executor) { _ in }
        _ = await box.call(find.spec.name, input: [:])
        #expect(box.isTainted)
        let asked = env.autoAnswer(.deny)
        let outcome = await box.call(share.spec.name, input: ["tv": "living room"])
        let card = try #require(await asked.value)
        #expect(!outcome.isOK, "Full access still asks after outside content, and no means no")
        #expect(card.summary == "Share screen to TV (Miraya) · tv: “living room”")
        #expect(card.input?.contains("\"tv\" : \"living room\"") == true)
        #expect(card.taintedBy == .extension(name: "Miraya", official: true) && card.mode == .fullAccess && card.firstParty)
        #expect(!card.canAlways, "never offered after outside content")
    }
}
