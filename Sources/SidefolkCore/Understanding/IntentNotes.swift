import Foundation

/// Notes, lists, facts about the user, and searching the notebook.
extension IntentParser {
    // MARK: Words

    private static let sep = #"(?::|\s[-–—]\s)"#
    private static let kindWord = #"(?:note|idea|task|todo|to-do|to\s+do|link|bookmark|thought)"#

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

    /// The collection a phrase names: the user's own spelling of a known one, else the words as typed.
    /// `nil` means the Inbox. `isTaskList` is true for "my todo list" and the like.
    func collection(_ raw: String, _ ctx: Context) -> (name: String?, isTaskList: Bool) {
        var name = raw.unquoted
        for lead in ["my ", "the ", "our "] where name.lowercased().hasPrefix(lead) { name = String(name.dropFirst(lead.count)) }
        let bare = Self.strippingListWords(name)
        let lower = name.lowercased(), bareLower = bare.lowercased()
        if Self.inboxNames.contains(lower) || Self.inboxNames.contains(bareLower) { return (nil, false) }
        if Self.taskListNames.contains(lower) || Self.taskListNames.contains(bareLower) { return (nil, true) }
        if let known = ctx.known.first(where: { $0.lowercased() == lower }) ?? ctx.known.first(where: { $0.lowercased() == bareLower }) {
            return (known, false)
        }
        return (bare.isEmpty ? name : bare, false)
    }

    /// "groceries list" -> "groceries", "Sidefolk project" -> "Sidefolk".
    private static func strippingListWords(_ s: String) -> String {
        var words = s.split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last?.lowercased(), ["list", "notes", "project", "folder", "collection", "notebook", "ideas"].contains(last) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    // MARK: Saving

    private static let noteColon = Pattern(
        "(?<kind>note|idea|task|todo|to-do|to\\s+do|link|bookmark|thought)s?(?:\\s+(?:for|in|to|about|on)\\s+(?<coll>[^:]{1,40}?))?\\s*" + sep + "\\s*(?<text>.+)"
    )
    private static let saveTo = Pattern(
        "(?:save|add|put|file|store|keep|stash|drop|capture)\\s+(?:(?:this|that|the|my|a|an|it)\\s+)?(?:(?<kind>note|idea|task|link|thought|todo)\\s+)?"
            + "(?:to|in|into|under|for|on)\\s+(?:(?:my|the)\\s+)?(?<coll>[^:]{1,40}?)\\s*" + sep + "\\s*(?<text>.+)"
    )
    private static let saveKind = Pattern(
        "(?:save|add|capture|jot|put)\\s+(?:(?:this|that|a|an|the|my)\\s+)?(?<kind>note|idea|task|link|thought|todo)\\s*" + sep + "\\s*(?<text>.+)"
    )
    private static let addToList = Pattern(
        "(?:add|put)\\s+(?<text>.+?)\\s+(?:to|on|onto|in)\\s+(?:(?:my|the|our)\\s+)?(?<coll>.+?)\\s+(?:list|checklist)"
    )
    private static let addToCollection = Pattern("(?:add|put)\\s+(?<text>.+?)\\s+(?:to|on|onto|in)\\s+(?:(?:my|the|our)\\s+)?(?<coll>.+)")
    private static let noteVerb = Pattern(
        "(?:(?:make|take)\\s+a\\s+note(?:\\s+(?:that|of|to\\s+self))?\\s*[:,]?|note\\s+(?:that|down|to\\s+self)|jot(?:\\s+down)?)\\s+(?<text>.+)"
    )
    private static let todoWord = Pattern("(?:todo|to-do)\\s+(?<text>.+)")
    private static let remember = Pattern("(?:remember|keep\\s+in\\s+mind)(?:\\s*[:,]\\s*|\\s+that\\s+|\\s+)(?<fact>.+)")
    private static let aboutMe = Pattern("about\\s+me\\s*" + sep + "\\s*(?<fact>.+)")
    /// Just a kind word on its own is not a thing to save.
    private static let bareKind = Pattern("(?:a\\s+|an\\s+|this\\s+|that\\s+|the\\s+)?(?:note|idea|task|link|thought)s?")
    private static let firstPerson = Pattern("(?:i|i'm|im|i've|i'd|i'll|my|we|we're|we've|our)\\b.*")

    func note(_ t: String, _ ctx: Context) -> ParsedIntent? {
        if let c = Self.noteColon.match(t), let text = c["text"] {
            let kind = Self.kind(of: c["kind"] ?? "note")
            return saved(kind: kind, text: text, place: c["coll"], ctx)
        }
        if let c = Self.saveTo.match(t), let text = c["text"], let place = c["coll"] {
            return saved(kind: c["kind"].map(Self.kind(of:)) ?? .note, text: text, place: place, ctx)
        }
        if let c = Self.saveKind.match(t), let text = c["text"] {
            return saved(kind: Self.kind(of: c["kind"] ?? "note"), text: text, place: nil, ctx)
        }
        if let c = Self.addToList.match(t), let text = c["text"], let place = c["coll"] {
            return saved(kind: .task, text: text, place: place, ctx)
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
            // "remember to ..." is a reminder in disguise, not a fact.
            guard !fact.lowercased().hasPrefix("to ") else { return nil }
            return Self.firstPerson.match(fact) != nil ? remembered(fact) : saved(kind: .note, text: fact, place: nil, ctx)
        }
        return nil
    }

    private func saved(kind: NotebookItem.Kind, text: String, place: String?, _ ctx: Context) -> ParsedIntent? {
        let body = text.unquoted
        guard !body.isEmpty, Self.bareKind.match(body) == nil else { return nil }
        var resolved: (name: String?, isTaskList: Bool) = (nil, false)
        if let place { resolved = collection(place, ctx) }
        let finalKind = resolved.isTaskList && kind == .note ? .task : kind
        let where_ = resolved.name ?? "Inbox"
        return ParsedIntent(intent: .note(kind: finalKind, text: body, collection: resolved.name), hint: "\(Self.label(finalKind)) → \(where_) · no AI")
    }

    private func remembered(_ fact: String) -> ParsedIntent? {
        let clean = fact.unquoted.capitalizedFirst
        guard !clean.isEmpty else { return nil }
        return ParsedIntent(intent: .aboutMe(fact: clean), hint: "Remember in About you · no AI")
    }

    // MARK: Searching

    private static let kinds = #"(?<kind>ideas?|notes?|tasks?|to-?dos?|links?|bookmarks?)"#
    private static let about = #"(?:for|in|about|on|from|under|of|regarding|mentioning|to)"#
    private static let findPatterns: [Pattern] = [
        Pattern(#"what\s+"# + kinds + #"\s+(?:did|do|have)\s+i\s+(?:save|saved|add|added|write|wrote|capture|captured|jot|jotted|note|noted|have|store|stored)(?:\s+down)?(?:\s+"# + about + #"\s+(?<q>.+))?"#),
        Pattern(#"what\s+did\s+i\s+(?:save|add|write|note|capture|jot\s+down|store)\s+(?:for|about|on|regarding|in)\s+(?<q>.+)"#),
        Pattern(#"what\s+(?:are|is)\s+my\s+(?:open\s+)?"# + kinds + #"(?:\s+"# + about + #"\s+(?<q>.+))?"#),
        Pattern(#"(?:show|list|get|open|see|display|find)\s+(?:me\s+)?(?:all\s+)?(?:(?:of\s+)?my\s+|the\s+)?(?:open\s+)?"# + kinds + #"(?:\s+"# + about + #"\s+(?<q>.+))?"#),
        Pattern(#"search\s+(?:(?:in\s+)?(?:my\s+)?(?:notes|notebook|ideas|tasks|everything)\s+)?(?:for\s+|about\s+)?(?<q>.+)"#),
        Pattern(#"find\s+(?:me\s+)?(?:my\s+)?(?:"# + kinds + #"\s+)?(?:(?:about|for|on|mentioning|with|containing)\s+)?(?<q>.+)"#),
    ]
    /// "find out why...", "find me a good restaurant", "search the web for...": a request for reasoning or the web, not a notebook search.
    private static let notASearch: Set<String> = [
        "out", "a", "an", "me", "how", "why", "what", "where", "who", "when", "the", "some", "good", "best", "my", "web", "online", "google",
        "internet", "youtube", "news", "wikipedia",
    ]

    func find(_ t: String, _ ctx: Context) -> ParsedIntent? {
        for pattern in Self.findPatterns {
            guard let c = pattern.match(t) else { continue }
            let kind = c["kind"].map(Self.kind(of:))
            let q = c["q"]?.unquoted
            if kind == nil, q == nil { continue }
            if let q {
                let words = q.split(separator: " ")
                guard words.count <= 5 else { continue }
                if kind == nil, Self.notASearch.contains(words[0].lowercased()) { continue }
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
