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

    /// Good morning, afternoon or evening, with the person's first name when the Mac knows it.
    public static func greeting(at date: Date, name: String?, calendar: Calendar = .autoupdatingCurrent) -> String {
        let hour = calendar.component(.hour, from: date)
        let name = name?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        switch (hour, name) {
        case (5..<12, let name?): return String(localized: "Good morning, \(name).", comment: "Today's greeting with the person's first name")
        case (12..<18, let name?): return String(localized: "Good afternoon, \(name).", comment: "Today's greeting with the person's first name")
        case (_, let name?): return String(localized: "Good evening, \(name).", comment: "Today's greeting with the person's first name")
        case (5..<12, nil): return String(localized: "Good morning.", comment: "Today's greeting")
        case (12..<18, nil): return String(localized: "Good afternoon.", comment: "Today's greeting")
        default: return String(localized: "Good evening.", comment: "Today's greeting")
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
