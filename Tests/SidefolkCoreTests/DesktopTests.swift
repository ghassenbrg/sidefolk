import Foundation
import Testing
@testable import SidefolkCore

/// The desktop of D84: the light at the companion's feet, the agents lane, what the Say bar understood and the
/// permission slip's tone.
@Suite struct DesktopTests {
    let now = TimeTest.wednesday10
    let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")

    // MARK: Light

    @Test func theLightSaysWhatMattersMost() {
        #expect(DesktopLight.of(pose: .idle, waiting: 0, cardOut: false, quiet: false) == .idle)
        #expect(DesktopLight.of(pose: .working(.notes), waiting: 0, cardOut: false, quiet: false) == .working)
        #expect(DesktopLight.of(pose: .thinking, waiting: 0, cardOut: false, quiet: false) == .working)
        #expect(DesktopLight.of(pose: .hearing, waiting: 0, cardOut: false, quiet: false) == .working)
        // Waiting outranks working: what needs the person shows over what runs for them.
        #expect(DesktopLight.of(pose: .working(.web), waiting: 3, cardOut: false, quiet: false) == .waiting(3))
        #expect(DesktopLight.of(pose: .alert, waiting: 1, cardOut: true, quiet: false) == .alert(1))
        #expect(DesktopLight.of(pose: .error, waiting: 2, cardOut: false, quiet: false) == .failed)
        // Quiet: no light at all, whatever happens; the count is kept for the shoulder and VoiceOver.
        #expect(DesktopLight.of(pose: .alert, waiting: 2, cardOut: true, quiet: true) == .quiet(2))
        #expect(DesktopLight.quiet(2).count == 2 && DesktopLight.working.count == 0)
        // Focus: dim, and the shoulder counts what waits with the whispers it holds.
        #expect(DesktopLight.of(pose: .working(.web), waiting: 1, cardOut: false, quiet: false, focus: true, held: 2) == .focus(3))
        #expect(DesktopLight.of(pose: .idle, waiting: 1, cardOut: false, quiet: true, focus: true) == .quiet(1))
    }

    @Test func anAlertWhoseCardFoldedIsNoLongerLit() {
        #expect(DesktopLight.of(pose: .alert, waiting: 0, cardOut: false, quiet: false) == .idle)
    }

    // MARK: Agents lane

    @Test func theLaneShowsLiveSessionsWaitingOnesFirst() {
        var codex = AgentSession(id: "a", agent: "codex", cwd: "/Users/me/git/pockito", state: .working, now: now.addingTimeInterval(-840))
        codex.updatedAt = now
        let claude = AgentSession(id: "b", agent: "claude-code", cwd: "/Users/me/git/sidefolk", state: .needsYou, now: now)
        let idle = AgentSession(id: "c", agent: "codex", cwd: "/tmp/x", state: .idle, now: now)
        var ended = AgentSession(id: "d", agent: "codex", cwd: "/tmp/y", state: .working, now: now)
        ended.endedAt = now
        let chips = AgentLane.chips([codex, idle, claude, ended])
        #expect(chips.map(\.id) == ["b", "a"])
        #expect(chips[0].agent == "Claude Code" && chips[0].needsYou && chips[0].project == "sidefolk")
        #expect(chips[1].agent == "Codex" && !chips[1].needsYou && chips[1].since == now.addingTimeInterval(-840))
    }

    @Test func theLaneKeepsToThree() {
        let many = (0..<5).map { AgentSession(id: "s\($0)", agent: "codex", cwd: nil, state: .working, now: now) }
        #expect(AgentLane.chips(many).count == AgentLane.shown)
    }

    // MARK: Understanding

    func understood(_ text: String) -> Understanding? {
        parser.parse(text, now: now, knownCollections: ["Groceries"])?.understanding(now: now, calendar: TimeTest.calendar())
    }

    @Test func aReminderSaysWhatAndWhenWithoutAI() throws {
        let u = try #require(understood("remind me tomorrow at 5 to call the bank"))
        #expect(u.local)
        #expect(u.sentence == "I'll remind you: “Call the bank”.")
        #expect(u.chips.map(\.text) == ["Reminder", "Tomorrow", "17:00", "On this Mac, no AI"])
        #expect(u.chips.first?.role == .kind && u.chips.last?.role == .local)
    }

    @Test func aWatchNamesThePageWithoutItsScheme() throws {
        let u = try #require(understood("tell me when example.com/pricing changes"))
        #expect(u.sentence == "I'll check example.com/pricing and tell you when it changes.")
        #expect(u.chips.contains { $0.text == "example.com/pricing" && $0.role == .detail })
    }

    @Test func aNoteSaysWhereItGoes() throws {
        let u = try #require(understood("add milk to groceries"))
        // Groceries is a list: what goes in it is a task to tick off.
        #expect(u.sentence == "I'll add this task to Groceries.")
        #expect(try #require(understood("note: folks could have their own voice")).sentence == "I'll save this to Inbox.")
    }

    @Test func wordsForTheAISayWhoAnswers() {
        let u = Understanding.ai("Claude")
        #expect(!u.local && u.sentence == "I'll ask Claude.")
        #expect(u.chips.map(\.role) == [.kind, .ai])
    }

    // MARK: Permission slip

    func request(_ caller: Caller, risk: Risk = .medium, tainted: Bool = false) -> ApprovalRequest {
        ApprovalRequest(tool: "files.move", title: "Move 12 PDFs", summary: "s", risk: risk, caller: caller, details: .none, canAlways: true,
                        tainted: tainted, effect: .changesFiles)
    }

    @Test func calmSlipsTakeReturnFirmOnesNeverDo() {
        let mine = request(.agent(runId: "r"))
        #expect(mine.slipTone == .calm && mine.takesReturn)
        // High risk is calm in tone but still needs ⌘Return.
        #expect(request(.user, risk: .high).slipTone == .calm && !request(.user, risk: .high).takesReturn)
        // Another app, outside content first, an extension nobody checked: firm, never Return.
        let other = request(.external(client: "codex"))
        #expect(other.slipTone == .firm && !other.takesReturn)
        let afterWeb = request(.agent(runId: "r"), tainted: true)
        #expect(afterWeb.slipTone == .firm && !afterWeb.takesReturn)
        var unchecked = request(.extension(id: "local.x"))
        unchecked.firstParty = false
        #expect(unchecked.slipTone == .firm)
        // Sidefolk's own extension is calm, but it isn't the person's own words: ⌘Return, not Return.
        let own = request(.extension(id: "dev.sidefolk.weather"))
        #expect(own.slipTone == .calm && !own.takesReturn)
    }

    /// A pin at rest shows its number and unit, never a value cut short (the tip has the rest).
    @Test func aPinAtRestKeepsItsNumberAndUnit() {
        #expect(PinValue.atRest("17.15 GB of 24 GB") == "17.15 GB")
        #expect(PinValue.atRest("19%") == "19%")
        #expect(PinValue.atRest("18.1° and cloudy") == "18.1°")
        #expect(PinValue.atRest("-3 °C") == "-3 °C")
        #expect(PinValue.atRest("1,204 km/h winds") == "1,204 km/h")
        #expect(PinValue.atRest("Partly cloudy") == "Partly cloudy")
        #expect(PinValue.atRest("2 things waiting") == "2", "a word isn't a unit")
    }
}
