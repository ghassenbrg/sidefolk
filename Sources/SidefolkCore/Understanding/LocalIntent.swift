import Foundation

/// A thing to watch, in the vocabulary of the watcher kinds (docs/PRODUCT.md, "Watchers").
public struct WatchIntent: Sendable, Equatable {
    /// `url_change`, `site_status`, `file_appears`, `folder_new_file` or `process_exits`.
    public var kind: String
    /// A URL with its scheme, an absolute file or folder path, or a process name.
    public var target: String
    /// `url_change`: the page must contain this text. `site_status`: "down" means tell me when the
    /// site goes down; nil means tell me when it is (back) up.
    public var contains: String?

    public init(kind: String, target: String, contains: String? = nil) {
        self.kind = kind
        self.target = target
        self.contains = contains
    }
}

/// What the user meant, worked out without a model.
public enum LocalIntent: Sendable, Equatable {
    case remind(title: String, when: Date, recurrence: Recurrence?)
    /// `collection` is a name as typed (or the known spelling); nil means the Inbox.
    case note(kind: NotebookItem.Kind, text: String, collection: String?)
    /// A durable fact about the user ("I prefer pnpm"), kept in About you.
    case aboutMe(fact: String)
    case watch(WatchIntent)
    /// Quiet mode until a time; nil means until the user turns it off.
    case quiet(until: Date?)
    case quietOff
    /// An empty `query` with a `kind` or `collection` means "list them".
    case find(query: String, kind: NotebookItem.Kind?, collection: String?)
    /// A reminder was asked for without a usable time; the app should ask when.
    case needsTime(title: String)
}

/// An intent and the line the input shows before Enter ("Reminder · Tue 09:00 · no AI").
public struct ParsedIntent: Sendable, Equatable {
    public var intent: LocalIntent
    public var hint: String

    public init(intent: LocalIntent, hint: String) {
        self.intent = intent
        self.hint = hint
    }
}
