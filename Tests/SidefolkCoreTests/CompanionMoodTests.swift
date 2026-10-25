import Foundation
import Testing
@testable import SidefolkCore

@Suite struct CompanionMoodTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func activity(_ id: String, _ category: ToolCategory = .notes) -> ToolActivity {
        ToolActivity(id: id, tool: "t", title: "T", summary: "", category: category, caller: .user)
    }

    @Test func idleByDefaultAndSleepsWhenAsked() {
        var m = CompanionMood()
        #expect(m.pose(at: now) == .idle)
        m.asleep = true
        #expect(m.pose(at: now) == .sleeping)
        m.panelOpen = true
        #expect(m.pose(at: now) == .listening)
    }

    @Test func workingShowsCategoryThenBriefSuccess() {
        var m = CompanionMood()
        m.apply(.toolStarted(activity("a", .time)), now: now)
        #expect(m.pose(at: now) == .working(.time))
        m.apply(.toolFinished(activity("a", .time), ok: true), now: now)
        #expect(m.pose(at: now) == .success)
        #expect(m.pose(at: now.addingTimeInterval(CompanionMood.successHold + 0.1)) == .idle)
        #expect(m.nextChange(after: now) != nil)
    }

    @Test func failureShowsError() {
        var m = CompanionMood()
        m.apply(.toolStarted(activity("a")), now: now)
        m.apply(.toolFinished(activity("a"), ok: false), now: now)
        #expect(m.pose(at: now) == .error)
    }

    @Test func priorityOrder() {
        var m = CompanionMood()
        m.apply(.agent(threadId: "t", .started(runId: "r", provider: "p", model: "m")), now: now)
        #expect(m.pose(at: now) == .thinking)
        m.apply(.toolStarted(activity("a", .web)), now: now)
        #expect(m.pose(at: now) == .working(.web))
        let item = AttentionItem(level: .attention, source: "reminder", title: "x")
        m.apply(.attention(.present(item, .attention(expandFor: 30))), now: now)
        #expect(m.pose(at: now) == .alert)
        let req = ApprovalRequest(tool: "t", title: "T", summary: "s", risk: .medium, caller: .agent(runId: "r"), details: .none, canAlways: true)
        m.apply(.approvalRequested(req), now: now)
        #expect(m.pose(at: now) == .waiting)
        m.dragging = true
        #expect(m.pose(at: now) == .dragging)
        m.dragging = false
        m.apply(.approvalResolved(id: req.id, decision: .allowOnce), now: now)
        m.apply(.attention(.withdraw(id: item.id)), now: now)
        #expect(m.pose(at: now) == .working(.web))
    }

    @Test func gentleNoticesDoNotAlert() {
        var m = CompanionMood()
        let item = AttentionItem(level: .gentle, source: "x", title: "x")
        m.apply(.attention(.present(item, .gentle(autoDismiss: 6))), now: now)
        #expect(m.pose(at: now) == .idle)
    }

    @Test func dutyRosterOrderAndLimit() {
        #expect(DutyRoster().onDuty.isEmpty)
        #expect(DutyRoster(reminderDueSoon: true, activeWatchers: 2, liveAgentWork: 1).onDuty == [.tempo, .scout, .byte])
        #expect(DutyRoster(activeWatchers: 1).onDuty == [.scout])
    }
}
