import Foundation
import Testing
@testable import SidefolkCore

/// Home's places in the Lantern revamp (D84): History's one timeline, On duty's counts and Today's brief.
struct HomePlacesTests {
    let now = TestEnv.referenceDate

    private func entry(_ id: Int64, _ caller: String, minutesAgo: Double, _ summary: String = "Saved a note") -> ActivityEntry {
        var e = ActivityEntry(at: now.addingTimeInterval(-minutesAgo * 60), caller: caller, tool: "notes.save", risk: "low",
                              decision: .auto, summary: summary)
        e.id = id
        return e
    }

    @Test func anAgentsCallsDuringItsSessionBecomeItsReceipt() {
        var session = AgentSession(id: "s1", agent: "codex", cwd: "/Users/me/pockito", state: .working, now: now.addingTimeInterval(-14 * 60))
        session.updatedAt = now.addingTimeInterval(-60)
        let inside = entry(1, "external:codex", minutesAgo: 5, "Watch “npm test”")
        let before = entry(2, "external:codex", minutesAgo: 30)
        let mine = entry(3, "user", minutesAgo: 2)
        let otherAgent = entry(4, "external:claude-code", minutesAgo: 4)
        let events = HistoryTimeline.merge(activity: [inside, before, mine, otherAgent], conversations: [], alerts: [],
                                           sessions: [session], now: now)
        #expect(events.count == 4, "the call inside the session folds into its receipt")
        guard case .session(_, let calls)? = events.first(where: { if case .session = $0.kind { true } else { false } })?.kind else {
            Issue.record("no receipt")
            return
        }
        #expect(calls.map(\.id) == [1])
        #expect(events.map(\.at) == events.map(\.at).sorted(by: >), "newest first")
    }

    @Test func filtersAndSearchNarrowTheTimeline() {
        let conversation = ConversationSummary(id: "c1", title: "Plan my afternoon", startedAt: now, updatedAt: now, requests: 2, spoken: false)
        let alert = AttentionItem(level: .attention, source: "watcher", title: "Pricing changed", now: now)
        let events = HistoryTimeline.merge(activity: [entry(1, "agent", minutesAgo: 1, "Renamed 3 screenshots"), entry(2, "external:codex", minutesAgo: 3)],
                                           conversations: [conversation], alerts: [alert], sessions: [], now: now)
        func count(_ filter: HistoryFilter, _ query: String = "") -> Int { events.filter { HistoryTimeline.shows($0, filter: filter, query: query) }.count }
        #expect(count(.all) == 4)
        #expect(count(.conversations) == 1)
        #expect(count(.actions) == 1, "another agent's call is under Agents, not Actions")
        #expect(count(.agents) == 1)
        #expect(count(.alerts) == 1)
        #expect(count(.all, "renamed SCREENSHOTS") == 1, "every word, any case")
        #expect(count(.all, "renamed pricing") == 0)
    }

    @Test func eventsGroupByTheirHour() {
        let events = [entry(1, "user", minutesAgo: 30), entry(2, "user", minutesAgo: 31), entry(3, "user", minutesAgo: 90)]
            .map { HistoryEvent(.action($0), at: $0.at) }
        let hours = HistoryTimeline.hours(events)
        #expect(hours.map(\.events.count) == [2, 1])
    }

    @Test func onDutyCountsWhatRunsAndListsWhatIsPaused() {
        var paused = Watcher(kind: "file", title: "report.pdf", config: .object([:]), intervalS: 60, source: "user", now: now)
        paused.state = .paused
        var trouble = Watcher(kind: "site", title: "staging", config: .object([:]), intervalS: 300, source: "user", now: now)
        trouble.state = .error
        let page = Watcher(kind: "web", title: "pricing", config: .object([:]), intervalS: 1800, source: "user", now: now)
        let cpu = Watcher(kind: "metric", title: "CPU", config: .object([:]), intervalS: 10, mode: .report, source: "user", now: now)
        var fired = Watcher(kind: "web", title: "done", config: .object([:]), intervalS: 60, source: "user", now: now)
        fired.state = .triggered
        let once = Reminder(title: "Send the deck", fireAt: now.addingTimeInterval(3600), source: "user", now: now)
        let stretch = Reminder(title: "Stretch", fireAt: now, recurrence: Recurrence(frequency: .hourly, interval: 2), source: "user", now: now)
        let routine = Reminder(title: "Evening wrap", fireAt: now, action: ReminderAction(kind: .prompt, prompt: "wrap"), source: "user", now: now)
        let working = AgentSession(id: "a", agent: "codex", cwd: nil, state: .working, now: now)
        let idle = AgentSession(id: "b", agent: "codex", cwd: nil, state: .idle, now: now)
        let duty = OnDuty(watchers: [paused, trouble, page, cpu, fired], reminders: [once, stretch, routine], sessions: [working, idle], jobs: [])
        #expect(duty.watches.count == 3 && duty.reports.count == 1)
        #expect(duty.repeating.map(\.title) == ["Stretch", "Evening wrap"])
        #expect(duty.running() == 6, "pricing, staging (still trying), CPU, two repeating, one session")
        #expect(duty.running(extra: 1) == 7)
        #expect(duty.paused == 1)
        // Each group's own count adds up to the title's, so the line under it never disagrees.
        #expect(duty.runningWatches == 2 && duty.runningReports == 1)
        #expect(duty.runningWatches + duty.runningReports + duty.repeating.count + duty.sessions.count + duty.jobs.count == duty.running())
        #expect(duty.pausable.map(\.title).sorted() == ["CPU", "pricing", "staging"])
    }

    @Test func theBriefSaysWhatNeedsYouWhatComesNextAndWhatChanged() {
        #expect(DayBrief.lead(needsYou: 0) == "Nothing needs you.")
        #expect(DayBrief.lead(needsYou: 1) == "One thing needs you.")
        #expect(DayBrief.lead(needsYou: 3) == "3 things need you.")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let at = cal.date(bySettingHour: 16, minute: 30, second: 0, of: now)!
        #expect(DayBrief.detail(next: ("Design review", at), changed: ["example.com/pricing"], calendar: cal)
            == "Design review is at 16:30, and example.com/pricing changed.")
        #expect(DayBrief.detail(next: ("Design review", at), changed: [], calendar: cal) == "Design review is at 16:30.")
        #expect(DayBrief.detail(next: nil, changed: ["a", "b"], calendar: cal) == "2 watched pages changed.")
        #expect(DayBrief.detail(next: nil, changed: [], calendar: cal).isEmpty)
        let afternoon = cal.date(bySettingHour: 15, minute: 58, second: 0, of: now)!
        #expect(DayBrief.greeting(at: afternoon, name: "Ghassen", calendar: cal) == "Good afternoon, Ghassen.")
        #expect(DayBrief.greeting(at: afternoon, name: " ", calendar: cal) == "Good afternoon.")
    }

    @Test func keepingASuggestedFactMakesItTheirsAndPutsItInAnswers() async throws {
        let env = try TestEnv()
        let notebook = NotebookStore(env.db)
        let mine = try #require(try await ProfileFacts.write("Prefers short answers", notebook: notebook, events: env.events, now: now))
        guard let profile = try await NotebookCollections.profile(notebook, create: false) else { Issue.record("no profile"); return }
        let suggested = NotebookItem(collectionId: profile.id, kind: .note, title: "Uses pnpm, not npm", source: "external:codex", now: now)
        try await notebook.add(suggested)
        #expect(ProfileFacts.isSuggestion(suggested) && !ProfileFacts.isSuggestion(mine))
        #expect(await ProfileFacts.all(notebook: notebook).map(\.id) == [mine.id], "a suggestion stays out of answers")
        try await ProfileFacts.keep(suggested, notebook: notebook, events: env.events, now: now)
        #expect(await ProfileFacts.all(notebook: notebook).count == 2)
        let edited = try await ProfileFacts.write("Prefers short, direct answers", editing: mine, notebook: notebook, events: env.events, now: now)
        #expect(edited?.id == mine.id)
        #expect(try await notebook.item(id: mine.id)?.title == "Prefers short, direct answers")
        #expect(try await ProfileFacts.write("   ", notebook: notebook, events: env.events) == nil)
    }
}
