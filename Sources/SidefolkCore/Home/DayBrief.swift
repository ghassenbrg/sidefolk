import Foundation

/// Today's brief (D84): one deterministic sentence under the greeting, made only of what the app knows (what needs
/// the person, what comes next, which watches noticed a change). No AI writes it, so it's the same every time the
/// same day is looked at.
public enum DayBrief {
    /// The lead, in bold: how many things need the person.
    public static func lead(needsYou: Int) -> String {
        switch needsYou {
        case 0: String(localized: "Nothing needs you.", comment: "Today's brief, first words: nothing waits on the person")
        case 1: String(localized: "One thing needs you.", comment: "Today's brief, first words")
        default: String(localized: "\(needsYou) things need you.", comment: "Today's brief, first words: how many things wait on the person")
        }
    }

    /// The rest: what comes next today, and what a watch noticed. Empty when there's nothing to say.
    /// - Parameters:
    ///   - next: the next event or reminder today, by title.
    ///   - changed: the watches whose change still waits to be seen, by title.
    public static func detail(next: (title: String, at: Date)?, changed: [String], calendar: Calendar = .autoupdatingCurrent) -> String {
        let change: String? = switch changed.count {
        case 0: nil
        case 1: String(localized: "\(changed[0]) changed", comment: "Today's brief: a watched page changed, “example.com/pricing changed”")
        default: String(localized: "\(changed.count) watched pages changed", comment: "Today's brief")
        }
        guard let next else {
            return change.map { String(localized: "\($0).", comment: "Today's brief: a sentence of one part, then its full stop") } ?? ""
        }
        let clock = TimeFormat.clock(next.at, calendar: calendar)
        if let change {
            return String(localized: "\(next.title) is at \(clock), and \(change).",
                          comment: "Today's brief: what comes next, then what a watch noticed: “Design review is at 16:30, and example.com/pricing changed.”")
        }
        return String(localized: "\(next.title) is at \(clock).", comment: "Today's brief: what comes next today, “Design review is at 16:30.”")
    }

    /// Good morning, afternoon or evening, with the person's first name when the Mac knows it. Between midnight and five
    /// it's neither evening nor morning, and "good night" is a goodbye: a plain hello.
    public static func greeting(at date: Date, name: String?, calendar: Calendar = .autoupdatingCurrent) -> String {
        let hour = calendar.component(.hour, from: date)
        let name = name?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        switch (hour, name) {
        case (0..<5, let name?): return String(localized: "Hello, \(name).", comment: "Today's greeting between midnight and five, with the person's first name")
        case (5..<12, let name?): return String(localized: "Good morning, \(name).", comment: "Today's greeting with the person's first name")
        case (12..<18, let name?): return String(localized: "Good afternoon, \(name).", comment: "Today's greeting with the person's first name")
        case (_, let name?): return String(localized: "Good evening, \(name).", comment: "Today's greeting with the person's first name")
        case (0..<5, nil): return String(localized: "Hello.", comment: "Today's greeting between midnight and five")
        case (5..<12, nil): return String(localized: "Good morning.", comment: "Today's greeting")
        case (12..<18, nil): return String(localized: "Good afternoon.", comment: "Today's greeting")
        default: return String(localized: "Good evening.", comment: "Today's greeting")
        }
    }
}

extension DayBrief {
    /// Today's "done today" (D88): what a person would call done. Reminders and tasks finished today, notes, ideas,
    /// tasks and links saved today, and other actions today that changed something. A read (a search, a list, another
    /// agent's status check) is not done, nor anything refused, failed or skipped; a call whose result the notebook or
    /// the reminders already count (saving a note, finishing a reminder or task) isn't counted twice.
    /// - Parameters:
    ///   - items: recent notebook items, the Trash left out.
    ///   - calls: recent tool calls from the activity log.
    ///   - changes: whether a tool changes something (`ToolSpec.mutates`); a tool no longer there counts as a read.
    public static func doneCount(reminders: [Reminder], items: [NotebookItem], calls: [ActivityEntry],
                                 changes: (String) -> Bool, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        func today(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: now) }
        let reminded = reminders.filter { $0.state == .done && today($0.lastFiredAt ?? $0.fireAt) }.count
        let saved = items.filter { $0.deletedAt == nil && today($0.createdAt) }.count
        let ticked = items.filter { $0.deletedAt == nil && $0.kind == .task && $0.status == .done && today($0.updatedAt) }.count
        let notDone: Set<ActivityEntry.Decision> = [.denied, .blocked, .failed, .skipped]
        let acted = calls.filter { call in
            today(call.at) && !notDone.contains(call.decision) && changes(call.tool) && !countedElsewhere(call)
        }.count
        return reminded + saved + ticked + acted
    }

    /// Saving a note and finishing a reminder or task are counted from the notebook and the reminders themselves.
    private static func countedElsewhere(_ call: ActivityEntry) -> Bool {
        switch call.tool {
        case "notes.save", "reminders.complete": true
        case "notes.update": call.args?.string("status")?.lowercased() == "done"
        default: false
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
