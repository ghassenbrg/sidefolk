import AppKit
import SidefolkCore

extension AppCoordinator {
    func makeAgentRuntime() -> AgentRuntime {
        let runtime = self.runtime
        let platform = runtime.platform
        let live = LiveStateSummary.provider(db: runtime.db)
        let extensions = runtime.extensions
        let skills = runtime.skills
        let sources = ContextSources(
            frontmostApp: { await platform.frontmostApplication() },
            liveState: {
                let lines = [await live(), ExtensionContext.watcherLines(await extensions.watcherKinds())].compactMap { $0 }
                return lines.isEmpty ? nil : lines.joined(separator: "\n")
            },
            skills: { skills.index() }
        )
        let context = ContextBuilder(notebook: runtime.notebook, exchanges: runtime.exchanges, sources: sources)
        let paths = runtime.paths
        let helper = helperPath
        let tokens = runtime.tokens
        let factory = BrainFactory.standard(secrets: secrets, claudeCodeBackend: { provider in
            ClaudeCodeBackend.make(provider: provider, paths: paths, helperPath: helper, registry: tokens)
        })
        let settings = runtime.settings
        return AgentRuntime(executor: runtime.executor, db: runtime.db, events: runtime.events, context: context,
                            factory: factory, settings: { settings.current })
    }
}

extension AppCoordinator: AskActions {
    func hint(for text: String) -> String? {
        if let title = ask.pendingReminderTitle {
            guard let when = whenParser.parse(text, now: Date()) else { return "When should I remind you to “\(title.clipped(30))”?" }
            return "Reminder · \(TimeFormat.when(when.date, now: Date(), calendar: .autoupdatingCurrent)) · no AI"
        }
        if let parsed = runtime.intentParser.parse(LocalIntentRunner.expandSlash(text), now: Date(), knownCollections: knownCollections) {
            return parsed.hint
        }
        return runtime.settings.current.provider.kind == .none ? "Needs AI — not set up yet" : "Ask \(providerLabel)"
    }

    var whenParser: WhenParser { WhenParser(calendar: .autoupdatingCurrent, settings: runtime.settings.current) }

    var providerLabel: String {
        switch runtime.settings.current.provider.kind {
        case .none: "no AI"
        case .claudeCode: "Claude"
        case .anthropic: "Claude (API)"
        case .openAICompatible: runtime.settings.current.provider.model.isEmpty ? "your model" : runtime.settings.current.provider.model
        }
    }

    func submit(_ text: String, attachment: Attachment?, thinkHarder: Bool, into model: AskModel) {
        // A reminder that was waiting for its time.
        if let title = model.pendingReminderTitle, attachment == nil {
            model.pendingReminderTitle = nil
            if let when = whenParser.parse(text, now: Date()) {
                runLocal(.remind(title: title, when: when.date, recurrence: when.recurrence), caption: "\(title) — \(text)", into: model)
            } else {
                model.add(.info("I didn't catch a time, so I didn't set it. Try “remind me tomorrow at 9 to \(title)”."))
            }
            return
        }
        // Plain-language intents complete locally, instantly, without AI (DECISIONS D4).
        if !thinkHarder, attachment == nil,
           let parsed = runtime.intentParser.parse(LocalIntentRunner.expandSlash(text), now: Date(), knownCollections: knownCollections) {
            runLocal(parsed.intent, caption: text, into: model)
            return
        }
        guard runtime.settings.current.provider.kind != .none else {
            model.add(.needsBrain(attachment?.text.map { "\(text)\n\n\($0)" } ?? text), caption: text)
            return
        }
        runAgent(text, attachment: attachment, thinkHarder: thinkHarder, into: model)
    }

    func runLocal(_ intent: LocalIntent, caption: String, into model: AskModel) {
        let runner = LocalIntentRunner(runtime: runtime)
        Task {
            let outcome = await runner.run(intent)
            switch outcome {
            case .card(let card, let activityId, let undo):
                model.add(.result(card, activityId: activityId.isEmpty ? nil : activityId, undo: undo), caption: caption)
                // Quick intents close the panel a moment after their card appears.
                try? await Task.sleep(for: .seconds(undo ? 2.5 : 1.2))
                if !model.busy, model.text.isEmpty, model.entries.last?.caption == caption { model.onAutoClose?() }
            case .list(let title, let cards):
                model.add(.list(title: title, cards: cards), caption: caption)
            case .needsTime(let title):
                model.pendingReminderTitle = title
                model.add(.info("When should I remind you to “\(title)”?"), caption: caption)
                model.focusRequest += 1
            case .info(let text):
                model.add(.info(text), caption: caption)
            case .failed(let error):
                model.add(.error(error, retryable: false), caption: caption)
            }
        }
    }

    func runAgent(_ text: String, attachment: Attachment?, thinkHarder: Bool, into model: AskModel) {
        model.busy = true
        model.phase = thinkHarder ? "Thinking harder…" : "Thinking…"
        let agentAttachment = attachment.map { a -> AgentAttachment in
            AgentAttachment(text: a.text ?? a.label, source: a.label, untrusted: true)
        }
        let request = AgentRequest(text: text, attachment: agentAttachment, thinkHarder: thinkHarder)
        let agent = self.agent!
        Task {
            let handle = await agent.submit(request)
            currentRun = handle.runId
            var captioned = false
            var shownCards = Set<String>()
            func caption() -> String? {
                defer { captioned = true }
                return captioned ? nil : text
            }
            for await event in handle.events {
                switch event {
                case .phase(.thinking):
                    model.phase = thinkHarder ? "Thinking harder…" : "Thinking…"
                case .phase(.working(let category)):
                    model.phase = Self.phaseLine(category)
                case .phase(.waitingForApproval):
                    model.phase = "Waiting for your OK…"
                case .toolFinished(let activity, let ok):
                    if ok, let card = activity.card {
                        shownCards.insert(card.title)
                        model.add(.result(card, activityId: activity.id, undo: activity.undoAvailable), caption: caption())
                    }
                case .reply(let reply):
                    for card in reply.cards where !shownCards.contains(card.title) {
                        model.add(.result(card, activityId: nil, undo: false), caption: caption())
                    }
                    let answer = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !answer.isEmpty {
                        model.add(.answer(answer, canThinkHarder: !thinkHarder && runtime.settings.current.provider.smartModel != ""),
                                  caption: caption())
                    }
                case .failed(let error):
                    model.add(.error(error, retryable: true), caption: caption())
                case .finished:
                    break
                default:
                    break
                }
            }
            model.busy = false
            model.phase = nil
            currentRun = nil
        }
    }

    static func phaseLine(_ category: ToolCategory) -> String {
        switch category {
        case .notes: "Writing it down…"
        case .memory: "Remembering…"
        case .time: "Setting the reminder…"
        case .watch: "Setting up the watch…"
        case .files: "Looking at your files…"
        case .web: "Reading the page…"
        case .system: "Working on it…"
        case .agents: "Checking on your agents…"
        case .extensions: "Using an extension…"
        }
    }

    func stop() {
        let agent = self.agent!
        Task { await agent.cancelAll() }
    }

    func undo(activityId: String, in model: AskModel) {
        Task {
            do {
                if let label = try await runtime.executor.undo.undo(activityId) {
                    model.add(.info("Undone: \(label)."))
                } else {
                    model.add(.info("That can't be undone anymore."))
                }
            } catch {
                model.add(.error(UserFacingError("I couldn't undo that.", detail: String(describing: error)), retryable: false))
            }
        }
    }

    func answer(approval: ApprovalRequest, decision: ApprovalDecision) {
        ask.removeApproval(id: approval.id)
        Task { await runtime.broker.resolve(id: approval.id, decision: decision) }
    }

    func open(card: ResultCard) {
        if let url = card.url, let u = URL(string: url), ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(u)
            return
        }
        if card.kind == .note, let id = card.refId {
            Task {
                if let item = try? await runtime.notebook.item(id: id) { openHome(item: item) } else { openHome() }
            }
            return
        }
        openHome()
    }

    func saveAnswer(_ text: String, in model: AskModel) {
        Task {
            let out = await runtime.executor.execute(name: "notes.save", input: ["text": .string(text)], caller: .user)
            switch out.status {
            case .ok(let r):
                if let card = r.card { model.add(.result(card, activityId: out.activity.id, undo: out.activity.undoAvailable)) }
            case .denied(let why):
                model.add(.error(UserFacingError(why), retryable: false))
            case .failed(let e):
                model.add(.error(e, retryable: false))
            }
        }
    }

    func openSettingsAI() { openSettings(tab: .ai) }
}
