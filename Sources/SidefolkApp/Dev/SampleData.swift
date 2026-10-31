#if DEBUG
import Foundation
import SidefolkCore

/// A believable week of Sidefolk for a developer, written into an in-memory runtime (UISnapshots).
enum SampleData {
    struct Created {
        var project: NotebookCollection
        var profile: NotebookCollection
        var selectedItem: NotebookItem
        var profileItem: NotebookItem
        /// A task with a reminder that belongs to it (D49).
        var remindedTask: NotebookItem
        /// A note Sidefolk's agent saved in a conversation that is still kept (D58).
        var savedInConversation: NotebookItem
    }

    static func fill(_ rt: SidefolkRuntime, notebook: NotebookModel) async throws -> Created {
        let now = Date()
        let home = NSHomeDirectory()
        // The calendar shown (D57): its events come from `SamplePlatform`.
        await rt.settings.update { $0.showCalendar = true }
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func ahead(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
        let cal = Calendar.current
        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let d = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
        }

        await rt.settings.update { s in
            s.provider.kind = .claudeCode
            s.provider.model = "sonnet"
            s.provider.smartModel = "opus"
        }

        // Notebook
        let inbox = try await rt.notebook.inbox()
        await notebook.reloadCollections()
        func make(_ name: String, _ kind: NotebookCollection.Kind) async throws -> NotebookCollection {
            switch await notebook.createCollection(named: name, kind: kind) {
            case .success(let c): return c
            case .failure(let e): throw e
            }
        }
        let profile = notebook.collections.first { $0.kind == .profile }!
        let sidefolk = try await make("Sidefolk", .project)
        let pockito = try await make("Pockito", .project)
        let reading = try await make("Reading list", .list)
        let groceries = try await make("Groceries", .list)
        _ = try await make("Design", .topic)
        let blog = try await make("Old blog", .project)
        try await rt.notebook.setLook(collectionId: sidefolk.id, emoji: nil, symbol: "sparkles", color: "teal")
        try await rt.notebook.setLook(collectionId: pockito.id, emoji: nil, symbol: "bolt.fill", color: "orange")
        try await rt.notebook.setLook(collectionId: groceries.id, emoji: "🥕", symbol: nil, color: nil)
        try await rt.notebook.setArchived(collectionId: blog.id, true)

        func item(_ c: NotebookCollection, _ kind: NotebookItem.Kind, _ title: String, body: String = "", url: String? = nil,
                  tags: [String] = [], source: String = "user", run: String? = nil, created: Date, edited: Date? = nil,
                  done: Bool = false) async throws -> NotebookItem {
            var i = NotebookItem(collectionId: c.id, kind: kind, title: title, body: body, url: url, tags: tags, source: source,
                                 runId: run, now: created)
            i.updatedAt = edited ?? created
            if done { i.status = .done }
            try await rt.notebook.add(i)
            return i
        }

        _ = try await item(inbox, .idea, "Folks could have their own sounds", body: "A short chime per folk, so you know who's tapping you without looking.",
                           tags: ["folks", "sound"], source: "external:claude-code", created: ago(35))
        let karim = try await item(inbox, .note, "Karim's new address", body: "12 rue Oberkampf, 75011 Paris", source: "user:agent",
                                   run: "r-karim", created: ago(60 * 26))
        let passport = try await item(inbox, .task, "Renew passport", body: "Appointment needed at the mairie.", created: ago(60 * 50))
        _ = try await item(inbox, .link, "Swift Testing", url: "https://developer.apple.com/xcode/swift-testing/", created: ago(60 * 70))

        let profileItem = try await item(profile, .note, "Prefers short, direct answers", body: "No preamble. Lead with the answer, then one line of why.",
                                         created: ago(60 * 24 * 6))
        _ = try await item(profile, .note, "Mornings are for deep work", body: "Avoid interruptions before 11:00 unless it's important.", created: ago(60 * 24 * 5))
        _ = try await item(profile, .note, "Works in Swift and TypeScript", body: "Main projects: Sidefolk (Swift), Pockito (TypeScript).",
                           created: ago(60 * 24 * 4))
        _ = try await item(profile, .note, "Lives in Paris", body: "Time zone Europe/Paris. Metric units.", created: ago(60 * 24 * 9))

        let selected = try await item(sidefolk, .idea, "Extensions could bring their own folk",
                                      body: """
                                      An extension's manifest could name a **folk** (color, prop, voice). While its tools run, that folk \
                                      sits beside Sidefolk like *Tempo* and *Scout* do.

                                      ## Questions
                                      - Who draws the folk? A template with a few colors and props is enough for v1.
                                      - Cap at three folks on screen, as today.

                                      ## Before v1
                                      - [x] Sketch three folks
                                      - [ ] Ask on the [forum](https://example.com/forum)
                                      - [ ] Write the `folk` manifest key
                                      """,
                                      tags: ["extensions", "folks"], source: "external:claude-code", created: ago(60 * 47), edited: ago(12))
        try await rt.notebook.setPinned(itemId: selected.id, true, now: ago(10))
        let guide = try await item(sidefolk, .task, "Write the extension developer guide", body: "Manifest, permissions, the watcher protocol, a sample.",
                                   tags: ["docs"], created: ago(60 * 30))
        _ = try await item(sidefolk, .task, "Record a 30-second demo", tags: ["launch"], created: ago(60 * 80), edited: ago(60 * 20), done: true)
        _ = try await item(sidefolk, .note, "Launch checklist", body: "Notarize, staple, DMG, landing page, Show HN draft.",
                           tags: ["launch"], created: ago(60 * 100))
        _ = try await item(sidefolk, .link, "Notarizing macOS software", url: "https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution",
                           created: ago(60 * 120))
        _ = try await item(sidefolk, .idea, "Morning brief could mention the weather", source: "user", created: ago(60 * 140))
        _ = try await item(pockito, .task, "Fix the sync conflict on rename", tags: ["bug"], source: "external:codex", created: ago(60 * 5))
        _ = try await item(pockito, .note, "Pricing thoughts", body: "Free for one device; $3/month for sync.", created: ago(60 * 60))
        _ = try await item(reading, .link, "The Mythical Man-Month", url: "https://en.wikipedia.org/wiki/The_Mythical_Man-Month", created: ago(60 * 200))
        for (i, thing) in ["Oat milk", "Coffee beans", "Lemons", "Basil"].enumerated() {
            _ = try await item(groceries, .task, thing, created: ago(Double(30 + i)), done: i == 3)
        }
        let old = try await item(sidefolk, .note, "Old pricing page copy", created: ago(60 * 24 * 12))
        _ = try await rt.notebook.trash(itemId: old.id, now: ago(60 * 24 * 2))
        let draft = try await item(inbox, .idea, "Sidefolk for iPad?", created: ago(60 * 24 * 3))
        _ = try await rt.notebook.trash(itemId: draft.id, now: ago(60 * 5))

        // Reminders
        func reminder(_ title: String, at: Date, recurrence: Recurrence? = nil, source: String = "user", state: Reminder.State = .scheduled,
                      snoozedUntil: Date? = nil, updated: Date? = nil, for item: NotebookItem? = nil) async throws {
            var r = Reminder(title: title, fireAt: at, recurrence: recurrence, source: source, now: ago(60 * 24))
            r.itemId = item?.id
            r.state = state
            r.snoozedUntil = snoozedUntil
            if state == .fired || state == .done { r.lastFiredAt = updated ?? at }
            r.updatedAt = updated ?? r.updatedAt
            try await rt.reminderStore.save(r)
        }
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let soon = min(ahead(40), endOfToday.addingTimeInterval(-120))
        try await reminder("Send the deck to Karim", at: soon)
        try await reminder("Stretch and refill water", at: ago(20), state: .snoozed, snoozedUntil: min(ahead(10), endOfToday.addingTimeInterval(-60)))
        try await reminder("Stand-up", at: day(1, 9, 30), recurrence: Recurrence(frequency: .weekdays))
        try await reminder("Drink some water", at: min(ahead(25), endOfToday.addingTimeInterval(-90)),
                           recurrence: Recurrence(frequency: .minutely, interval: 30, until: min(max(day(0, 18), ahead(120)), endOfToday.addingTimeInterval(-60))))
        try await reminder("Call mom", at: day(1, 18), source: "external:claude-code")
        try await reminder("Renew the sidefolk.app domain", at: day(4, 10))
        // Reminders that belong to a task (D49): one with the task's own words, one with words of its own.
        try await reminder("Write the extension developer guide", at: day(1, 10), for: guide)
        try await reminder("Book the mairie appointment", at: day(2, 9), for: passport)
        try await reminder("Water the plants", at: day(6, 19), recurrence: Recurrence(frequency: .weekly, weekdays: [7]))
        try await reminder("Pay rent", at: day(9, 9), recurrence: Recurrence(frequency: .monthly))
        try await reminder("Take out the recycling", at: ago(130), state: .done, updated: ago(120))
        try await reminder("Book the dentist", at: ago(60 * 20), state: .fired, updated: ago(60 * 20))

        // Watchers
        func watcher(_ title: String, kind: String, config: JSONValue, every: Double, state: Watcher.State = .active, checked: Date? = nil,
                     error: String? = nil, updated: Date? = nil, id: String? = nil, seen: JSONValue? = nil) async throws {
            var w = Watcher(id: id ?? Identifier.make(), kind: kind, title: title, config: config, intervalS: every, source: "user",
                            now: ago(60 * 24 * 2))
            w.lastState = seen
            w.state = state
            w.lastCheckedAt = checked
            w.lastError = error
            w.errorCount = error == nil ? 0 : 3
            if let updated { w.updatedAt = updated }
            try await rt.watcherStore.save(w)
        }
        // What the page probe keeps of its last change (D58), and the notice about it still waiting on Today.
        try await watcher("Pro pricing on example.com", kind: "web.change", config: ["url": "https://example.com/pricing"], every: 1800, checked: ago(4),
                          id: "w-pricing", seen: ["change": ["at": .number(ago(25).timeIntervalSince1970),
                                                             "removed": ["Pro $12 / month, billed yearly"], "added": ["Pro $15 / month, billed yearly"]]])
        try await watcher("Staging is up", kind: "site.up", config: ["url": "https://staging.sidefolk.app"], every: 60, state: .error, checked: ago(1),
                          error: "Couldn't reach staging.sidefolk.app (timed out). I'll try again in 4 min.")
        try await watcher("report.pdf lands in Downloads", kind: "file.appears", config: ["path": .string(home + "/Downloads/report.pdf")],
                          every: 60, state: .paused, checked: ago(60 * 3))
        try await watcher("Nils Frahm tickets go on sale", kind: "web.contains", config: ["url": "https://example.org/concerts"], every: 3600,
                          state: .triggered, checked: ago(170), updated: ago(170))

        // Reports: values told in place, with the last reading saved as the engine saves it.
        func report(_ title: String, kind: String, config: JSONValue, every: Double, value: String, ends: Date?) async throws {
            var w = Watcher(kind: kind, title: title, config: config, intervalS: every, mode: .report, expiresAt: ends, source: "user", now: ago(12))
            w.lastCheckedAt = now.addingTimeInterval(-min(every, 30))
            w.lastState = ["reading": ["shown": .string(value)]]
            try await rt.watcherStore.save(w)
        }
        try await report(String(localized: "CPU"), kind: WatchKind.metric, config: ["metric": "cpu"], every: 10, value: "23%", ends: ahead(48))
        try await report(String(localized: "Temperature in \("Fukuoka")"), kind: WatchKind.weather, config: ["place": "Fukuoka", "quantity": "temperature"],
                         every: 60, value: "18.4 °C", ends: nil)

        // Jobs and sessions
        var running = Job(kind: .command, title: "npm test", command: "npm test -- --watch=false", cwd: home + "/git/pockito", pid: 4312,
                          source: "cli", now: ago(3))
        running.state = .running
        try await rt.jobs.save(running)
        var built = Job(kind: .command, title: "swift build -c release", command: "swift build -c release", cwd: home + "/git/sidefolk", pid: 4100,
                        source: "cli", now: ago(46))
        built.state = .succeeded
        built.exitCode = 0
        built.endedAt = ago(40)
        try await rt.jobs.save(built)
        var deploy = Job(kind: .command, title: "./deploy.sh staging", command: "./deploy.sh staging", cwd: home + "/git/pockito", pid: 3900,
                         source: "cli", now: ago(125))
        deploy.state = .failed
        deploy.exitCode = 1
        deploy.endedAt = ago(122)
        try await rt.jobs.save(deploy)

        var waiting = AgentSession(id: "cc-1", agent: "claude-code", cwd: home + "/git/sidefolk", state: .needsYou, now: ago(30))
        waiting.detail = "Wants to run: git push origin main"
        waiting.updatedAt = ago(6)
        try await rt.sessions.save(waiting)
        var working = AgentSession(id: "cx-1", agent: "codex", cwd: home + "/git/pockito", state: .working, now: ago(14))
        working.detail = "Refactoring the sync engine"
        try await rt.sessions.save(working)
        var finished = AgentSession(id: "cc-2", agent: "claude-code", cwd: home + "/git/website", state: .finished, now: ago(82))
        finished.endedAt = ago(60)
        finished.updatedAt = ago(60)
        try await rt.sessions.save(finished)

        // Things waiting for the user
        let attention = AttentionStore(rt.db)
        try await attention.save(AttentionItem(
            level: .attention, source: "reminder", title: "Send the invoice to Acme.", body: "You asked yesterday, 18:20.",
            // The buttons in the app's words, as the reminder and watch notices word them.
            actions: [AttentionAction(id: "done", title: String(localized: "Done"), isPrimary: true),
                      AttentionAction(id: "snooze10", title: String(localized: "10 min")),
                      AttentionAction(id: "tomorrow", title: String(localized: "Tomorrow"))],
            refKind: "reminder", refId: "r-acme", now: ago(8)))
        try await attention.save(AttentionItem(
            level: .attention, source: "watcher", title: "Pricing changed: Pro went from $12 to $15.",
            actions: [AttentionAction(id: "open", title: String(localized: "Open"), isPrimary: true),
                      AttentionAction(id: "stop", title: String(localized: "Stop"))],
            refKind: "watcher", refId: "w-pricing", now: ago(25)))

        // Activity and agent runs
        let entries: [(Double, String, String, String, ActivityEntry.Decision, String, String?, String?)] = [
            (1, "agent", "files.rename", "medium", .autoMode, "Rename “Scan 0412.pdf” to “Invoice April.pdf”", "Renamed", nil),
            (2, "agent", "notebook.search", "low", .auto, "Search the notebook for “sidefolk ideas”", "Found 4 items", nil),
            (6, "external:claude-code", "shell.run", "high", .denied, "Run “git push origin main” in ~/git/sidefolk", nil, "You said not now."),
            (15, "agent", "ext.miraya.share_screen", "medium", .fullAccessPaired, "Share the screen to Living Room TV",
             "Sharing Built-in display on Living Room TV", nil),
            (35, "external:claude-code", "notebook.add", "low", .auto, "Save an idea to Inbox", "Saved “Folks could have their own sounds”", nil),
            (52, "agent", "web.fetch", "medium", .allowed, "Fetch example.com/pricing", "Read 12 KB", nil),
            (61, "agent", "files.move", "medium", .always, "Move 12 PDFs from Downloads to Invoices", "Moved 12 files", nil),
            (75, "extension:app.sidefolk.system-vitals", "vitals_cpu", "low", .auto, "Read CPU load", "CPU 34%", nil),
            (90, "external:codex", "watch.create", "low", .auto, "Watch “npm test” in ~/git/pockito", "Watching", nil),
            (130, "agent", "files.trash", "medium", .blocked, "Move 3 files in ~/Desktop to the Trash", nil,
             "That folder hasn't been shared with Sidefolk."),
            (180, "agent", "web.fetch", "medium", .failed, "Fetch staging.sidefolk.app", nil, "Timed out after 15 s. Nothing changed."),
            (240, "user", "reminder.create", "low", .auto, "Remind me tomorrow at 18:00 to call mom", "Tomorrow 18:00", nil),
            (300, "agent", "clipboard.read", "medium", .allowed, "Read the clipboard", "Read 214 characters", nil),
            (420, "routine:morning-brief", "notebook.search", "low", .auto, "Collect today's open tasks", "3 tasks", nil),
            (60 * 20, "agent", "apps.open", "low", .auto, "Open github.com/sidefolk/sidefolk", "Opened in Safari", nil),
            (60 * 30, "agent", "shell.run", "high", .allowed, "Run “npm test” in ~/git/pockito", "Exit 0 after 41 s", nil),
            (60 * 40, "agent", "files.trash", "high", .fullAccess, "Move 2 files in ~/Downloads to the Trash", "Moved to the Trash", nil),
            (60 * 50, "external:claude-code", "notify", "low", .auto, "Tell you that the build finished", "Shown as a bubble", nil),
        ]
        // What a few of them were called with, as the details show it.
        let args: [Double: JSONValue] = [
            6: .object(["command": "git push origin main", "cwd": .string(home + "/git/sidefolk")]),
            61: .object(["from": .string(home + "/Downloads"), "to": .string(home + "/Documents/Invoices"), "pattern": "*.pdf"]),
        ]
        for (minutes, caller, tool, risk, decision, summary, outcome, error) in entries {
            try await rt.activity.log(ActivityEntry(at: ago(minutes), caller: caller, tool: tool, risk: risk, decision: decision,
                                                    summary: summary, args: args[minutes], outcome: outcome, error: error))
        }
        for i in 0..<14 {
            var run = AgentRun(threadId: "t\(i)", provider: "claudeCode", model: "sonnet", now: ago(Double(i) * 200))
            run.inputTokens = 9_000 + i * 1_300
            run.outputTokens = 1_200 + i * 160
            run.steps = 2
            // Done, as past runs are: only a run without an end shows as working (D58).
            run.endedAt = ago(Double(i) * 200 - 0.7)
            try await rt.runs.save(run)
        }

        // Conversations with the AI (D45): a plan with its steps and a follow-up, a spoken question, one that stopped.
        func said(_ thread: String, _ role: Exchange.Role, _ text: String, _ minutes: Double, run: String? = nil,
                  spoken: Bool = false) async throws {
            var meta: [String: JSONValue] = role == .user ? ["tainted": false] : [:]
            if spoken { meta["spoken"] = true }
            if let run { meta["runId"] = .string(run) }
            try await rt.exchanges.append(Exchange(threadId: thread, role: role, content: text, meta: .object(meta), now: ago(minutes)))
        }
        func step(_ run: String, _ minutes: Double, _ tool: String, _ summary: String, _ decision: ActivityEntry.Decision = .auto,
                  error: String? = nil) async throws {
            try await rt.activity.log(ActivityEntry(at: ago(minutes), caller: "agent", tool: tool, risk: "low", decision: decision,
                                                    summary: summary, error: error, runId: run))
        }
        try await said("c-rename", .user, "Rename the scans on my Desktop by date", 60 * 26)
        try await step("r-rename", 60 * 26 - 0.5, "files.rename", "Rename 3 files in ~/Desktop", .blocked,
                       error: "That folder hasn't been shared with Sidefolk.")
        try await said("c-rename", .event, "Stopped. Nothing was changed.", 60 * 26 - 1, run: "r-rename")
        try await said("c-rain", .user, "Will it rain in Fukuoka tomorrow?", 60 * 5, spoken: true)
        try await step("r-rain", 60 * 5 - 0.2, "ext.weather.forecast", "Weather forecast for Fukuoka")
        try await said("c-rain", .assistant, "Light rain is likely tomorrow morning in Fukuoka (70%), clearing after noon. Highs around 19 °C.",
                       60 * 5 - 0.4, run: "r-rain")
        try await said("c-karim", .user, "Save Karim's new address: 12 rue Oberkampf, 75011 Paris", 60 * 26 + 0.2)
        try await step("r-karim", 60 * 26 + 0.1, "notes.save", "Save a note to Inbox")
        try await said("c-karim", .assistant, "Saved “Karim's new address” to your Inbox.", 60 * 26, run: "r-karim")
        try await said("c-plan", .user, "Plan my afternoon around the invoices and a run", 95)
        try await step("r-plan", 94.8, "notebook.search", "Search the notebook for “invoices”")
        try await step("r-plan", 94.7, "reminders.list", "Read your reminders for today")
        try await said("c-plan", .assistant, SampleData.plan, 94.5, run: "r-plan")
        try await said("c-plan", .user, "Yes, remind me at 16:30 to go for the run", 93)
        try await step("r-plan-2", 92.9, "reminders.create", "Remind me today at 16:30 to go for a run")
        try await said("c-plan", .assistant, "Done: I'll remind you at 16:30 to go for your run.", 92.8, run: "r-plan-2")

        // Guard
        try await rt.permissions.grantFolder(home + "/Downloads", access: .readwrite)
        try await rt.permissions.grantFolder(home + "/Documents/Invoices", access: .read)
        var move = Grant(tool: "files.move", scope: ["folder": .string(home + "/Downloads")], callerKind: "agent", now: ago(60 * 24 * 3))
        move.lastUsedAt = ago(61)
        try await rt.permissions.addGrant(move)
        try await rt.permissions.addGrant(Grant(tool: "shell.run", scope: ["command": "npm test"], callerKind: "agent", now: ago(60 * 30)))
        try await rt.permissions.addGrant(Grant(tool: "web.fetch", scope: ["host": "github.com"], callerKind: "external", now: ago(60 * 24)))
        // Using the internet (D47): a site and a built-in service allowed for good.
        var docs = Grant(tool: "web.fetch", scope: ["host": "docs.swift.org"], callerKind: "agent", now: ago(60 * 24 * 2))
        docs.lastUsedAt = ago(20)
        try await rt.permissions.addGrant(docs)
        try await rt.permissions.addGrant(Grant(tool: "ext.weather.forecast", scope: ["extension": "dev.sidefolk.weather"],
                                                callerKind: "agent", now: ago(60 * 5)))
        try await rt.permissions.setPolicy(GuardPolicy(mode: .askOncePerKind, disabled: [.clipboard]))

        return Created(project: sidefolk, profile: profile, selectedItem: selected, profileItem: profileItem, remindedTask: guide,
                       savedInConversation: karim)
    }

    /// A long answer, for Conversations and the Ask panel's Show all.
    static let plan = """
        Here's a plan for this afternoon:

        **14:00** Rename and file the April invoices (about 30 minutes).
        **14:30** Reply to Karim about the new address.
        **15:00** Deep work on the onboarding copy.
        **16:30** A 5 km run, before the light goes.
        **17:30** Stretch, then the 18:00 call with mom.
        **19:00** Dinner, then nothing with a screen.

        I left the pricing page review for tomorrow morning: it needs a fresh head. Want me to set reminders for these?
        """
}
#endif
