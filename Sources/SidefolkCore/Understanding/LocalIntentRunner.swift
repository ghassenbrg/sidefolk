import Foundation

/// What carrying out a local intent produced, for the Ask panel.
public enum LocalOutcome: Sendable {
    case card(ResultCard, activityId: String, undo: Bool)
    case list(title: String, cards: [ResultCard])
    /// A reminder without a usable time: ask the user when.
    case needsTime(title: String)
    case info(String)
    case failed(UserFacingError)
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
        case "quiet", "q": return rest.lowercased() == "off" ? "quiet off" : (rest.isEmpty ? "be quiet" : "quiet for \(rest)")
        case "find", "f", "search": return "find \(rest)"
        default: return t
        }
    }

    public func parse(_ text: String) async -> ParsedIntent? {
        let names = ((try? await runtime.notebook.collections()) ?? []).map(\.name)
        return runtime.intentParser.parse(Self.expandSlash(text), now: runtime.clock.now, knownCollections: names)
    }

    public func run(_ intent: LocalIntent) async -> LocalOutcome {
        switch intent {
        case .remind(let title, let when, let recurrence):
            var input: [String: JSONValue] = ["title": .string(title), "when": .string(ISO8601DateFormatter().string(from: when))]
            if let r = recurrence {
                var rec: [String: JSONValue] = ["frequency": .string(r.frequency.rawValue), "interval": .number(Double(r.interval))]
                if !r.weekdays.isEmpty { rec["weekdays"] = .array(r.weekdays.map { .number(Double($0)) }) }
                input["recurrence"] = .object(rec)
            }
            return await execute("reminders.create", .object(input))
        case .note(let kind, let text, let collection):
            var input: [String: JSONValue] = ["text": .string(text), "kind": .string(kind.rawValue)]
            if let collection { input["collection"] = .string(collection) }
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
        case .quiet(let until):
            await runtime.settings.update { $0.quietUntil = until ?? .distantFuture }
            await runtime.attention.update { $0.quiet = true }
            let label = until.map { "until \(TimeFormat.when($0, now: runtime.clock.now, calendar: .autoupdatingCurrent))" } ?? "until you turn it off"
            return .card(ResultCard(kind: .info, title: "Quiet \(label).", subtitle: "Only urgent things will interrupt you."),
                         activityId: "", undo: false)
        case .quietOff:
            await runtime.settings.update { $0.quietUntil = nil }
            await runtime.attention.update { $0.quiet = false }
            return .card(ResultCard(kind: .info, title: "Quiet is off."), activityId: "", undo: false)
        case .find(let query, let kind, let collection):
            return await find(query: query, kind: kind, collection: collection)
        case .needsTime(let title):
            return .needsTime(title: title)
        }
    }

    private func execute(_ tool: String, _ input: JSONValue) async -> LocalOutcome {
        let out = await runtime.executor.execute(name: tool, input: input, caller: .user)
        switch out.status {
        case .ok(let result):
            let card = result.card ?? ResultCard(kind: .info, title: result.text.clipped(120))
            return .card(card, activityId: out.activity.id, undo: out.activity.undoAvailable)
        case .denied(let why):
            return .failed(UserFacingError(why))
        case .failed(let error):
            return .failed(error)
        }
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
        let names = Dictionary(uniqueKeysWithValues: ((try? await notebook.collections(includeArchived: true)) ?? []).map { ($0.id, $0.name) })
        let cards = items.map { item in
            ResultCard(kind: .note, title: item.title, subtitle: [names[item.collectionId], TimeFormat.day(item.updatedAt, now: runtime.clock.now, calendar: .autoupdatingCurrent)]
                .compactMap { $0 }.joined(separator: " · "), refId: item.id, url: item.url)
        }
        var title = kind.map { "\($0.rawValue.capitalized)s" } ?? "Found"
        if let target { title += " in \(target.name)" }
        if !query.isEmpty, kind == nil { title = "Found for “\(query.clipped(30))”" }
        return .list(title: "\(title) (\(cards.count))", cards: cards)
    }
}
