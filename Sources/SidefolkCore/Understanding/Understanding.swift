import Foundation

/// What the Say bar understood, before Return (D84, principle 4): one plain sentence of what will happen, its parts as
/// chips, and whether AI is involved. Made from the same parse that runs the words (`ParsedIntent`, `IntentPlan`), so
/// what it promises is what Return does.
public struct Understanding: Sendable, Equatable {
    public struct Chip: Sendable, Equatable {
        public enum Role: Sendable, Equatable {
            /// What it is: a reminder, a note, a watch.
            case kind
            /// When, how often, where it goes.
            case detail
            /// Done on this Mac, no AI.
            case local
            /// Goes to the AI the person chose.
            case ai
        }

        public var symbol: String
        public var text: String
        public var role: Role
    }

    public var sentence: String
    public var chips: [Chip]
    /// Return does it on this Mac, without AI.
    public var local: Bool

    public init(sentence: String, chips: [Chip], local: Bool) {
        self.sentence = sentence
        self.chips = chips
        self.local = local
    }

    /// Words only the AI can answer: who answers, and that it is a question for them.
    public static func ai(_ provider: String) -> Understanding {
        Understanding(sentence: String(localized: "I'll ask \(provider).", comment: "The Say bar, before Return: the AI that answers (“Claude”)"),
                      chips: [Chip(symbol: "questionmark.bubble", text: String(localized: "Question", comment: "A chip under the Say bar: the words are a question for the AI"), role: .kind),
                              Chip(symbol: "sparkles", text: String(localized: "Uses \(provider)", comment: "A chip under the Say bar: the AI that answers (“Uses Claude”)"), role: .ai)],
                      local: false)
    }

    /// Words that need AI while none is set up.
    public static var noAI: Understanding {
        Understanding(sentence: String(localized: "That needs AI, which isn't set up. I can still remind, note and watch."),
                      chips: [Chip(symbol: "sparkles", text: String(localized: "Needs AI"), role: .ai)], local: false)
    }
}

extension ParsedIntent {
    /// The sentence and chips for these words. `now` and `calendar` read times as the runner will.
    public func understanding(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Understanding {
        let plan = plan(now: now, calendar: calendar)
        var chips: [Understanding.Chip] = []
        if let symbol = Self.symbol(intent), plan.tool != nil || !plan.title.isEmpty {
            chips.append(.init(symbol: symbol, text: plan.kind, role: .kind))
        }
        if case .watch(let w) = intent, let every = Self.watchTarget(w) {
            chips.append(.init(symbol: "globe", text: every, role: .detail))
        }
        for (i, part) in plan.chips.enumerated() {
            chips.append(.init(symbol: Self.detailSymbol(intent, index: i), text: part, role: .detail))
        }
        chips.append(.init(symbol: "checkmark.circle", text: String(localized: "On this Mac, no AI", comment: "A chip under the Say bar: done here without AI"),
                           role: .local))
        return Understanding(sentence: sentence(now: now, calendar: calendar), chips: chips, local: true)
    }

    private func sentence(now: Date, calendar: Calendar) -> String {
        switch intent {
        case .remind(let title, _, let recurrence, _, _):
            return recurrence == nil ? String(localized: "I'll remind you: “\(title)”.", comment: "The Say bar, before Return; the reminder's words")
                : String(localized: "I'll remind you each time: “\(title)”.", comment: "The Say bar, before Return: a repeating reminder")
        case .note(let kind, _, let collection, _):
            let place = collection ?? String(localized: "Inbox")
            return kind == .task ? String(localized: "I'll add this task to \(place).", comment: "The Say bar, before Return; a collection")
                : String(localized: "I'll save this to \(place).", comment: "The Say bar, before Return; a collection")
        case .taskWithReminder(_, let collection, _, _):
            return String(localized: "I'll add this task to \(collection ?? String(localized: "Inbox")) and remind you then.",
                          comment: "The Say bar, before Return; a collection")
        case .aboutMe:
            return String(localized: "I'll remember this about you.")
        case .watch(let w):
            let target = Self.watchTarget(w) ?? w.target
            switch w.kind {
            case "site_status":
                return w.contains == "down" ? String(localized: "I'll tell you if \(target) goes down.", comment: "The Say bar, before Return; a site")
                    : String(localized: "I'll tell you when \(target) is up.", comment: "The Say bar, before Return; a site")
            case "file_appears", "folder_new_file":
                return String(localized: "I'll tell you when a file turns up there.")
            case "process_exits":
                return String(localized: "I'll tell you when \(target) stops.", comment: "The Say bar, before Return; a program's name")
            default:
                return String(localized: "I'll check \(target) and tell you when it changes.", comment: "The Say bar, before Return; a page")
            }
        case .report:
            return String(localized: "I'll keep this value beside me, up to date.")
        case .read:
            return String(localized: "I'll read it now.")
        case .stopWatch(let ids, _):
            return ids.isEmpty ? String(localized: "I'll look for what to stop.") : String(localized: "I'll stop watching that.")
        case .quiet(let until):
            return until.map { String(localized: "I'll keep quiet until \(TimeFormat.clock($0, calendar: calendar)).", comment: "The Say bar, before Return; a time") }
                ?? String(localized: "I'll keep quiet until you say so.")
        case .quietOff:
            return String(localized: "I'll stop keeping quiet.")
        case .find:
            return String(localized: "I'll look through your notebook.")
        case .listing:
            return String(localized: "I'll read it now.")
        case .needsTime:
            return String(localized: "I'll ask when to remind you.")
        case .needsTarget:
            return String(localized: "I'll ask what to watch.")
        case .needsPlace:
            return String(localized: "I'll ask where you are.")
        case .companion:
            return String(localized: "Let's play.")
        case .surface:
            return String(localized: "An extension shows this.", comment: "The Say bar, before Return: the sentence opens an extension's panel")
        case .newConversation:
            return String(localized: "Your next question starts a new conversation.")
        case .extensionCommand:
            return String(localized: "An extension answers this.")
        }
    }

    /// A watched address without its scheme, as people say it.
    private static func watchTarget(_ w: WatchIntent) -> String? {
        guard w.kind == "url_change" || w.kind == "site_status", let url = URL(string: w.target), let host = url.host else { return nil }
        let path = url.path == "/" ? "" : url.path
        return host + path
    }

    private static func symbol(_ intent: LocalIntent) -> String? {
        switch intent {
        case .remind, .needsTime: "alarm"
        case .note(let kind, _, _, _): kind == .task ? "checkmark.square" : "note.text"
        case .taskWithReminder: "checkmark.square"
        case .aboutMe: "person.text.rectangle"
        case .watch, .stopWatch, .needsTarget: "binoculars"
        case .report, .read, .needsPlace: "gauge.with.dots.needle.33percent"
        case .companion: "gamecontroller"
        case .surface: "puzzlepiece.extension"
        case .quiet, .quietOff: "moon"
        case .find: "magnifyingglass"
        case .listing: "list.bullet"
        case .newConversation: "square.and.pencil"
        case .extensionCommand: "puzzlepiece.extension"
        }
    }

    private static func detailSymbol(_ intent: LocalIntent, index: Int) -> String {
        switch intent {
        case .remind: index == 0 ? "calendar" : index == 1 ? "clock" : "repeat"
        case .taskWithReminder: index == 0 ? "tray" : index == 1 ? "calendar" : "clock"
        case .note: "tray"
        default: "text.quote"
        }
    }
}
