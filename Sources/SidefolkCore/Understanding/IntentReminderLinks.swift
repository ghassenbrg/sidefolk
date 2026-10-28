import Foundation

/// Reminders that belong to a note or task (D49), in words: "add a task to call mom at 5" saves the task and its
/// reminder; "remind me about the report task tomorrow at 9" sets a reminder the runner ties to that task when exactly
/// one task fits.
extension IntentParser {
    /// "add a task to call mom at 5", "create a todo to book the flights": the words after "to" are the task.
    static let taskTo = IntentPattern(
        #"(?:add|create|make|set\s+up|new)\s+(?:a\s+|an\s+|another\s+|one\s+more\s+)?(?:new\s+)?(?:task|todo|to-do)\s+(?:for\s+me\s+)?to\s+(?<text>.+)"#,
        multiline: true)

    /// A word that makes the end of a task a time ("at 5", "tomorrow", "friday"), not a number it needs ("read chapter 5").
    private static let timeMarker = Scan(
        #"\b(?:at|by|on|in|tomorrow|today|tonight|this|next|morning|afternoon|evening|noon|midnight|mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b|\d:\d{2}|\d\s*(?:am|pm)\b"#)

    /// A task whose words end with a time: the task without it, and when to remind. Only a time at the very end, read
    /// with confidence and still ahead, on one line. Never a repeat: a chore done once would end its whole series.
    func taskTime(_ text: String, _ ctx: Context) -> (title: String, date: Date)? {
        guard !text.contains(where: \.isNewline) else { return nil }
        let rest = Self.rewriteTimeWords(text.trimmingCharacters(in: CharacterSet(charactersIn: " .!")))
        guard let found = when.parse(rest, now: ctx.now), found.recurrence == nil, found.confidence != .low,
              !found.isExplicitInstant, found.date > ctx.now,
              found.range.upperBound == rest.endIndex, Self.timeMarker.found(in: found.matched) else { return nil }
        let title = Self.cleanTitle(found.remaining)
        guard !title.isEmpty, !Self.leavesTimeWords(title: title, left: found.remaining, rest: rest) else { return nil }
        return (title, found.date)
    }

    /// The hint for a task with its reminder: "Task → Inbox · Reminder · Tomorrow 17:00 · no AI".
    func taskWithReminder(_ title: String, at date: Date, collection: String?, collectionKind: NotebookCollection.Kind?, _ ctx: Context) -> ParsedIntent {
        ParsedIntent(intent: .taskWithReminder(text: title, collection: collection, collectionKind: collectionKind, remindAt: date),
                     hint: ParsedIntent.hint("\(Self.label(.task)) → \(collection ?? String(localized: "Inbox"))", String(localized: "Reminder"),
                                             TimeFormat.when(date, now: ctx.now, calendar: when.calendar)))
    }

    private static let itemKind = #"(?<kind>task|todo|to-do|note|idea)"#
    private static let itemReferences = [
        // "the report task", "my dentist note"
        IntentPattern(#"(?:about\s+)?(?:the|my|our|that|this)\s+(?<name>.+?)\s+"# + itemKind),
        // "the task “Send the report”", "my note called groceries"
        IntentPattern(#"(?:about\s+)?(?:the|my|our|that|this)\s+"# + itemKind + #"\s+(?:called\s+|named\s+|about\s+)?(?<name>.+)"#),
    ]

    /// A reminder's title that points at a note or task by name: the name and the kind, for the runner to look up.
    public static func itemReference(in title: String) -> (name: String, kind: NotebookItem.Kind)? {
        for pattern in itemReferences {
            guard let c = pattern.match(title), let name = c["name"]?.unquoted, let word = c["kind"] else { continue }
            let clean = name.trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”‘’"))
            guard !clean.isEmpty else { continue }
            return (clean, kind(of: word))
        }
        return nil
    }

    /// The one item a reference means: the title said exactly, or else the only one whose title holds those words.
    /// Tasks must still be open. Two candidates mean nothing is certain, so nil.
    public static func referencedItem(_ name: String, among items: [NotebookItem]) -> NotebookItem? {
        func words(_ s: String) -> [Substring] {
            s.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) })
        }
        let wanted = words(name)
        guard !wanted.isEmpty else { return nil }
        let live = items.filter { $0.deletedAt == nil && !($0.kind == .task && $0.status == .done) }
        let exact = live.filter { words($0.title) == wanted }
        if exact.count == 1 { return exact[0] }
        guard exact.isEmpty else { return nil }
        let containing = live.filter { item in
            let have = words(item.title)
            guard have.count >= wanted.count else { return false }
            return (0...(have.count - wanted.count)).contains { Array(have[$0..<($0 + wanted.count)]) == wanted }
        }
        return containing.count == 1 ? containing[0] : nil
    }
}
