import Foundation

/// What carrying out a local intent produced, for the Ask panel.
public enum LocalOutcome: Sendable {
    case card(ResultCard, activityId: String, undo: Bool)
    case list(title: String, cards: [ResultCard])
    /// A reminder without a usable time: ask the user when. `reason` says why the words given were no use (it is nil when
    /// there were none) and `important` must be carried into the reminder made from the answer.
    case needsTime(title: String, reason: String?, important: Bool)
    /// A watch without an address ("tell me when the server is back up"): ask which address, e.g. "localhost:3000", then
    /// finish with `IntentParser.watch(address:kind:becomes:)`.
    case needsTarget(kind: String, becomes: String?)
    /// A weather report with no place: the card asks which, with a button to Settings › Privacy › Your location (D48).
    case needsPlace(ResultCard)
    case info(String)
    case failed(UserFacingError)
    /// The app ends the AI conversation: the agent runtime is the app's, not the core's (D45).
    case newConversation
}

/// Carries out what `IntentParser` understood, without any model: every change goes through
/// `ToolExecutor` as the user's own action, so it is audited and undoable like anything else.
public struct LocalIntentRunner: Sendable {
    public let runtime: SidefolkRuntime
    public init(runtime: SidefolkRuntime) { self.runtime = runtime }

    /// Slash commands are shortcuts for the same plain-language intents.
    public static func expandSlash(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("/") else { return t }
        let parts = t.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
        let rest = parts.count > 1 ? parts[1] : ""
        switch parts.first?.lowercased() ?? "" {
        case "note", "n": return "note: \(rest)"
        case "idea", "i": return "idea: \(rest)"
        case "todo", "task", "t": return "todo: \(rest)"
        case "remind", "r": return "remind me \(rest)"
        case "watch", "w": return "watch \(rest)"
        case "quiet", "q":
            // "/quiet 1h" means for an hour; "/quiet until 5pm" and "/quiet for 1 hour" already say which.
            let lower = rest.lowercased()
            if lower == "off" { return "quiet off" }
            if rest.isEmpty { return "be quiet" }
            return ["for ", "until ", "till ", "til "].contains { lower.hasPrefix($0) } ? "quiet \(rest)" : "quiet for \(rest)"
        case "find", "f", "search": return "find \(rest)"
        default: return t
        }
    }

    public func parse(_ text: String) async -> ParsedIntent? {
        let names = ((try? await runtime.notebook.collections()) ?? []).map(\.name)
        let watching = await runtime.watchers.list().map(WatchName.init)
        return runtime.intentParser.parse(Self.expandSlash(text), now: runtime.clock.now, knownCollections: names, watching: watching)
    }

    public func run(_ intent: LocalIntent) async -> LocalOutcome {
        switch intent {
        case .remind(let title, let when, let recurrence, let important, let anchor):
            var input: [String: JSONValue] = ["title": .string(title), "when": .string(ISO8601DateFormatter().string(from: when))]
            // "remind me about the report task …": the reminder belongs to that task when exactly one fits (D49).
            if let item = await referencedItem(title) {
                input["item"] = .string(item.id)
                input["title"] = .string(item.title)
            }
            // Only the user's own calls may carry it; it isn't in the schema models see.
            if let anchor, recurrence != nil { input["anchor"] = .string(ISO8601DateFormatter().string(from: anchor)) }
            // Only important reminders interrupt during quiet mode.
            if important { input["level"] = .string("critical") }
            if let r = recurrence {
                var rec: [String: JSONValue] = ["frequency": .string(r.frequency.rawValue), "interval": .number(Double(r.interval))]
                if !r.weekdays.isEmpty { rec["weekdays"] = .array(r.weekdays.map { .number(Double($0)) }) }
                // "every 30 minutes until 6pm": the hint promised the end, so the reminder keeps it.
                if let until = r.until { rec["until"] = .string(ISO8601DateFormatter().string(from: until)) }
                input["recurrence"] = .object(rec)
            }
            return await execute("reminders.create", .object(input))
        case .note(let kind, let text, let collection, let collectionKind):
            // The words are kept as typed; the title gets its capital letter here, like a reminder's.
            var input: [String: JSONValue] = ["text": .string(IntentParser.capitalizedNote(text)), "kind": .string(kind.rawValue)]
            if let collection { input["collection"] = .string(collection) }
            if collection != nil, let collectionKind { input["collection_kind"] = .string(collectionKind.rawValue) }
            return await execute("notes.save", .object(input))
        case .taskWithReminder(let text, let collection, let collectionKind, let remindAt):
            var input: [String: JSONValue] = ["text": .string(IntentParser.capitalizedNote(text)), "kind": "task",
                                              "remind": .string(ISO8601DateFormatter().string(from: remindAt))]
            if let collection { input["collection"] = .string(collection) }
            if collection != nil, let collectionKind { input["collection_kind"] = .string(collectionKind.rawValue) }
            return await execute("notes.save", .object(input))
        case .aboutMe(let fact):
            return await execute("profile.remember", ["fact": .string(fact)])
        case .watch(let w):
            var input: [String: JSONValue] = ["kind": .string(w.kind), "target": .string(w.target)]
            if w.kind == "site_status" {
                input["becomes"] = .string(w.contains == "down" ? "down" : "up")
            } else if let contains = w.contains {
                input["contains"] = .string(contains)
            }
            return await execute("watch.create", .object(input))
        case .report(let r):
            var input = Self.input(for: r.source)
            input["every_seconds"] = .number(r.everySeconds)
            if let until = r.until { input["until"] = .string(until) }
            if r.untilStopped { input["until_stopped"] = true }
            if r.notify { input["notify"] = true }
            return await execute("watch.report", .object(input))
        case .stopWatch(let ids, let words):
            return await stop(ids, words: words)
        case .quiet(let until):
            await runtime.settings.update { $0.quietUntil = until ?? .distantFuture }
            await runtime.attention.update { $0.quiet = true }
            let title = until.map { String(localized: "Quiet until \(TimeFormat.when($0, now: runtime.clock.now, calendar: .autoupdatingCurrent)).") }
                ?? String(localized: "Quiet until you turn it off.")
            return .card(ResultCard(kind: .info, title: title, subtitle: String(localized: "Only urgent things will interrupt you.")),
                         activityId: "", undo: false)
        case .quietOff:
            await runtime.settings.update { $0.quietUntil = nil }
            await runtime.attention.update { $0.quiet = false }
            return .card(ResultCard(kind: .info, title: String(localized: "Quiet is off.")), activityId: "", undo: false)
        case .find(let query, let kind, let collection):
            return await find(query: query, kind: kind, collection: collection)
        case .needsTime(let title, let reason, let important):
            return .needsTime(title: title, reason: reason, important: important)
        case .needsTarget(let kind, let becomes):
            return .needsTarget(kind: kind, becomes: becomes)
        case .needsPlace:
            return .needsPlace(PlaceNeeded.card)
        case .companion(let act):
            return await execute("companion.play", ["act": .string(act.rawValue)])
        case .newConversation:
            return .newConversation
        case .read(let source):
            return await execute("watch.read", .object(Self.input(for: source)))
        case .chance(let c):
            var input: [String: JSONValue] = ["kind": .string(c.kind.rawValue), "count": .number(Double(c.count))]
            if c.kind == .dice { input["sides"] = .number(Double(c.sides)); input["modifier"] = .number(Double(c.modifier)) }
            if c.kind == .rockPaperScissors {
                // The companion shows its hand only once the person has chosen theirs: then "rock" alone plays it.
                guard let hand = c.hand else { return .info(String(localized: "Rock, paper or scissors? Say yours.")) }
                input["hand"] = .string(hand.rawValue)
            }
            return await execute("companion.toss", .object(input))
        }
    }

    /// What a report or a reading reads, as `watch.report` and `watch.read` take it.
    static func input(for source: ReportIntent.Source) -> [String: JSONValue] {
        switch source {
        case .metric(let metric): ["source": "metric", "metric": .string(metric.rawValue)]
        case .weather(let place, let quantity): ["source": "weather", "place": .string(place), "quantity": .string(quantity.rawValue)]
        }
    }

    /// The note or task a reminder's title names ("the report task"), when exactly one in the notebook fits.
    private func referencedItem(_ title: String) async -> NotebookItem? {
        guard let reference = IntentParser.itemReference(in: title) else { return nil }
        // Facts in About you are no reminder's business.
        let profile = try? await NotebookCollections.profile(runtime.notebook, create: false)
        let candidates = ((try? await runtime.notebook.items(kinds: [reference.kind], limit: 1000)) ?? []).filter { $0.collectionId != profile?.id }
        return IntentParser.referencedItem(reference.name, among: candidates)
    }

    /// Stops what the words named, through `watch.stop` like any other stop. Several matches are named back
    /// rather than all stopped: "stop the temperature" with two cities should ask which.
    private func stop(_ ids: [String], words: String) async -> LocalOutcome {
        let said = words.trimmingCharacters(in: .whitespaces).clipped(40)
        guard !ids.isEmpty else {
            return .info(said.isEmpty ? String(localized: "I'm not showing or watching anything right now.")
                : String(localized: "I'm not showing or watching anything like “\(said)”."))
        }
        guard ids.count == 1 else {
            let titles = await runtime.watchers.list().filter { ids.contains($0.id) }.map { "“\($0.title)”" }
            return .info(String(localized: "That could be \(Wording.list(titles)). Which one should I stop?"))
        }
        return await execute("watch.stop", ["id": .string(ids[0])])
    }

    private func execute(_ tool: String, _ input: JSONValue) async -> LocalOutcome {
        let out = await runtime.executor.execute(name: tool, input: input, caller: .user)
        guard case .ok(let result) = out.status else { return .failed(out.problem!) }
        let card = result.card ?? ResultCard(kind: .info, title: result.text.clipped(120))
        return .card(card, activityId: out.activity.id, undo: out.activity.undoAvailable)
    }

    private func find(query: String, kind: NotebookItem.Kind?, collection: String?) async -> LocalOutcome {
        let notebook = runtime.notebook
        let target = collection == nil ? nil : try? await notebook.findCollection(named: collection!)
        let kinds = kind.map { [$0] }
        let items: [NotebookItem]
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            items = (try? await notebook.items(collectionId: target?.id, kinds: kinds, limit: 20)) ?? []
        } else {
            items = (try? await notebook.search(query, collectionId: target?.id, kinds: kinds, limit: 20)) ?? []
        }
        let names = Dictionary(uniqueKeysWithValues: ((try? await notebook.collections(includeArchived: true)) ?? [])
            .map { ($0.id, NotebookCollections.shownName($0)) })
        let cards = items.map { item in
            ResultCard(kind: .note, title: item.title, subtitle: [names[item.collectionId], TimeFormat.day(item.updatedAt, now: runtime.clock.now, calendar: .autoupdatingCurrent)]
                .compactMap { $0 }.joined(separator: " · "), refId: item.id, url: item.url, itemKind: item.kind)
        }
        let title: String
        if !query.isEmpty, kind == nil {
            title = String(localized: "Found for “\(query.clipped(30))”")
        } else {
            let what = kind.map(NoteText.plural) ?? String(localized: "Results", comment: "Title of notebook search results of every kind: “Results in Sidefolk”")
            title = target.map { String(localized: "\(what) in \(NotebookCollections.shownName($0))", comment: "A thing, then where it is: “Ideas in Sidefolk”, “Claude Code in sidefolk”") } ?? what
        }
        return .list(title: "\(title) (\(cards.count))", cards: cards)
    }
}
