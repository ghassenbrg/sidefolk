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

/// A coin, dice or a hand for the companion to play (D44, amended), for `companion.toss`.
public struct ChanceIntent: Sendable, Equatable {
    public enum Kind: String, Sendable { case coin, dice, rockPaperScissors = "rock_paper_scissors" }

    public var kind: Kind
    public var count = 1
    public var sides = 6
    public var modifier = 0
    /// Rock, paper, scissors: the person's hand; nil when they haven't said it yet.
    public var hand: Hand?

    public init(_ kind: Kind, count: Int = 1, sides: Int = 6, modifier: Int = 0, hand: Hand? = nil) {
        self.kind = kind
        self.count = count
        self.sides = sides
        self.modifier = modifier
        self.hand = hand
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
    /// A durable fact about the user ("I prefer pnpm"), kept in About you.
    case aboutMe(fact: String)
    case watch(WatchIntent)
    case report(ReportIntent)
    /// One value now, nothing left running ("what's my CPU usage"), for `watch.read`.
    case read(ReportIntent.Source)
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
    /// A trick or a game with the companion (D44).
    case companion(CompanionAct)
    /// A coin, dice or rock, paper, scissors on the desktop.
    case chance(ChanceIntent)
}

/// An intent and the line the input shows before Enter ("Reminder · Tue 09:00 · no AI").
public struct ParsedIntent: Sendable, Equatable {
    public var intent: LocalIntent
    public var hint: String

    public init(intent: LocalIntent, hint: String) {
        self.intent = intent
        self.hint = hint
    }

    /// A hint from its parts in the app's language, ending with the promise that no AI is involved.
    static func hint(_ parts: String...) -> String {
        (parts + [String(localized: "no AI")]).joined(separator: " · ")
    }
}
