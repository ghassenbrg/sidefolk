import AppKit
import SidefolkCore

extension AppCoordinator {
    func makeAgentRuntime() -> AgentRuntime {
        let runtime = self.runtime
        let platform = runtime.platform
        let sources = ContextSources(
            frontmostApp: { await platform.frontmostApplication() },
            liveState: LiveStateSummary.provider(db: runtime.db),
            skills: { [] }
        )
        let context = ContextBuilder(notebook: runtime.notebook, exchanges: runtime.exchanges, sources: sources)
        let factory = BrainFactory.standard(secrets: secrets, claudeCodeBackend: { _ in nil })
        let settings = runtime.settings
        return AgentRuntime(executor: runtime.executor, db: runtime.db, events: runtime.events, context: context,
                            factory: factory, settings: { settings.current })
    }
}

extension AppCoordinator: AskActions {
    func hint(for text: String) -> String? {
        runtime.settings.current.provider.kind == .none ? nil : "Ask \(providerLabel)"
    }

    var providerLabel: String {
        switch runtime.settings.current.provider.kind {
        case .none: "no AI"
        case .claudeCode: "Claude"
        case .anthropic: "Claude (API)"
        case .openAICompatible: runtime.settings.current.provider.model.isEmpty ? "your model" : runtime.settings.current.provider.model
        }
    }

    func submit(_ text: String, attachment: Attachment?, thinkHarder: Bool, into model: AskModel) {
        guard runtime.settings.current.provider.kind != .none else {
            model.add(.needsBrain, caption: text)
            return
        }
        runAgent(text, attachment: attachment, thinkHarder: thinkHarder, into: model)
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

    func openSettingsAI() { openSettings() }
}
