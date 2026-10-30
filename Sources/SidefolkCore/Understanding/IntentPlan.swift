import Foundation

/// What Return will do with words understood on the Mac (D62), in parts the one bar shows before anything happens:
/// the kind of thing, its words, its pieces (day, time, collection, how often) and the tool that will run it.
public struct IntentPlan: Sendable, Equatable {
    public var kind: String
    public var title: String
    public var chips: [String]
    /// The tool `LocalIntentRunner` calls, through `ToolExecutor` like any other; nil when nothing runs yet (a question
    /// back, quiet mode, a search).
    public var tool: String?
}

extension ParsedIntent {
    public func plan(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> IntentPlan {
        func day(_ date: Date) -> String { TimeFormat.day(date, now: now, calendar: calendar) }
        func clock(_ date: Date) -> String { TimeFormat.clock(date, calendar: calendar) }
        let inbox = String(localized: "Inbox")
        switch intent {
        case .remind(let title, let when, let recurrence, _, _):
            var chips = [day(when), clock(when)]
            if let recurrence { chips.append(TimeFormat.recurrence(recurrence, now: now, calendar: calendar)) }
            return IntentPlan(kind: String(localized: "Reminder"), title: title, chips: chips, tool: "reminders.create")
        case .note(let kind, let text, let collection, _):
            return IntentPlan(kind: String(localized: kind.wordResource), title: text, chips: [collection ?? inbox], tool: "notes.save")
        case .taskWithReminder(let text, let collection, _, let at):
            return IntentPlan(kind: String(localized: "Task"), title: text, chips: [collection ?? inbox, day(at), clock(at)], tool: "notes.save")
        case .aboutMe(let fact):
            return IntentPlan(kind: String(localized: "About you"), title: fact, chips: [], tool: "profile.remember")
        case .watch(let w):
            return IntentPlan(kind: String(localized: "New watch"), title: w.target, chips: w.contains.map { [$0] } ?? [], tool: "watch.create")
        case .report(let r):
            return IntentPlan(kind: String(localized: "Live value"), title: hint, chips: [], tool: r.everySeconds > 0 ? "watch.report" : nil)
        case .read:
            return IntentPlan(kind: String(localized: "Read now"), title: hint, chips: [], tool: "watch.read")
        case .companion:
            return IntentPlan(kind: String(localized: "Play"), title: hint, chips: [], tool: "companion.play")
        case .chance:
            return IntentPlan(kind: String(localized: "Play"), title: hint, chips: [], tool: "companion.toss")
        default:
            return IntentPlan(kind: hint, title: "", chips: [], tool: nil)
        }
    }
}

extension NotebookItem.Kind {
    /// "Note", "Idea", "Task", "Link".
    public var wordResource: LocalizedStringResource {
        switch self {
        case .note: "Note"
        case .idea: "Idea"
        case .task: "Task"
        case .link: "Link"
        }
    }
}
