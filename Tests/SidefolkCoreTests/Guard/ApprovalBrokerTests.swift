import Foundation
import Testing
@testable import SidefolkCore

/// A waiting approval says when it stops waiting (D58), the same everywhere it's shown: the event that shows the
/// card, the broker's list Home reads, and nothing once it's answered.
@Suite struct ApprovalBrokerTests {
    @Test func aWaitingRequestKnowsWhenItStops() async throws {
        let events = EventBus()
        let broker = ApprovalBroker(events: events)
        let stream = events.stream()
        let request = ApprovalRequest(tool: "files.move", title: "Move 12 PDFs", summary: "From Downloads to Invoices", risk: .medium,
                                      caller: .agent(runId: "r1"), details: .none, canAlways: true)

        let before = Date()
        let answer = Task { await broker.request(request, timeout: 600) }
        var shown: ApprovalRequest?
        for await event in stream {
            if case .approvalRequested(let r) = event { shown = r; break }
        }
        let waiting = try #require(await broker.pending().first)
        let expires = try #require(waiting.expiresAt)
        #expect(shown?.expiresAt == expires)
        #expect(expires >= before.addingTimeInterval(600) && expires <= Date().addingTimeInterval(600))

        await broker.resolve(id: waiting.id, decision: .allowOnce)
        #expect(await answer.value == .allowOnce)
        #expect(await broker.pending().isEmpty)
    }

    /// A stray Return never says yes for another app, before the card settles, or to high risk without ⌘.
    @Test func whenAKeyMaySayYes() {
        func request(_ caller: Caller, _ risk: Risk) -> ApprovalRequest {
            ApprovalRequest(tool: "t", title: "T", summary: "S", risk: risk, caller: caller, details: .none, canAlways: false)
        }
        let mine = request(.agent(runId: "r"), .medium)
        #expect(mine.mayApproveFromKeys(armed: true, command: false))
        #expect(!mine.mayApproveFromKeys(armed: false, command: false))

        let risky = request(.user, .high)
        #expect(!risky.mayApproveFromKeys(armed: true, command: false))
        #expect(risky.mayApproveFromKeys(armed: true, command: true))

        for other in [Caller.external(client: "codex"), .extension(id: "dev.sidefolk.git"), .routine(id: "brief")] {
            #expect(!request(other, .low).mayApproveFromKeys(armed: true, command: true))
        }
        #expect(request(.command(extensionId: "dev.sidefolk.currency"), .low).mayApproveFromKeys(armed: true, command: false))
    }
}
