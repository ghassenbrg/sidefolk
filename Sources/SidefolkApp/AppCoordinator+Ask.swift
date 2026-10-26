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
        }, codexBackend: { provider, thinkHarder in
            CodexBackend.make(provider: provider, thinkHarder: thinkHarder, paths: paths, helperPath: helper, registry: tokens)
        })
        let settings = runtime.settings
        return AgentRuntime(executor: runtime.executor, db: runtime.db, events: runtime.events, context: context,
                            factory: factory, settings: { settings.current })
    }
}

extension AppCoordinator: AskActions {
    func hint(for text: String) -> String? {
        if let title = ask.pendingReminderTitle {
            guard let when = whenParser.parse(text, now: Date()) else {
                return String(localized: "When should I remind you to “\(title.clipped(30))”?")
            }
            return String(localized: "Reminder · \(TimeFormat.when(when.date, now: Date(), calendar: .autoupdatingCurrent)) · no AI")
        }
        if let parsed = runtime.intentParser.parse(LocalIntentRunner.expandSlash(text), now: Date(), knownCollections: knownCollections) {
            return parsed.hint
        }
        return runtime.settings.current.provider.kind == .none ? String(localized: "Needs AI — not set up yet")
            : String(localized: "Ask \(providerLabel)")
    }

    var whenParser: WhenParser { WhenParser(calendar: .autoupdatingCurrent, settings: runtime.settings.current) }

    var providerLabel: String {
        let provider = runtime.settings.current.provider
        switch provider.kind {
        case .none: return String(localized: "no AI")
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        case .anthropic: return String(localized: "Claude (API)")
        case .openAICompatible:
            let model = provider.model.isEmpty ? provider.preset.defaultModel(available: nil) ?? "" : provider.model
            return model.isEmpty ? provider.preset.name : model
        }
    }

    func submit(_ text: String, attachment: Attachment?, thinkHarder: Bool, into model: AskModel) {
        // A reminder that was waiting for its time: only a time (or "cancel") answers it; anything
        // else is a new request and the pending one is dropped.
        if let title = model.pendingReminderTitle, attachment == nil {
            let lower = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            // Typed commands are understood in English without AI (D28); the words shown are localized.
            if ["cancel", "never mind", "nevermind", "nvm", "forget it", "no", "stop"].contains(lower) {
                model.pendingReminderTitle = nil
                model.add(.info(String(localized: "Okay, no reminder.")), caption: text)
                return
            }
            if let when = runtime.intentParser.parseTime(text, now: Date()), when.date > Date(),
               when.remaining.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).isEmpty {
                model.pendingReminderTitle = nil
                runLocal(.remind(title: title, when: when.date, recurrence: when.recurrence, important: model.pendingReminderImportant),
                         caption: "\(title) — \(text)", into: model)
                return
            }
            model.pendingReminderTitle = nil
        }
        // A watch that was waiting for its address.
        if let pending = model.pendingWatch, attachment == nil {
            model.pendingWatch = nil
            if let parsed = runtime.intentParser.watch(address: text, kind: pending.kind, becomes: pending.becomes) {
                runLocal(parsed.intent, caption: text, into: model)
                return
            }
        }
        // Plain-language intents complete locally, instantly, without AI (DECISIONS D4). Words typed
        // with a dropped item are understood too; the item rides along as the note or reminder detail.
        if !thinkHarder,
           let parsed = runtime.intentParser.parse(LocalIntentRunner.expandSlash(text), now: Date(), knownCollections: knownCollections) {
            runLocal(Self.withAttachment(parsed.intent, attachment), caption: text, into: model)
            return
        }
        guard runtime.settings.current.provider.kind != .none else {
            let full = attachment?.text.map { "\(text)\n\n\($0)" } ?? text
            model.add(.needsBrain(full, guess: reminderGuess(text)), caption: text)
            return
        }
        runAgent(text, attachment: attachment, thinkHarder: thinkHarder, into: model)
    }

    /// "call the bank tomorrow at 9" → a reminder suggestion, when a confident future time is in there.
    func reminderGuess(_ text: String) -> ReminderGuess? {
        guard let when = whenParser.parse(text, now: Date()), when.confidence != .low, when.date > Date() else { return nil }
        var title = when.remaining.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for prefix in ["to ", "that "] where title.lowercased().hasPrefix(prefix) { title = String(title.dropFirst(prefix.count)) }
        guard title.count >= 2 else { return nil }
        title = title.prefix(1).uppercased() + title.dropFirst()
        let label = String(localized: "Remind me \(TimeFormat.when(when.date, now: Date(), calendar: .autoupdatingCurrent))",
                           comment: "A button: “Remind me Tomorrow 09:00”")
        return ReminderGuess(title: title, when: when.date, recurrence: when.recurrence, label: label)
    }

    /// Puts what was dropped into the note body or the reminder's notes.
    static func withAttachment(_ intent: LocalIntent, _ attachment: Attachment?) -> LocalIntent {
        guard let attachment, let detail = attachment.text ?? Optional(attachment.label) else { return intent }
        switch intent {
        case .note(let kind, let text, let collection, let collectionKind):
            return .note(kind: kind, text: text + "\n\n" + detail, collection: collection, collectionKind: collectionKind)
        default:
            return intent
        }
    }

    func runLocal(_ intent: LocalIntent, caption: String?, into model: AskModel) {
        let runner = LocalIntentRunner(runtime: runtime)
        Task {
            let outcome = await runner.run(intent)
            switch outcome {
            case .card(let card, let activityId, let undo):
                model.add(.result(card, activityId: activityId.isEmpty ? nil : activityId, undo: undo), caption: caption)
                // Quick intents close the panel a moment after their card appears.
                try? await Task.sleep(for: .seconds(undo ? 2.5 : 1.2))
                if !model.busy, model.text.isEmpty, model.pendingQuestion == nil, model.entries.last?.caption == caption {
                    model.onAutoClose?()
                }
            case .list(let title, let cards):
                model.add(.list(title: title, cards: cards), caption: caption)
            case .needsTime(let title, let reason, let important):
                model.pendingReminderTitle = title
                model.pendingReminderImportant = important
                let question = String(localized: "When should I remind you to “\(title.prefix(1).lowercased() + title.dropFirst())”?")
                model.add(.info([reason, question].compactMap { $0 }.joined(separator: " ")), caption: caption)
                model.focusRequest += 1
            case .needsTarget(let kind, let becomes):
                model.pendingWatch = (kind, becomes)
                model.add(.info(String(localized: "Which address should I watch? For example localhost:3000 or example.com/status.")), caption: caption)
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
        model.phase = Self.thinkingLine(harder: thinkHarder)
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
                    model.phase = Self.thinkingLine(harder: thinkHarder)
                case .phase(.working(let category)):
                    model.phase = Self.phaseLine(category)
                case .phase(.waitingForApproval):
                    model.phase = String(localized: "Waiting for your OK…")
                case .toolFinished(let activity, let ok):
                    // Read-only results feed the answer; only changes become cards (DECISIONS D5).
                    if ok, activity.mutates, let card = activity.card {
                        shownCards.insert(card.title)
                        model.add(.result(card, activityId: activity.id, undo: activity.undoAvailable), caption: caption())
                    }
                    // What the mode answered for the person, and what nobody answered, always show (D37).
                    if ok, activity.actedWithoutAsking {
                        model.add(.doneWithoutAsking(activity.summary, fullAccess: activity.decision == .fullAccess), caption: caption())
                    }
                    if activity.decision == .skipped {
                        model.add(.skipped(activity.summary, why: activity.error ?? ""), caption: caption())
                    }
                case .reply(let reply):

                    let answer = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !answer.isEmpty {
                        model.add(.answer(answer, canThinkHarder: !thinkHarder && runtime.settings.current.provider.smartModel != "",
                                          tainted: reply.tainted),
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

    static func thinkingLine(harder: Bool) -> String {
        harder ? String(localized: "Thinking harder…") : String(localized: "Thinking…")
    }

    static func phaseLine(_ category: ToolCategory) -> String {
        switch category {
        case .notes: String(localized: "Writing it down…")
        case .memory: String(localized: "Remembering…")
        case .time: String(localized: "Setting the reminder…")
        case .watch: String(localized: "Setting up the watch…")
        case .files: String(localized: "Looking at your files…")
        case .web: String(localized: "Reading the page…")
        case .system: String(localized: "Working on it…")
        case .agents: String(localized: "Checking on your agents…")
        case .extensions: String(localized: "Using an extension…")
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
                    model.add(.info(String(localized: "Undone: \(label).")))
                } else {
                    model.add(.info(String(localized: "That can't be undone anymore.")))
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

    func saveAnswer(_ text: String, tainted: Bool, in model: AskModel) {
        Task {
            // The user's click, but not the user's words when the turn read outside content (SECURITY T2).
            let out = await runtime.executor.execute(name: "notes.save", input: ["text": .string(text)], caller: .user, tainted: tainted)
            if case .ok(let r) = out.status {
                if let card = r.card { model.add(.result(card, activityId: out.activity.id, undo: out.activity.undoAvailable)) }
            } else if let problem = out.problem {
                model.add(.error(problem, retryable: false))
            }
        }
    }

    func saveAsTask(_ text: String, in model: AskModel) {
        runLocal(.note(kind: .task, text: text, collection: nil), caption: nil, into: model)
    }

    func remind(_ guess: ReminderGuess, in model: AskModel) {
        runLocal(.remind(title: guess.title, when: guess.when, recurrence: guess.recurrence), caption: nil, into: model)
    }

    func askWhen(toRemind text: String, in model: AskModel) {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines).clipped(80)
        model.pendingReminderTitle = title
        model.pendingReminderImportant = false
        model.add(.info(String(localized: "When should I remind you to “\(title)”?")), caption: nil)
        model.focusRequest += 1
    }

    func reminderTimes() -> [(label: String, date: Date)] {
        let settings = runtime.settings.current
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        func at(_ hour: Int, daysFromNow days: Int) -> Date? {
            calendar.date(byAdding: .day, value: days, to: now).flatMap { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: $0) }
        }
        var times: [(label: String, date: Date)] = [(String(localized: "In 1 hour"), now.addingTimeInterval(3600))]
        if let evening = at(settings.eveningHour, daysFromNow: 0), evening > now.addingTimeInterval(3600) {
            times.append((String(localized: "This evening"), evening))
        }
        if let morning = at(settings.morningHour, daysFromNow: 1) { times.append((String(localized: "Tomorrow"), morning)) }
        return times
    }

    func remindPending(at date: Date, in model: AskModel) {
        guard let title = model.pendingReminderTitle, date > Date() else { return }
        model.pendingReminderTitle = nil
        runLocal(.remind(title: title, when: date, recurrence: nil, important: model.pendingReminderImportant), caption: title, into: model)
    }

    func answer(question: AttentionItem, actionId: String) {
        ask.removeQuestion(id: question.id)
        Task { await runtime.attention.respond(id: question.id, actionId: actionId) }
    }

    func retry(_ text: String, in model: AskModel) {
        model.text = text
        model.submit()
    }

    /// What dropping something on the companion leads to, without AI.
    func perform(_ action: DropAction, with attachment: Attachment, in model: AskModel) {
        model.attachment = nil
        switch (action, attachment.kind) {
        case (.save, .url(let url)):
            runLocal(.note(kind: .link, text: (url.host ?? url.absoluteString) + "\n" + url.absoluteString, collection: nil),
                     caption: attachment.label, into: model)
        case (.save, .file(let file)):
            runLocal(.note(kind: .note, text: file.lastPathComponent + "\n" + FolderAccess.displayPath(file.path), collection: nil),
                     caption: attachment.label, into: model)
        case (.save, .text):
            runLocal(.note(kind: .note, text: attachment.text ?? attachment.label, collection: nil), caption: attachment.label, into: model)
        case (.remind, _):
            let title: String = switch attachment.kind {
            case .url(let url): url.host.map { String(localized: "Look at \($0)") } ?? String(localized: "Look at the link")
            case .file(let file): String(localized: "Look at \(file.lastPathComponent)")
            case .text: (attachment.text ?? attachment.label).clipped(80)
            }
            model.pendingReminderTitle = title
            model.add(.info(String(localized: "When should I remind you to “\(title)”?")), caption: attachment.label)
            model.focusRequest += 1
        case (.watch, .url(let url)):
            runLocal(.watch(WatchIntent(kind: "url_change", target: url.absoluteString)), caption: attachment.label, into: model)
        case (.watch, .file(let file)):
            var isDir: ObjCBool = false
            let folder = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir) && isDir.boolValue
            runLocal(.watch(WatchIntent(kind: folder ? "folder_new_file" : "file_changes", target: file.path)),
                     caption: attachment.label, into: model)
        case (.watch, .text):
            model.add(.info(String(localized: "I can watch links and files, not text.")))
        case (.ask, _):
            model.attachment = attachment
            model.add(.info(String(localized: "What should I do with \(attachment.label)? Type it below.")))
            model.focusRequest += 1
        }
    }
}
