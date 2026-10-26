import Foundation

/// Notes, lists, facts about the user, and searching the notebook. Notes are matched on the text as typed
/// (line breaks, punctuation and all), so what is saved is what was written.
extension IntentParser {
    // MARK: Words

    private static let sep = #"(?::(?![\d/])|\s[-–—]\s)"#
    private static let kindWord = #"(?:note|idea|task|todo|to-do|to\s+do|link|bookmark|thought)"#
    /// A collection phrase: anything up to the separator, except that a colon inside a clock time ("3:30") or a
    /// link ("https://…") is not the separator.
    private static let collChars = #"(?:[^:\n]|(?<=\d):(?=\d)|(?<=\w):(?=//))"#

    static func kind(of word: String) -> NotebookItem.Kind {
        switch word.lowercased().replacingOccurrences(of: "s", with: "", options: [.anchored, .backwards]) {
        case "idea": .idea
        case "task", "todo", "to-do", "to do": .task
        case "link", "bookmark": .link
        default: .note
        }
    }

    private static func label(_ kind: NotebookItem.Kind) -> String {
        switch kind {
        case .note: "Note"
        case .idea: "Idea"
        case .task: "Task"
        case .link: "Link"
        }
    }

    /// Words that mean "no particular collection".
    private static let inboxNames: Set<String> = ["inbox", "notes", "notebook", "the notebook", "my notes", "sidefolk notes", "myself", "self", "me"]
    private static let taskListNames: Set<String> = ["todo", "to-do", "to do", "todos", "to-dos", "tasks", "task", "to do list"]
    /// "add milk to my list": which list is not said, so it is the plain task list, not a collection called "my".
    private static let fillerNames: Set<String> = ["list", "checklist", "my", "the", "our", "a", "an", "this", "that", "it", "one", "something", "here"]
    /// Words that are about when, not about where.
    private static let timeNames: Set<String> = [
        "today", "tonight", "tomorrow", "yesterday", "later", "soon", "now", "sometime", "someday", "eventually", "this week", "next week",
        "this weekend", "the weekend", "this month", "next month", "this year", "next year", "this morning", "this afternoon", "this evening",
    ]
    private static let clockWords = Scan(#"\d{1,2}:\d{2}|\b\d{1,2}\s*(?:am|pm)\b"#)

    /// The collection a phrase names: the user's own spelling of a known one, else the words as typed with a capital letter.
    /// `name` nil means the Inbox. `isTaskList` is true for "my todo list" and the like. `kind` is what a new collection
    /// of this name should be, when the phrase says ("groceries list" is a list).
    func collection(_ raw: String, _ ctx: Context) -> (name: String?, isTaskList: Bool, kind: NotebookCollection.Kind?) {
        var name = raw.unquoted
        for lead in ["my ", "the ", "our "] where name.lowercased().hasPrefix(lead) { name = String(name.dropFirst(lead.count)) }
        let bare = Self.strippingListWords(name)
        let lower = name.lowercased(), bareLower = bare.lowercased()
        if Self.inboxNames.contains(lower) || Self.inboxNames.contains(bareLower) { return (nil, false, nil) }
        if Self.taskListNames.contains(lower) || Self.taskListNames.contains(bareLower) { return (nil, true, nil) }
        if name.isEmpty || Self.fillerNames.contains(lower) || Self.fillerNames.contains(bareLower) { return (nil, true, nil) }
        if let known = ctx.known.first(where: { $0.lowercased() == lower }) ?? ctx.known.first(where: { $0.lowercased() == bareLower }) {
            return (known, false, nil)
        }
        let given = bare.isEmpty ? name : bare
        let words = lower.split(separator: " ")
        let kind: NotebookCollection.Kind? = words.count > 1 ? (["list", "checklist"].contains(words.last!) ? .list : words.last == "project" ? .project : nil) : nil
        return (Self.capitalizedName(given), false, kind)
    }

    /// "groceries" -> "Groceries"; "iOS apps" and "side-project" keep what was typed after the first letter.
    private static func capitalizedName(_ s: String) -> String {
        guard let first = s.split(separator: " ").first, first == first.lowercased() else { return s }
        return s.capitalizedFirst
    }

    /// "groceries list" -> "groceries", "Sidefolk project" -> "Sidefolk".
    private static func strippingListWords(_ s: String) -> String {
        var words = s.split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last?.lowercased(), ["list", "notes", "project", "folder", "collection", "notebook", "ideas"].contains(last) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    /// Whether a phrase after "for" / "about" can be the name of a collection at all, rather than a time or a link
    /// ("task for tomorrow: call the dentist" is not a task in a collection called "tomorrow").
    private func isCollectionName(_ place: String, _ ctx: Context) -> Bool {
        let p = place.trimmingCharacters(in: .whitespaces)
        if ctx.known.contains(where: { $0.lowercased() == p.lowercased() }) { return true }
        if p.contains("://") || p.lowercased().hasPrefix("www.") { return false }
        if Self.clockWords.found(in: p) { return false }
        if Self.timeNames.contains(p.lowercased()) { return false }
        if let found = when.parse(p, now: ctx.now), found.remaining.isEmpty { return false }
        return true
    }

    /// The first letter of a note's title in capitals, like a reminder's: "milk" is saved as "Milk". Left alone when the
    /// first word has a capital inside it (iPhone, macOS) or looks like a link, a path or an address.
    public static func capitalizedNote(_ text: String) -> String {
        guard let first = text.split(whereSeparator: \.isWhitespace).first, first == first.lowercased(),
              !first.contains(where: { "/.@:#~\\".contains($0) }) else { return text }
        return text.capitalizedFirst
    }

    // MARK: Saving

    private static let noteColon = IntentPattern(
        "(?<kind>note|idea|task|todo|to-do|to\\s+do|link|bookmark|thought)s?(?:\\s+list)?(?:\\s+(?<lead>(?:for|in|to|about|on)\\s+(?<coll>" + collChars + "{1,40}?)))?\\s*" + sep
            + "\\s*(?<text>.+)", multiline: true
    )
    private static let saveTo = IntentPattern(
        "(?:save|add|put|file|store|keep|stash|drop|capture)\\s+(?:(?:this|that|the|my|a|an|it)\\s+)?(?:(?<kind>note|idea|task|link|thought|todo)\\s+)?"
            + "(?<lead>(?:to|in|into|under|for|on)\\s+(?:(?:my|the)\\s+)?(?<coll>" + collChars + "{1,40}?))\\s*" + sep + "\\s*(?<text>.+)", multiline: true
    )
    private static let saveKind = IntentPattern(
        "(?:save|add|capture|jot|put)\\s+(?:(?:this|that|a|an|the|my)\\s+)?(?<kind>note|idea|task|link|thought|todo)\\s*" + sep + "\\s*(?<text>.+)", multiline: true
    )
    private static let addToList = IntentPattern(
        "(?:add|put)\\s+(?<text>.+?)\\s+(?:to|on|onto|in)\\s+(?:(?:my|the|our)\\s+)?(?<coll>.+?)\\s+(?:list|checklist)", multiline: true
    )
    private static let addToCollection = IntentPattern("(?:add|put)\\s+(?<text>.+?)\\s+(?:to|on|onto|in)\\s+(?:(?:my|the|our)\\s+)?(?<coll>[^\\n]+)", multiline: true)
    private static let noteVerb = IntentPattern(
        "(?:(?:make|take)\\s+a\\s+note(?:\\s+(?:that|of|to\\s+self))?\\s*[:,]?|note\\s+(?:that|down|to\\s+self)|jot(?:\\s+down)?\\s*[:,]?)\\s+(?<text>.+)", multiline: true
    )
    private static let todoWord = IntentPattern("(?:todo|to-do)\\s+(?<text>.+)", multiline: true)
    private static let remember = IntentPattern("(?:remember|keep\\s+in\\s+mind)(?:\\s*[:,]\\s*|\\s+that\\s+|\\s+)(?<fact>.+)", multiline: true)
    private static let aboutMe = IntentPattern("about\\s+me\\s*" + sep + "\\s*(?<fact>.+)", multiline: true)
    /// Just a kind word on its own is not a thing to save.
    private static let bareKind = IntentPattern("(?:a\\s+|an\\s+|this\\s+|that\\s+|the\\s+)?(?:note|idea|task|link|thought|list|todo|to-do|to\\s+do)s?")
    /// "remember this": nothing said to remember.
    private static let nothingToRemember: Set<String> = ["this", "that", "it", "these", "those", "something", "everything", "stuff"]
    private static let firstPerson = IntentPattern("(?:i|i'm|im|i've|i'd|i'll|my|we|we're|we've|our)\\b.*", multiline: true)

    /// - Parameter t: the text as typed (see `Prepared.typed`).
    func note(_ t: String, _ ctx: Context) -> ParsedIntent? {
        if let c = Self.noteColon.match(t), let text = c["text"] {
            let kind = Self.kind(of: c["kind"] ?? "note")
            return saved(kind: kind, text: text, place: c["coll"], lead: c["lead"], ctx)
        }
        if let c = Self.saveTo.match(t), let text = c["text"], let place = c["coll"] {
            return saved(kind: c["kind"].map(Self.kind(of:)) ?? .note, text: text, place: place, lead: c["lead"], ctx)
        }
        if let c = Self.saveKind.match(t), let text = c["text"] {
            return saved(kind: Self.kind(of: c["kind"] ?? "note"), text: text, place: nil, ctx)
        }
        if let c = Self.addToList.match(t), let text = c["text"], let place = c["coll"] {
            return saved(kind: .task, text: text, place: place, listKind: .list, ctx)
        }
        if let c = Self.addToCollection.match(t), let text = c["text"], let place = c["coll"],
           Self.bareKind.match(text) == nil, collection(place, ctx).name.map({ name in ctx.known.contains(name) }) == true {
            return saved(kind: .task, text: text, place: place, ctx)
        }
        if let c = Self.noteVerb.match(t), let text = c["text"] {
            return saved(kind: .note, text: text, place: nil, ctx)
        }
        if let c = Self.todoWord.match(t), let text = c["text"] {
            return saved(kind: .task, text: text, place: nil, ctx)
        }
        if let c = Self.aboutMe.match(t), let fact = c["fact"] {
            return remembered(fact)
        }
        if let c = Self.remember.match(t), let fact = c["fact"] {
            // "remember to ..." is a reminder in disguise, not a fact; "remember this" has nothing in it.
            guard !fact.lowercased().hasPrefix("to "), !Self.nothingToRemember.contains(fact.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!? "))) else { return nil }
            return Self.firstPerson.match(fact) != nil ? remembered(fact) : saved(kind: .note, text: fact, place: nil, ctx)
        }
        return nil
    }

    /// - Parameters:
    ///   - lead: the words that named the place ("for tomorrow"), kept in the note if they turn out not to name one.
    ///   - listKind: what a new collection with this name should be, when the sentence says so ("... to my groceries list").
    private func saved(kind: NotebookItem.Kind, text: String, place: String?, lead: String? = nil, listKind: NotebookCollection.Kind? = nil,
                       _ ctx: Context) -> ParsedIntent? {
        var body = Self.tidy(text.unquoted)
        guard !body.isEmpty, Self.bareKind.match(body) == nil else { return nil }
        var resolved: (name: String?, isTaskList: Bool, kind: NotebookCollection.Kind?) = (nil, false, nil)
        if let place {
            if isCollectionName(place, ctx) {
                resolved = collection(place, ctx)
            } else if let lead {
                // "task for tomorrow: call the dentist": not a place, so nothing is lost; the words stay in the task.
                body = lead + ": " + body
            } else {
                return nil
            }
        }
        let finalKind = resolved.isTaskList && kind == .note ? .task : kind
        let where_ = resolved.name ?? "Inbox"
        return ParsedIntent(intent: .note(kind: finalKind, text: body, collection: resolved.name, collectionKind: resolved.kind ?? (resolved.name == nil ? nil : listKind)),
                            hint: "\(Self.label(finalKind)) → \(where_) · no AI")
    }

    private func remembered(_ fact: String) -> ParsedIntent? {
        let clean = fact.unquoted.capitalizedFirst
        guard !clean.isEmpty else { return nil }
        return ParsedIntent(intent: .aboutMe(fact: clean), hint: "Remember in About you · no AI")
    }

    // MARK: Searching

    private static let kinds = #"(?<kind>ideas?|notes?|tasks?|to-?dos?|links?|bookmarks?)"#
    private static let about = #"(?:for|in|about|on|from|under|of|regarding|mentioning|to)"#
    private static let findPatterns: [IntentPattern] = [
        IntentPattern(#"what\s+"# + kinds + #"\s+(?:did|do|have)\s+i\s+(?:save|saved|add|added|write|wrote|capture|captured|jot|jotted|note|noted|have|store|stored)(?:\s+down)?(?:\s+"# + about + #"\s+(?<q>.+))?"#),
        IntentPattern(#"what\s+did\s+i\s+(?:save|add|write|note|capture|jot\s+down|store)\s+(?:for|about|on|regarding|in)\s+(?<q>.+)"#),
        IntentPattern(#"what\s+(?:are|is)\s+my\s+(?:open\s+)?"# + kinds + #"(?:\s+"# + about + #"\s+(?<q>.+))?"#),
        IntentPattern(#"(?:show|list|get|open|see|display|find)\s+(?:me\s+)?(?:all\s+)?(?:(?:of\s+)?my\s+|the\s+)?(?:open\s+)?"# + kinds + #"(?:\s+"# + about + #"\s+(?<q>.+))?"#),
        IntentPattern(#"search\s+(?:(?:in\s+)?(?:my\s+)?(?:notes|notebook|ideas|tasks|everything)\s+)?(?:for\s+|about\s+)?(?<q>.+)"#),
        IntentPattern(#"find\s+(?:me\s+)?(?:my\s+)?(?:"# + kinds + #"\s+)?(?:(?:about|for|on|mentioning|with|containing)\s+)?(?<q>.+)"#),
    ]
    /// "find out why...", "find me a good restaurant", "search the web for...": a request for reasoning or the web, not a notebook search.
    private static let notASearch: Set<String> = [
        "out", "a", "an", "me", "how", "why", "what", "where", "who", "when", "the", "some", "good", "best", "my", "web", "online", "google",
        "internet", "youtube", "news", "wikipedia",
    ]
    /// "search for" and "find ideas for" with nothing after the preposition search for the preposition.
    private static let prepositions: Set<String> = ["for", "about", "on", "in", "of", "from", "under", "regarding", "mentioning", "with", "containing", "to"]

    func find(_ t: String, _ ctx: Context) -> ParsedIntent? {
        for pattern in Self.findPatterns {
            guard let c = pattern.match(t) else { continue }
            let kind = c["kind"].map(Self.kind(of:))
            // `find " "` unquotes to a space: no words is no query.
            let q = c["q"].map { $0.unquoted.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
            if kind == nil, q == nil { continue }
            if let q {
                let words = q.split(whereSeparator: \.isWhitespace)
                guard !words.isEmpty, words.count <= 5 else { continue }
                if kind == nil, Self.notASearch.contains(words[0].lowercased()) { continue }
                if words.count == 1, Self.prepositions.contains(words[0].lowercased()) { continue }
            }
            // "ideas for Sidefolk": a collection when the user has one by that name, otherwise search words.
            var query = q ?? ""
            var collectionName: String?
            if let q, kind != nil, let known = collection(q, ctx).name, ctx.known.contains(known) {
                collectionName = known
                query = ""
            }
            return ParsedIntent(intent: .find(query: query, kind: kind, collection: collectionName),
                                hint: findHint(kind: kind, query: query, collection: collectionName))
        }
        return nil
    }

    private func findHint(kind: NotebookItem.Kind?, query: String, collection: String?) -> String {
        guard kind != nil || collection != nil else { return "Search notebook · no AI" }
        let what = kind.map { "\(Self.label($0).lowercased())s" } ?? "notebook"
        let place = collection.map { " in \($0)" } ?? ""
        return "Search \(what)\(place) · no AI"
    }
}
