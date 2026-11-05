import Foundation

/// The card for a plan, in Sidefolk's words and nobody else's: what the flow reads, changes and sends out, what it hands to the person's AI and
/// sets off, what still asks, and its limits (D186). Everything is drawn from what the host worked out (`PlanEvaluation`), so the card can't say less
/// than what runs: every line is shown, one by one, with nothing grouped and nothing clipped that matters.
extension ExtensionPlanWords {
    /// A heading and its lines, in the layout `ApprovalText` reads: a line ending in a colon, then "• " rows.
    struct Block {
        var heading: String
        var rows: [String]

        var text: String { heading + "\n" + rows.map { "• \($0)" }.joined(separator: "\n") }
    }

    /// Blocks and paragraphs as one text.
    static func text(_ parts: [String]) -> String { parts.joined(separator: "\n\n") }

    static func card(for e: PlanEvaluation, extensionName name: String, mode: GuardMode) -> String {
        var parts: [String] = []
        let plan = e.plan
        let delta = e.previous != nil
        let shown = delta ? e.fresh : Array(e.lines.indices)
        // The one warning that matters most comes first: the card scrolls, and what is below its fold is read last.
        let crossings = crossingSentences(e, shown: shown)
        if !crossings.isEmpty { parts.append(crossings.joined(separator: " ")) }
        // Whole, here, where the summary above the card is clipped: its own words, marked as that, and what it's the only place to say.
        if !plan.when.isEmpty { parts.append(String(localized: "When, in \(ToolFormat.oneLine(ExtensionText.clean(name), 60))'s words: \(ToolFormat.oneLine(ExtensionText.clean(plan.when), 600))", comment: "A plan's card: the extension's own description of when it runs and what else it sets off")) }
        if delta, !shown.isEmpty {
            parts.append(String(localized: "New, asking you now:", comment: "A plan's card, after an edit: only what the person hasn't read yet follows"))
        }
        parts += blocks(e, shown: shown, name: name, mode: mode).map(\.text)
        if let outside = outsideParagraph(e, shown: shown) { parts.append(outside) }
        if delta {
            // Only what stood and still stands is "already allowed"; a line that asks each time was never allowed, and words changed where the plan lets them are said.
            let standing = e.lines.indices.filter { i in
                let step = e.lines[i].step
                return !e.fresh.contains(i) && step.standing && step.kind == nil && !(step.isInFullAccessOnly && mode != .fullAccess)
            }
            let same = standing.filter { i in e.previous?.steps.contains { $0.tool == e.lines[i].step.tool && ExtensionPlanRules.same($0.input, e.lines[i].step.input) && ExtensionPlanRules.covers($0, e.lines[i].step) } == true }.count
            if same > 0 {
                parts.append(String(localized: "Lines already allowed, unchanged: \(same). What you took out isn't asked about.", comment: "A plan's card after an edit; a count of lines"))
            }
            if standing.count > same {
                parts.append(String(localized: "Lines whose words changed where a plan lets them: \(standing.count - same).", comment: "A plan's card after an edit; a count of lines"))
            }
            if e.widened { parts.append(String(localized: "Its terms changed: what it says about when it runs, how long it lasts, how many actions it may make, or that it goes round a list.", comment: "A plan's card after an edit")) }
        }
        // With nothing to allow, there's nothing to return and nothing to count: the card is only what it says it sets off.
        guard !e.lines.isEmpty else { return text(parts) }
        if !delta { parts.append(String(localized: "What these return goes to \(safe(name, 60)), which has no network of its own.", comment: "A plan's card; the extension's name")) }
        if e.lines.contains(where: { $0.step.tool == CompanionJobTool.name }) {
            parts.append(String(localized: "A job for your companion uses your AI and its tools, under your own trust settings. What it does is in History.", comment: "A plan's card"))
        }
        if e.lines.contains(where: { $0.tool.flatMap(ExtensionPlanRules.extensionTool)?.sandboxed == false }) {
            parts.append(String(localized: "What each tool of a server does is its author's word, which Sidefolk can't check.", comment: "A plan's card: about a server the person added"))
        }
        if e.lines.contains(where: { $0.step.standing && $0.step.isInFullAccessOnly }) {
            parts.append(String(localized: "Lines marked as running without asking only while Full access is on ask each time once it ends.", comment: "A plan's card"))
        }
        parts.append(limits(plan, creates: e.lines.contains { ["watch.create", "reminders.create", "calendar.create"].contains($0.step.tool) }))
        if delta, mode == .askEveryTime {
            parts.append(String(localized: "You asked to be asked every time, so each action still asks before it runs.", comment: "A plan's card, the last words, for someone who chose Ask every time"))
        }
        if !delta {
            parts.append(mode == .askEveryTime
                ? String(localized: "You asked to be asked every time, so each action still asks before it runs.", comment: "A plan's card, the last words, for someone who chose Ask every time")
                : String(localized: "Apart from the lines that still ask, that's all of it. It asks again when its time is up, if a server's program changes, or if you change a setting it depends on, and when you change it to do something new, except that in Auto and in Full access some additions are let through and History shows them. An update of the add-on itself does not ask again.", comment: "A plan's card, the last words"))
        }
        return text(parts)
    }

    /// The lines a card was never shown for (Full access or Auto let them through), as History keeps them on the approval's row: a list with one entry for each
    /// line and one for each of its FIELDS, the places and choices first and the free words last. An entry is the field as the card says it, nothing left out
    /// (every written part between the slots, every item of a list), up to the 300 characters History keeps of a string; one that is longer says how much was cut.
    /// There are at most 60 entries, and then how many more, so nothing is dropped without a count.
    static func addedLines(_ e: PlanEvaluation) -> [String] {
        var out: [String] = []
        for i in e.fresh {
            guard let tool = e.lines[i].tool else { continue }
            out += historyEntries(e.lines[i], tool: tool, e)
        }
        return capped(out, 60)
    }

    private static func historyEntries(_ line: PlanEvaluation.Line, tool: any Tool, _ e: PlanEvaluation) -> [String] {
        let properties = tool.spec.inputSchema["properties"]?.objectValue ?? [:]
        let ext = ExtensionPlanRules.extensionTool(tool)
        let who = ext.map { " (" + safe($0.extensionName, 30) + ")" } ?? ""
        let title = safe(tool.spec.title, 50) + who
        var header = title
        // A server whose program Sidefolk couldn't check says so, as the card does.
        if ext?.sandboxed == false, line.step.program == nil { header += " · " + String(localized: "program: not checked", comment: "History: a plan's line for a server whose program can't be checked") }
        let fields = (line.step.input.objectValue ?? [:]).sorted { a, b in
            let ra = ExtensionPlanRules.fieldClass(a.key, schema: properties[a.key]) == .freeText ? 1 : 0
            let rb = ExtensionPlanRules.fieldClass(b.key, schema: properties[b.key]) == .freeText ? 1 : 0
            return ra != rb ? ra < rb : a.key < b.key
        }
        return [header] + fields.map { key, value in cut(title + " / " + safe(key, 40) + ": " + historyValue(key, value, line, e)) }
    }

    /// A field's value as the card says it: written words quoted, a slot as the steps it comes from with every written part around it, a list with its count.
    private static func historyValue(_ key: String, _ value: JSONValue, _ line: PlanEvaluation.Line, _ e: PlanEvaluation) -> String {
        if let text = value.stringValue, ExtensionPlanRules.hasSlot(text) {
            let literals = ExtensionPlanRules.literals(text), roots = ExtensionPlanRules.roots(text)
            var shown = ""
            for (n, root) in roots.enumerated() {
                shown += safe(n < literals.count ? literals[n] : "", 300)
                shown += String(localized: "[from \(safe(describe([root], e).joined(separator: ", "), 80))]", comment: "History: a filled-in value, from the steps named")
            }
            shown += safe(literals.count > roots.count ? literals[roots.count] : "", 300)
            switch line.step.sources?[key] {
            case "outside"?: return String(localized: "\(shown) (outside content)", comment: "History: a filled-in value that comes from outside content")
            case "claimed"?: return String(localized: "\(shown) (the add-on says it's yours)", comment: "History: a filled-in value the extension says is the person's own")
            case "inside"?: return String(localized: "\(shown) (your answer or the clock)", comment: "History: a filled-in value that is the person's typed answer or the clock")
            default: return shown
            }
        }
        func one(_ v: JSONValue) -> String { v.stringValue.map { "“" + safe($0, 300) + "”" } ?? safe(v.jsonString, 300) }
        switch value {
        case .string(let text): return "“" + safe(text, 300) + "”"
        case .array(let items): return String(localized: "list (\(items.count)): \(items.map(one).joined(separator: ", "))", comment: "History: a list a plan wrote, with how many items it has")
        case .object: return String(localized: "record: \(safe(value.jsonString, 300))", comment: "History: a record a plan wrote")
        default: return safe(value.jsonString, 300)
        }
    }

    /// An entry as History keeps it (a string of at most 300 characters): longer, it ends with how much was cut.
    private static func cut(_ text: String) -> String {
        guard text.count > 290 else { return text }
        return String(text.prefix(265)) + String(localized: "…[\(text.count - 265) cut]", comment: "History: an entry was cut; how many characters")
    }

    /// At most `limit` entries, one line each so History keeps every one whole; past it, a last entry says how many more there were.
    static func capped(_ lines: [String], _ limit: Int) -> [String] {
        guard lines.count > limit else { return lines }
        return Array(lines.prefix(limit - 1)) + [String(localized: "+\(lines.count - limit + 1) more", comment: "A list was cut; how many more")]
    }

    // MARK: Sections

    private static func blocks(_ e: PlanEvaluation, shown: [Int], name: String, mode: GuardMode) -> [Block] {
        var reads: [(line: PlanEvaluation.Line, i: Int)] = [], changes = reads, sends = reads, asks = reads
        var tells = reads, ai: [String] = [], sets: [String] = []
        for i in shown {
            let line = e.lines[i]
            switch line.step.kind {
            case "value": continue
            case "ai": ai.append(aiRow(line, e))
            case "flow": sets.append(String(localized: "“\(safe(line.step.input["name"]?.stringValue ?? "", 80))”, which keeps its own approval, as the extension says", comment: "A plan's card: another flow it sets off; its name"))
            default:
                // What stands only in Full access asks under every other mode, and the card says so.
                if !line.step.standing || (line.step.isInFullAccessOnly && mode != .fullAccess) || (e.askOnline && usesNetwork(line)) { asks.append((line, i)) }
                else if line.tool.map({ tellsThePerson($0) }) == true { tells.append((line, i)) }
                else if sendsOut(line) { sends.append((line, i)) }
                else if line.tool?.spec.mutates == false { reads.append((line, i)) }
                else { changes.append((line, i)) }
            }
        }
        func rows(_ list: [(line: PlanEvaluation.Line, i: Int)], why: Bool = false) -> [String] {
            // The same line again is read once: the same tool and the same bytes in every word it shows (not just text that compares equal), so nothing is
            // hidden by saying how many.
            struct Key: Hashable { var tool: String; var bytes: [UInt8] }
            var order: [Key] = [], texts: [Key: String] = [:], counts: [Key: Int] = [:]
            for item in list {
                var text = lineText(item.line, e)
                if why { text += reason(item.line, mode: mode, askOnline: e.askOnline) }
                // A line that stands only in Full access says so wherever it is shown: the mode can change after the card is read.
                else if item.line.step.isInFullAccessOnly {
                    text += " · " + String(localized: "it runs without asking only while Full access is on", comment: "A plan's card: a line that stands only in Full access")
                }
                let key = Key(tool: item.line.step.tool + "\u{1}" + (item.line.step.provider ?? ""), bytes: Array(text.utf8))
                if counts[key] == nil { order.append(key); texts[key] = text }
                counts[key, default: 0] += 1
            }
            return order.map { key in
                let n = counts[key] ?? 1, text = texts[key] ?? ""
                return n > 1 ? text + " " + String(localized: "× \(n)", comment: "A plan's card: the same line, this many times") : text
            }
        }
        var out: [Block] = []
        if !reads.isEmpty { out.append(Block(heading: String(localized: "It reads:", comment: "A plan's card"), rows: rows(reads))) }
        if !changes.isEmpty { out.append(Block(heading: String(localized: "It changes:", comment: "A plan's card"), rows: rows(changes))) }
        if !sends.isEmpty { out.append(Block(heading: String(localized: "It sends out:", comment: "A plan's card"), rows: rows(sends))) }
        if !tells.isEmpty { out.append(Block(heading: String(localized: "It tells or asks you:", comment: "A plan's card: a notice, a question, a line said aloud"), rows: rows(tells))) }
        if !ai.isEmpty { out.append(Block(heading: String(localized: "What these steps read goes to your AI, to write from:", comment: "A plan's card"), rows: ai)) }
        if !sets.isEmpty { out.append(Block(heading: String(localized: "It sets off:", comment: "A plan's card"), rows: sets)) }
        if !asks.isEmpty { out.append(Block(heading: String(localized: "It will still ask you each time:", comment: "A plan's card"), rows: rows(asks, why: true))) }
        return out
    }

    /// A notice, a question, a line said aloud or the companion's move: reaching the person is all it does, though it changes nothing of theirs.
    private static func tellsThePerson(_ tool: any Tool) -> Bool {
        ExtensionActionPolicy.reachesThePerson.contains(tool.spec.name) || ["voice.say", "companion.play"].contains(tool.spec.name)
    }

    /// A line whose tool can reach the network: it asks each time while the person has asked the internet to (D47), whatever a plan says.
    private static func usesNetwork(_ line: PlanEvaluation.Line) -> Bool { line.tool?.spec.capabilities.contains(.network) == true }

    /// Whether a standing line leaves the Mac or hands words to another program: a server, another extension, a link, the network.
    private static func sendsOut(_ line: PlanEvaluation.Line) -> Bool {
        guard let tool = line.tool else { return false }
        return ExtensionPlanRules.extensionTool(tool) != nil || !tool.spec.capabilities.isDisjoint(with: [.network, .apps])
    }

    private static func lineText(_ line: PlanEvaluation.Line, _ e: PlanEvaluation) -> String {
        guard let tool = line.tool else { return ToolFormat.oneLine(ExtensionText.clean(line.step.title ?? ""), 80) }
        var from: [String: String] = [:]
        for (field, source) in line.step.sources ?? [:] {
            guard let text = line.step.input[field]?.stringValue else { continue }
            let names = listed(sourceNames(text, e))
            // A signed extension's word that a value is the person's own is believed, and said to be its word.
            from[field] = source == "claimed" ? String(localized: "\(names), which the extension says is your own", comment: "A plan's card: a value the extension says comes from the person") : names
        }
        // A field that is one slot takes a value of any kind, or none, whatever the schema says (what runs is what the host matched, not what the schema hopes).
        let wholes = ExtensionPlanRules.wholeKeys(line.step.input, tool: tool.spec.name)
        return ExtensionPlanWords.line(tool: tool, template: line.step.input, from: from, program: line.step.program, whole: wholes, omit: [])
    }

    /// Names for the card: as many as fit in 400 characters, and how many more there are, so a long list can't push one past the cut unseen.
    private static func listed(_ names: [String]) -> String {
        var shown: [String] = [], used = 0
        for name in names {
            let text = safe(name, 400)
            let added = (shown.isEmpty ? 0 : 2) + text.count
            if !shown.isEmpty, used + added > 400 { break }
            shown.append(text)
            used += added
        }
        let more = names.count - shown.count
        let list = shown.joined(separator: ", ")
        return more > 0 ? list + " " + String(localized: "(and \(more) more)", comment: "A plan's card: a list of a step's sources was cut; how many more") : list
    }

    /// Where a filled value comes from, by the step's own title and the tool it runs, so a title can't be taken for something else; a name no step
    /// makes is said to be one.
    private static func sourceNames(_ text: String, _ e: PlanEvaluation) -> [String] { describe(ExtensionPlanRules.roots(text), e) }

    /// The steps these names stand for, each once, a step that only passes words on named by what it reads, down to the steps that make them; each by its own
    /// title and its tool, so a title can't pass for something else. A name no step makes is said to be one.
    private static func describe(_ names: [String], _ e: PlanEvaluation) -> [String] {
        var visited = Set<String>(), out: [String] = []
        func expand(_ root: String) {
            guard visited.insert(root).inserted else { return }
            guard let line = e.lines.first(where: { $0.step.name == root }) else {
                out.append(String(localized: "a value named \(root) that no step makes", comment: "A plan's card: a filled-in value whose source isn't a step of the flow"))
                return
            }
            if line.step.kind == "value" {
                for read in line.step.reads ?? [] { expand(read) }
                return
            }
            let tool = line.tool.map { safe($0.spec.title, 80) } ?? line.step.kind ?? root
            let text: String
            if let title = line.step.title.map({ safe($0, 80) }), title != tool { text = "\(title) · \(tool)" } else { text = tool }
            if !out.contains(text) { out.append(text) }
        }
        names.forEach(expand)
        return out
    }

    private static func aiRow(_ line: PlanEvaluation.Line, _ e: PlanEvaluation) -> String {
        let title = line.step.title.map { safe($0, 80) } ?? String(localized: "Write with your AI", comment: "A plan's card: a step that hands what it read to the person's AI")
        guard let reads = line.step.reads, !reads.isEmpty else {
            return title + " · " + String(localized: "from everything the steps before it read", comment: "A plan's card: an AI step that names nothing")
        }
        let names = describe(reads, e)
        return title + " · " + String(localized: "from “\(listed(names))”", comment: "A plan's card: the steps an AI step reads")
    }

    /// Why a line still asks, in words, when there is a reason the person can act on.
    private static func reason(_ line: PlanEvaluation.Line, mode: GuardMode, askOnline: Bool) -> String {
        let why: String? = switch line.verdict.why {
        case "code_field"?: String(localized: "nothing filled in can go in a field that runs something", comment: "A plan's card: why a line asks")
        case "reach_field"?: String(localized: "where it goes comes from outside content", comment: "A plan's card: why a line asks")
        case "declared_place"?: String(localized: "where it goes comes from a name the extension wrote, which Sidefolk can't check", comment: "A plan's card: why a line asks")
        case "private_read"?: String(localized: "what you copied is yours alone", comment: "A plan's card: why a line asks")
        case "filled_value"?: String(localized: "a value filled in from outside content", comment: "A plan's card: why a line asks")
        case "server_unpinned"?:
            switch line.verdict.detail {
            case "launcher"?: String(localized: "it starts through a launcher, interpreter or build tool, so what runs isn't the file Sidefolk can check", comment: "A plan's card: why a server's line asks")
            case "script"?: String(localized: "its program is a script, not a compiled program, so Sidefolk can't check it", comment: "A plan's card: why a server's line asks")
            case "loads"?: String(localized: "it is started with a file or folder it loads, which Sidefolk can't check", comment: "A plan's card: why a server's line asks")
            case "path"?: String(localized: "its program is named without a full path, so Sidefolk can't tell which one runs", comment: "A plan's card: why a server's line asks")
            default: String(localized: "its program can't be checked", comment: "A plan's card: why a line asks")
            }
        case "switch_off"?: String(localized: "you turned off passing what it reads on to servers", comment: "A plan's card: why a line asks")
        case "high_risk"?: String(localized: "it can't be undone", comment: "A plan's card: why a line asks")
        case "shell"?: String(localized: "it runs a program", comment: "A plan's card: why a line asks")
        case nil where line.step.standing && line.tool?.spec.capabilities.contains(.network) == true && askOnline: String(localized: "you asked the internet to ask each time (this line runs without asking if you change that)", comment: "A plan's card: why a line asks")
        case "text_to_read"?: String(localized: "its words are read in full each time", comment: "A plan's card: why a line asks")
        case "nested_slot"?, "unreadable_value"?: String(localized: "a value that can't be shown in full", comment: "A plan's card: why a line asks")
        default: nil
        }
        var out = why.map { " · " + $0 } ?? ""
        // Under Full access it stands: the card says so, since the mode can change after the card is read.
        if line.step.standing, line.step.isInFullAccessOnly {
            out += " · " + String(localized: "it runs without asking only while Full access is on", comment: "A plan's card: a line that stands only in Full access")
        }
        return out
    }

    // MARK: Outside content and limits

    /// The whole plan reads private things and outside words and sends words from them to a server or another extension: said where it happens.
    private static func crossingSentences(_ e: PlanEvaluation, shown: [Int]) -> [String] {
        var sentences: [String] = []
        for i in shown where e.lines[i].verdict.warning == "crossing" {
            guard let tool = e.lines[i].tool, let ext = ExtensionPlanRules.extensionTool(tool) else { continue }
            sentences.append(String(localized: "This flow reads things of yours and outside content, and fills “\(safe(tool.spec.title, 60))” from what it reads: words from a page or a file could put your own there, and they go to \(safe(ext.extensionName, 40)).",
                                    comment: "A plan's card: a warning that outside words could carry the person's own words to a server; a tool's title, an extension's name"))
        }
        return sentences
    }

    /// Where words from outside go, line by line, in plain words: the one thing an approval can't fix is what such words say.
    private static func outsideParagraph(_ e: PlanEvaluation, shown: [Int]) -> String? {
        var sentences: [String] = []
        for i in shown {
            let line = e.lines[i]
            guard let tool = line.tool, line.step.standing else { continue }
            for field in (line.step.sources ?? [:]).filter({ $0.value == "outside" }).keys.sorted() {
                guard let text = line.step.input[field]?.stringValue else { continue }
                let names = sourceNames(text, e)
                let properties = tool.spec.inputSchema["properties"]?.objectValue ?? [:]
                if tool.spec.name == CompanionJobTool.name {
                    sentences.append(String(localized: "Words from “\(listed(names))” become the instructions of a job for your companion, which picks its own tools under your trust settings.",
                                            comment: "A plan's card: outside words steer a job; a step's title"))
                    continue
                }
                sentences.append(String(localized: "Words from “\(listed(names))” go into \(safe(field, 300)) of “\(safe(tool.spec.title, 60))”.",
                                        comment: "A plan's card: where outside words go; a step's title, a field, a tool's title"))
            }
        }
        guard !sentences.isEmpty else { return nil }
        return String(localized: "Outside content:", comment: "A plan's card: a paragraph on words that come from a web page, a file or another program") + " "
            + sentences.joined(separator: " ") + " "
            + String(localized: "They can't change which tool, server or fields it uses, only what goes into the fields named here.", comment: "A plan's card")
    }

    private static func limits(_ plan: ExtensionPlan, creates: Bool) -> String {
        let perRun = plan.perRun ?? ExtensionPlanRules.defaultPerRun
        var out = plan.goesRound == true
            ? String(localized: "It goes round a list. Limit a day: \(plan.perDay). Limit in a run, as the extension counts runs: \(perRun).", comment: "A plan's card: its limits")
            : String(localized: "Limit a day: \(plan.perDay). Limit in a run, as the extension counts runs: \(perRun).", comment: "A plan's card: its limits")
        if let ttl = plan.ttl {
            out += " " + String(localized: "This plan ends by itself after \(max(1, Int((Double(ttl) / 60).rounded(.up)))) min at the most; what it set up, a watch or a reminder, stays until it is removed.", comment: "A plan's card")
        } else {
            out += " " + String(localized: "You can end this in Settings › Add-ons.", comment: "A plan's card")
            // Ending the plan doesn't take back what it made.
            if creates { out += " " + String(localized: "A watch, a reminder or an event it creates stays until you remove it.", comment: "A plan's card") }
        }
        return out
    }
}

extension ExtensionPlanRules {
    /// A standing line that stays inside Sidefolk: its tool is Sidefolk's own, nothing it does could carry words out, it isn't a risk to undo, and it WRITES or
    /// TELLS (a note, a notice, a reminder, a question, a line said aloud). A read whose answer goes back to the add-on (files, calendar, agenda, notes,
    /// Apple Notes) always shows a card in Auto: what it hands over is private, and nobody would have read the line (D187, the founder's call).
    static func staysInside(_ line: PlanEvaluation.Line) -> Bool {
        guard let tool = line.tool, line.step.standing, !line.step.isInFullAccessOnly, extensionTool(tool) == nil else { return false }
        let spec = tool.spec
        let writesOrTells = (spec.mutates || ExtensionActionPolicy.reachesThePerson.contains(spec.name)) && spec.name != "companion.play"
        // A tool that reads private things and gives them back, whatever else it does (`applenotes.copy` reads whole notes in and returns their titles), is a read.
        let reads = !spec.capabilities.isDisjoint(with: [.macApps, .filesRead, .calendar])
        return writesOrTells && !reads && spec.risk != .high && !PermissionEngine.couldCarryOut(spec, outwardUntyped: !spec.capabilities.isDisjoint(with: [.network, .apps]))
    }
}
