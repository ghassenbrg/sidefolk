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

/// A value to show every so often ("every 10 seconds tell me the CPU usage"), for `watch.report`.
public struct ReportIntent: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case metric(Metric)
        case weather(place: String, quantity: WeatherQuantity)
    }

    public var source: Source
    public var everySeconds: TimeInterval
    /// The end as typed ("6pm", "in an hour"); nil means the default end.
    public var until: String?
    public var untilStopped = false
    /// "notify me": a notification with every reading, not only the live value.
    public var notify = false

    public init(source: Source, everySeconds: TimeInterval, until: String? = nil, untilStopped: Bool = false, notify: Bool = false) {
        self.source = source
        self.everySeconds = everySeconds
        self.until = until
        self.untilStopped = untilStopped
        self.notify = notify
    }
}

/// What the user meant, worked out without a model.
public enum LocalIntent: Sendable, Equatable {
    /// `important` reminders are the ones that still interrupt during quiet mode ("urgent: remind me ...").
    /// `anchor` is set when a monthly or yearly series starts on a clamped day (`WhenResult.anchor`): "every month
    /// on the 31st" said in November fires on the 30th first, and must still come back on the 31st.
    case remind(title: String, when: Date, recurrence: Recurrence?, important: Bool = false, anchor: Date? = nil)
    /// `collection` is a name as typed (or the known spelling); nil means the Inbox. `text` is exactly what was typed.
    /// `collectionKind` is what to make the collection if it does not exist yet ("add milk to my groceries list" makes a
    /// list); nil leaves that to the tool's default.
    case note(kind: NotebookItem.Kind, text: String, collection: String?, collectionKind: NotebookCollection.Kind? = nil)
    /// A task with a time at its end ("add a task to call mom at 5"): saved with a reminder that belongs to it (D49).
    case taskWithReminder(text: String, collection: String?, collectionKind: NotebookCollection.Kind?, remindAt: Date)
    /// A durable fact about the user ("I prefer pnpm"), kept in About you.
    case aboutMe(fact: String)
    case watch(WatchIntent)
    case report(ReportIntent)
    /// "stop telling me the CPU": the watchers the words name (none, one or several), and the words themselves.
    case stopWatch(ids: [String], words: String)
    /// Quiet mode until a time; nil means until the user turns it off.
    case quiet(until: Date?)
    case quietOff
    /// An empty `query` with a `kind` or `collection` means "list them".
    case find(query: String, kind: NotebookItem.Kind?, collection: String?)
    /// A reminder was asked for without a usable time; the app should ask when. `title` is clean (no time words).
    /// `reason` says why the words given were no use ("Yesterday has passed.", "25:00 isn't a time.") and is nil
    /// when there simply was no time. `important` is carried through to the reminder made from the answer.
    case needsTime(title: String, reason: String? = nil, important: Bool = false)
    /// A watch was asked for without saying what to watch ("tell me when the server is back up"); the app should ask
    /// for the address and finish with `IntentParser.watch(address:kind:becomes:)`. `kind` is `site_status` or
    /// `url_change`; for `site_status`, `becomes` is "up" or "down".
    case needsTarget(kind: String, becomes: String?)
    /// A weather report with no place named, while Sidefolk doesn't know where the person is (D48).
    case needsPlace(WeatherQuantity)
    /// A trick or a game with the companion (D44).
    case companion(CompanionAct)
    /// "new conversation", "start fresh": the next request to the AI starts a new conversation (D45).
    case newConversation
    /// A sentence one switched-on extension answers without the AI (D50).
    case extensionCommand(ExtensionCommandCall)
}

/// An intent and the line the input shows before Enter ("Reminder · Tue 09:00 · no AI").
public struct ParsedIntent: Sendable, Equatable {
    public var intent: LocalIntent
    public var hint: String

    public init(intent: LocalIntent, hint: String) {
        self.intent = intent
        self.hint = hint
    }

    /// A sentence an extension's command answers (D50): the app leaves it to the AI when something was dropped too.
    public var isExtensionCommand: Bool { if case .extensionCommand = intent { true } else { false } }

    /// A hint from its parts in the app's language, ending with the promise that no AI is involved.
    static func hint(_ parts: String...) -> String {
        (parts + [String(localized: "no AI")]).joined(separator: " · ")
    }
}
