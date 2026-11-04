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
        /// It stands in no mode: the person's own words are needed there.
        var refused = false
    }

    enum FieldClass { case code, reach, text }

    // MARK: Where a filled value comes from

    /// The names a step's slots start with: `{{page.title}}` is `page`.
    static func roots(_ text: String) -> [String] {
        slot.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let inner = text[range].dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespaces)
            return String(inner.prefix { $0 != "." && $0 != "[" })
        }
    }

    /// For each field a step fills in, whether the words come from inside (the person's own typed answer, or the clock) or outside (anything else).
    /// Outside is the default: a name the host can't place is outside. A signed extension may name more that are inside (`inside`).
    static func sources(of template: JSONValue, earlier: [(name: String?, tool: String)], inside: Set<String>, fromPerson: Set<String> = []) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in template.objectValue ?? [:] {
            guard let text = value.stringValue, hasSlot(text) else { continue }
            if fromPerson.contains(key) { out[key] = "inside"; continue }
            let roots = roots(text)
            let isInside = roots.allSatisfy { root in
                inside.contains(root) || ["today", "now"].contains(root) || earlier.contains { $0.name == root && $0.tool == "ask.user" }
            }
            out[key] = isInside ? "inside" : "outside"
        }
        return out
    }

    // MARK: Fields that decide where a call goes or what it runs

    private static let codeWords: Set<String> = ["command", "cmd", "script", "code", "exec", "execute", "eval", "expression", "sql", "shell", "statement", "program"]
    private static let reachWords: Set<String> = [
        "url", "uri", "link", "href", "host", "hostname", "domain", "address", "endpoint", "path", "file", "filename", "filepath", "dir", "directory",
        "folder", "recipient", "recipients", "to", "cc", "bcc", "email", "repo", "repository", "branch", "channel", "webhook", "target", "destination",
        "server", "origin", "redirect",
    ]

    /// What kind of place a parameter is, by its name and the schema's hints: a closed guess, the second line behind the card's own words (T53).
    static func fieldClass(_ key: String, schema: JSONValue?) -> FieldClass {
        var words: [String] = [], word = ""
        var previous: Character?
        for ch in key {
            if !ch.isLetter && !ch.isNumber {
                if !word.isEmpty { words.append(word.lowercased()); word = "" }
            } else {
                if ch.isUppercase, let p = previous, p.isLowercase, !word.isEmpty { words.append(word.lowercased()); word = "" }
                word.append(ch)
            }
            previous = ch
        }
        if !word.isEmpty { words.append(word.lowercased()) }
        if words.contains(where: codeWords.contains) { return .code }
        if words.contains(where: reachWords.contains) { return .reach }
        if let format = schema?["format"]?.stringValue, ["uri", "uri-reference", "iri", "hostname", "email", "idn-email"].contains(format) { return .reach }
        return .text
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
        guard written(template).allSatisfy({ plain($0) && $0.count <= ExtensionPlanWords.valueLimit }), objectsFit(template) else { return asks("unreadable_value") }
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
            guard sources[key] != "inside" else { continue }
            switch fieldClass(key, schema: properties[key]) {
            case .code: return asks("code_field", refused: true)
            case .reach:
                fullOnly = true
                why = "reach_field"
            case .text:
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
            if kind == "flow" { return step.input["name"]?.stringValue == old.input["name"]?.stringValue }
            return Set(step.reads ?? ["*"]).isSubset(of: Set(old.reads ?? ["*"]))
        }
        guard old.kind == nil, old.tool == step.tool, (old.provider ?? "") == (step.provider ?? ""), old.definition == step.definition else { return false }
        // It asks each time: there is nothing silent to read again.
        guard step.standing else { return true }
        guard old.standing, !(old.isInFullAccessOnly && !step.isInFullAccessOnly), same(old.reach, step.reach), (old.program ?? "") == (step.program ?? ""),
              let before = old.input.objectValue, let now = step.input.objectValue, Set(before.keys) == Set(now.keys) else { return false }
        let open = ExtensionActionPolicy.fillable[step.tool] ?? []
        for (key, value) in now {
            if open.contains(key), before[key]?.stringValue != nil, value.stringValue != nil { continue }
            guard let was = before[key], same(was, value) else { return false }
        }
        for (key, source) in step.sources ?? [:] where source == "outside" {
            guard old.sources?[key] == "outside" else { return false }
        }
        return true
    }

    /// Whether the terms themselves are wider than the person read: more actions, a longer time, or another way of starting.
    static func widened(_ old: ExtensionPlan, to new: ExtensionPlan) -> Bool {
        let fewer = new.perDay <= old.perDay && (new.perRun ?? defaultPerRun) <= (old.perRun ?? defaultPerRun)
        let ends: Bool = switch (old.ttl, new.ttl) {
        case (nil, _): true
        case (.some, nil): false
        case (let a?, let b?): b <= a
        }
        return !fewer || !ends || !same(old.when, new.when)
    }

    static let defaultPerRun = 50
    static let perRuns = 1...1000
}
