import Foundation

/// What a plan the person read already allows, so an edit asks only about what is new (D187), and which steps stand, and how (D188, D189).
extension ExtensionPlanRules {
    /// What the host knows about who is asking and what the person chose.
    struct Context: Sendable {
        /// The extension is one of Sidefolk's own, signed (D98): only it is taken at its word about its flow, and only it may hold what ask each time for others.
        var firstParty: Bool
        /// The person's switch: a flow may pass what it reads to servers and to other extensions' tools (D189).
        var mayPassToServers: Bool
    }

    /// Whether a step stands, and whether only while Full access is on.
    struct Verdict: Equatable {
        var stands = false
        var fullAccessOnly = false
        /// Why it asks or only stands in Full access, as the editor's marks say it (`sidefolk/plan.check`); nil when it stands.
        var why: String?
        /// More on why, for the card: why a server's program can't be checked (`ProgramPin.Unchecked`).
        var detail: String?
        /// A plain warning on the card for a line that stands (`crossing`: it reads the person's own things and outside words and sends words on).
        var warning: String?
        /// It stands in no mode: the person's own words are needed there.
        var refused = false
    }

    enum FieldClass {
        /// Runs something: outside words never go here, in any mode.
        case code
        /// A plain text the receiver shows or stores: where outside words may go.
        case freeText
        /// Anything else, and so a place or a choice outside words may not make: only in Full access.
        case other
    }

    // MARK: Where a filled value comes from

    /// The names a step's slots start with: `{{page.title}}` is `page`.
    static func roots(_ text: String) -> [String] {
        slot.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let inner = text[range].dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespaces)
            return String(inner.prefix { $0 != "." && $0 != "[" })
        }
    }

    /// Names a step can't take, because the host reads them as something else.
    static let reservedNames: Set<String> = ["today", "now"]

    /// For each field a step fills in: "inside" when the person's own typed answer (an earlier `ask.user` step) or the clock fills it, "claimed" when
    /// a signed extension says it comes from the person (believed, except where code runs), and "outside" otherwise, which is also what any name the host
    /// can't place is. A step's name is the host's to read first: a name two steps share, or a step called `now`, never counts as inside.
    static func sources(of template: JSONValue, earlier: [(name: String?, tool: String)], inside: Set<String>, fromPerson: Set<String> = []) -> [String: String] {
        sources(of: template, steps: earlier.map { ($0.name, $0.tool, nil, nil) }, inside: inside, fromPerson: fromPerson)
    }

    /// As above, with the steps that only pass words on (`kind: "value"`, which read other steps by name and are never shown): a value is as far out as
    /// the furthest thing it reads.
    static func sources(of template: JSONValue, steps: [(name: String?, tool: String, kind: String?, reads: [String]?)], inside: Set<String>, fromPerson: Set<String> = []) -> [String: String] {
        // 0 inside, 1 claimed, 2 outside. Worked out once per name, however many steps point at it (a chain of steps each reading the one before twice would
        // otherwise take as many turns as it has paths); a name met again while it is being worked out is a cycle, and outside.
        var memo: [String: Int] = [:]
        func rank(_ root: String) -> Int {
            if let known = memo[root] { return known }
            let named = steps.filter { $0.name == root }
            guard !named.isEmpty else {
                let value = reservedNames.contains(root) ? 0 : inside.contains(root) ? 1 : 2
                memo[root] = value
                return value
            }
            memo[root] = 2
            let value = named.map { step -> Int in
                if step.tool == "ask.user" { return 0 }
                if step.kind == "value", let reads = step.reads { return reads.map(rank).max() ?? 2 }
                return 2
            }.max() ?? 2
            memo[root] = value
            return value
        }
        var out: [String: String] = [:]
        for (key, value) in template.objectValue ?? [:] {
            guard let text = value.stringValue, hasSlot(text) else { continue }
            if fromPerson.contains(key) { out[key] = "claimed"; continue }
            let worst = roots(text).map(rank).max() ?? 0
            out[key] = worst == 2 ? "outside" : worst == 1 ? "claimed" : "inside"
        }
        return out
    }

    // MARK: Fields that decide where a call goes or what it runs

    private static let codeWords: Set<String> = [
        "command", "cmd", "script", "code", "exec", "execute", "eval", "expression", "sql", "shell", "statement", "program", "snippet", "args", "argv",
        "regex", "js", "python", "bash", "zsh", "powershell", "applescript", "javascript",
        "arguments", "argument", "executable", "exe", "binary", "cmdline", "flags", "flag", "options", "option", "env", "environment", "prompt", "task", "run", "sh",
        "interpreter", "entrypoint", "macro",
    ]
    /// Names that run something, written as one word (`applescript`); a name that only holds the letters (`transcript`, `description`) isn't one.
    private static let codeCompounds = ["applescript", "javascript", "typescript", "vbscript", "coffeescript", "powershell", "commandline", "shellscript", "bashscript"]
    /// A name that runs something written as one lower-case word (`osascript`, `shellcommand`, `runscript`): a stem in it, unless every place the stem
    /// appears is inside a word that only holds the letters (`description`, `transcript`, `manuscript`, `prescription`, `subscription`, `inscription`).
    /// Ranges, not removal: cutting the innocent word out of `commandescription` would cut the stem apart.
    private static func hidesCode(_ lower: String) -> Bool {
        let text = lower as NSString
        func found(_ word: String) -> [NSRange] {
            var out: [NSRange] = [], from = 0
            while from < text.length {
                let r = text.range(of: word, range: NSRange(location: from, length: text.length - from))
                guard r.location != NSNotFound else { break }
                out.append(r)
                from = r.location + 1
            }
            return out
        }
        let innocent = ["description", "transcript", "manuscript", "prescription", "subscription", "inscription"].flatMap(found)
        return ["script", "command", "shell"].flatMap(found).contains { stem in
            !innocent.contains { NSIntersectionRange($0, stem) == stem }
        }
    }

    private static let placeWords: Set<String> = [
        "url", "uri", "link", "href", "host", "hostname", "domain", "address", "endpoint", "path", "file", "filename", "filepath", "dir", "directory",
        "folder", "recipient", "email", "repo", "repository", "branch", "channel", "webhook", "target", "destination", "server", "origin", "redirect", "to",
        "cc", "bcc", "chat", "user", "phone", "number", "attendee", "invitee", "location", "workspace", "account", "device", "tv",
    ]
    private static let freeTextWords: Set<String> = [
        "text", "message", "msg", "body", "content", "title", "subject", "summary", "note", "comment", "description", "caption", "reason", "detail", "remark",
    ]
    /// Words that may sit beside a free-text word without making it something else (`long_description`, `plain_text`).
    private static let neutralWords: Set<String> = ["short", "long", "full", "plain", "rich", "first", "last", "new", "custom", "extra", "main", "issue"]

    /// A name in lower-case words: camel case, acronyms (`URLPath` is `url`, `path`), digits and plurals taken apart.
    static func words(in key: String) -> [String] {
        rawWords(in: key).flatMap { w -> [String] in
            guard w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") else { return [w] }
            return w.hasSuffix("es") ? [w, String(w.dropLast()), String(w.dropLast(2))] : [w, String(w.dropLast())]
        }
    }

    /// The words of a name as written, each once.
    private static func rawWords(in key: String) -> [String] {
        let chars = Array(key)
        var words: [String] = [], word = ""
        func flush() { if !word.isEmpty { words.append(word.lowercased()); word = "" } }
        for (i, ch) in chars.enumerated() {
            guard ch.isLetter || ch.isNumber else { flush(); continue }
            if let last = word.last {
                let boundary = (last.isLowercase && ch.isUppercase) || (last.isNumber != ch.isNumber)
                    || (last.isUppercase && ch.isUppercase && i + 1 < chars.count && chars[i + 1].isLowercase)
                if boundary { flush() }
            }
            word.append(ch)
        }
        flush()
        return words
    }

    /// What kind of place a parameter is, by its name and the schema: a closed guess and the second line behind the card's own words (T53). Only a plain
    /// string with a name for words people read is free text; everything else outside words might choose is another place, and code is refused.
    static func fieldClass(_ key: String, schema: JSONValue?, whole: Bool = false) -> FieldClass {
        let lower = key.lowercased()
        let tokens = Set(words(in: key))
        if !tokens.isDisjoint(with: codeWords) || codeCompounds.contains(where: lower.contains) || hidesCode(lower) { return .code }
        if !tokens.isDisjoint(with: placeWords) { return .other }
        // Free text is a declared plain string, named only with words for what people read: every word of the name, so `appName` or `functionBody` is not.
        let allowed = freeTextWords.union(neutralWords)
        func isAllowed(_ word: String) -> Bool { allowed.contains(word) || allowed.contains(String(word.dropLast())) || allowed.contains(String(word.dropLast(2))) }
        guard let schema, schema["type"]?.stringValue == "string", !["enum", "format", "pattern", "anyOf", "oneOf", "allOf", "$ref", "const", "not", "contentMediaType", "contentEncoding"].contains(where: { schema[$0] != nil }),
              !tokens.isDisjoint(with: freeTextWords), rawWords(in: key).allSatisfy(isAllowed) else { return .other }
        return .freeText
    }

    // MARK: Standing

    /// Whether a step may stand in a plan from this extension, and whether only in Full access (D188, D189). `pinned`: a server's program can be checked.
    /// Everything today's rule lets stand still stands, for any extension. A signed extension's plan may also hold what asked each time before:
    /// a filled value in a field the table doesn't open, a server's tool, the clipboard. What no mode lets stand: text to read in full, a program that runs
    /// anything, outside words into a field that runs code, words the card can't show.
    static func verdict(tool: any Tool, template: JSONValue, sources: [String: String], pinned: Bool, context: Context) -> Verdict {
        if standing(tool: tool, template: template) { return Verdict(stands: true) }
        let spec = tool.spec, name = spec.name
        let ext = extensionTool(tool)
        let server = ext.map { !$0.sandboxed } ?? false
        func asks(_ why: String, refused: Bool = false) -> Verdict { Verdict(why: why, refused: refused) }
        // What no mode lets stand, for anyone.
        if tool.scope(for: template).text != nil { return asks("text_to_read", refused: true) }
        if spec.capabilities.contains(.shell) { return asks("shell", refused: true) }
        guard let fields = template.objectValue else { return asks("unreadable_value") }
        guard context.firstParty else { return asks(spec.risk == .high ? "high_risk" : "filled_value") }
        guard written(template).allSatisfy({ plain($0) && $0.count <= ExtensionPlanWords.valueLimit }), objectsFit(template), !joinersOutsideWords(template) else { return asks("unreadable_value") }
        if name == CompanionJobTool.name, (fields["job"]?.stringValue?.count ?? 0) > CompanionJobTool.longest { return asks("unreadable_value") }
        // A built-in tool that is high risk keeps its card; a server's is high risk for everyone (D127), and stands once its program can be checked.
        if spec.risk == .high, !server { return asks("high_risk") }
        if server, !pinned { return asks("server_unpinned") }
        let properties = spec.inputSchema["properties"]?.objectValue ?? [:]
        let open = ExtensionActionPolicy.fillable[name] ?? []
        var fullOnly = ExtensionActionPolicy.neverStanding.contains(name)
        var why: String? = fullOnly ? "private_read" : nil
        for (key, value) in fields {
            guard !hasSlot(key) else { return asks("nested_slot") }
            guard let text = value.stringValue, hasSlot(text) else {
                guard slotless(value, unless: false) else { return asks("nested_slot") }
                continue
            }
            if open.contains(key) { continue }
            let source = sources[key] ?? "outside"
            let kind = fieldClass(key, schema: properties[key], whole: isWholeSlot(text))
            // Where code runs, no slot at all: the host reads a name ("today", an `ask.user` step the program may never ask) as the person's own, which is the
            // program's declaration and not a fact, so nobody's word counts there, in any mode.
            if kind == .code { return asks("code_field", refused: true) }
            switch kind {
            case .code: break
            case .other:
                // A place or a choice is the person's only where the extension says so on its card (claimed). The rest, a typed answer or a clock included, is
                // read from names the program wrote, so it stands only in Full access; and the person's switch holds back what comes from outside.
                if source == "claimed" { continue }
                if source == "outside", ext != nil, !context.mayPassToServers { return asks("switch_off") }
                fullOnly = true
                why = source == "inside" ? "declared_place" : "reach_field"
            case .freeText:
                guard source == "outside" else { continue }
                if ext != nil {
                    // Another extension's tool or a server: free words may go in, as the card says, unless the person switched that off.
                    guard context.mayPassToServers else { return asks("switch_off") }
                } else {
                    fullOnly = true
                    why = why ?? "filled_value"
                }
            }
        }
        return Verdict(stands: true, fullAccessOnly: fullOnly, why: why)
    }

    // MARK: Coverage

    /// Whether the step `old`, which the person read, already allows `step`: the same tool from the same provider as it was, the same written
    /// values (words may change only where the table says they stay inside Sidefolk), and no value coming from further out than before.
    static func covers(_ old: ExtensionPlan.Step, _ step: ExtensionPlan.Step) -> Bool {
        // An AI step is covered by one that read at least what this one reads (no names given means everything before it); another flow set off, by the same name.
        if let kind = step.kind {
            guard old.kind == kind else { return false }
            // A step that only passes words on grants nothing: what feeds from it is what changes, and that is compared where it is used.
            if kind == "value" { return true }
            if kind == "flow" { return same(step.input["name"]?.stringValue ?? "", old.input["name"]?.stringValue ?? "") }
            return Set(step.reads ?? ["*"]).isSubset(of: Set(old.reads ?? ["*"])) && (step.feeds ?? [:]).allSatisfy { old.feeds?[$0.key] == $0.value }
        }
        guard old.kind == nil, old.tool == step.tool, (old.provider ?? "") == (step.provider ?? ""), old.definition == step.definition else { return false }
        // It asks each time: there is nothing silent to read again.
        guard step.standing else { return true }
        guard old.standing, !(old.isInFullAccessOnly && !step.isInFullAccessOnly), same(old.reach, step.reach), (old.program ?? "") == (step.program ?? ""),
              let before = old.input.objectValue, let now = step.input.objectValue,
              Set(before.keys.map { Array($0.utf8) }) == Set(now.keys.map { Array($0.utf8) }) else { return false }
        let open = ExtensionActionPolicy.fillable[step.tool] ?? []
        for (key, value) in now {
            if open.contains(key), let was = before[key]?.stringValue, let now = value.stringValue {
                // Other words are fine; words that were written and are now filled in from elsewhere are not the same thing.
                if hasSlot(now), !hasSlot(was) { return false }
                continue
            }
            guard let was = before[key], same(was, value) else { return false }
        }
        // What a word-filled value came from: no further out than before, and the same kind of step behind it.
        // The table's text fields are no exception: their words may change, but where those words come from may not move out of the person's own.
        for (key, source) in step.sources ?? [:] {
            // A claim is the extension's word, which no switch of the person's holds back: a field newly said to be theirs is something new, though it is
            // "no further out" than the page words it was before (T53).
            if source == "outside" || source == "claimed" { guard old.sources?[key] == source else { return false } }
        }
        return (step.feeds ?? [:]).allSatisfy { old.feeds?[$0.key] == $0.value }
    }

    /// Whether the terms themselves are wider than the person read: more actions, a longer time, or another way of starting.
    static func widened(_ old: ExtensionPlan, to new: ExtensionPlan) -> Bool {
        let fewer = new.perDay <= old.perDay && (new.perRun ?? defaultPerRun) <= (old.perRun ?? defaultPerRun)
        let ends: Bool = switch (old.ttl, new.ttl) {
        case (nil, _): true
        case (.some, nil): false
        case (let a?, let b?): b <= a
        }
        return !fewer || !ends || !same(old.when, new.when) || (new.goesRound == true && old.goesRound != true)
    }

    static let defaultPerRun = 50
    static let perRuns = 1...1000
}
