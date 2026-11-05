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
        // Whole, here, where the summary above the card is clipped: its own words, marked as that, and what it's the only place to say.
        if !plan.when.isEmpty { parts.append(String(localized: "When, in \(ToolFormat.oneLine(ExtensionText.clean(name), 60))'s words: \(ToolFormat.oneLine(ExtensionText.clean(plan.when), 600))", comment: "A plan's card: the extension's own description of when it runs and what else it sets off")) }
        let delta = e.previous != nil
        let shown = delta ? e.fresh : Array(e.lines.indices)
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
            let same = standing.filter { i in e.previous?.steps.contains { ExtensionPlanRules.same($0.input, e.lines[i].step.input) && ExtensionPlanRules.covers($0, e.lines[i].step) } == true }.count
            if same > 0 {
                parts.append(String(localized: "Lines already allowed, unchanged: \(same). What you took out isn't asked about.", comment: "A plan's card after an edit; a count of lines"))
            }
            if standing.count > same {
                parts.append(String(localized: "Lines whose words changed where a plan lets them: \(standing.count - same).", comment: "A plan's card after an edit; a count of lines"))
            }
            if e.widened { parts.append(String(localized: "Its terms changed: how it starts, how long it lasts or how many actions it may make.", comment: "A plan's card after an edit")) }
        }
        // With nothing to allow, there's nothing to return and nothing to count: the card is only what it says it sets off.
        guard !e.lines.isEmpty else { return text(parts) }
        if !delta { parts.append(String(localized: "What these return goes to \(name), which has no network of its own.", comment: "A plan's card; the extension's name")) }
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
                : String(localized: "Apart from the lines that still ask, that's all of it: it won't ask again unless you change it to do something new.", comment: "A plan's card, the last words"))
        }
        return text(parts)
    }

    // MARK: Sections

    private static func blocks(_ e: PlanEvaluation, shown: [Int], name: String, mode: GuardMode) -> [Block] {
        var reads: [(line: PlanEvaluation.Line, i: Int)] = [], changes = reads, sends = reads, asks = reads
        var tells = reads, ai: [String] = [], sets: [String] = []
        for i in shown {
            let line = e.lines[i]
            switch line.step.kind {
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
            list.map { item in
                var text = lineText(item.line, e)
                if why { text += reason(item.line, mode: mode, askOnline: e.askOnline) }
                // A line that stands only in Full access says so wherever it is shown: the mode can change after the card is read.
                else if item.line.step.isInFullAccessOnly {
                    text += " · " + String(localized: "it runs without asking only while Full access is on", comment: "A plan's card: a line that stands only in Full access")
                }
                return text
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
            let names = safe(sourceNames(text, e).joined(separator: ", "), 400)
            // A signed extension's word that a value is the person's own is believed, and said to be its word.
            from[field] = source == "claimed" ? String(localized: "\(names), which the extension says is your own", comment: "A plan's card: a value the extension says comes from the person") : names
        }
        // A whole value is only said where it could be something other than words: a field the schema says is a string can't take a list.
        let properties = tool.spec.inputSchema["properties"]?.objectValue ?? [:]
        let wholes = ExtensionPlanRules.wholeKeys(line.step.input, tool: tool.spec.name)
        let anything = wholes.filter { properties[$0]?["type"]?.stringValue != "string" }
        return ExtensionPlanWords.line(tool: tool, template: line.step.input, from: from, program: line.step.program, whole: anything, omit: wholes.subtracting(anything))
    }

    /// Where a filled value comes from, by the step's own title and the tool it runs, so a title can't be taken for something else; a name no step
    /// makes is said to be one.
    private static func sourceNames(_ text: String, _ e: PlanEvaluation) -> [String] {
        var seen = Set<String>()
        return ExtensionPlanRules.roots(text).filter { seen.insert($0).inserted }.map { root in
            guard let line = e.lines.first(where: { $0.step.name == root }) else {
                return String(localized: "a value named \(root) that no step makes", comment: "A plan's card: a filled-in value whose source isn't a step of the flow")
            }
            let tool = line.tool.map { safe($0.spec.title, 80) } ?? line.step.kind ?? root
            guard let title = line.step.title.map({ safe($0, 80) }), title != tool else { return tool }
            return "\(title) · \(tool)"
        }
    }

    private static func aiRow(_ line: PlanEvaluation.Line, _ e: PlanEvaluation) -> String {
        let title = line.step.title.map { safe($0, 80) } ?? String(localized: "Write with your AI", comment: "A plan's card: a step that hands what it read to the person's AI")
        guard let reads = line.step.reads, !reads.isEmpty else {
            return title + " · " + String(localized: "from everything the steps before it read", comment: "A plan's card: an AI step that names nothing")
        }
        let names = reads.map { read in e.lines.first { $0.step.name == read }.map { $0.step.title ?? $0.tool?.spec.title ?? read } ?? read }
        return title + " · " + String(localized: "from “\(safe(names.joined(separator: ", "), 400))”", comment: "A plan's card: the steps an AI step reads")
    }

    /// Why a line still asks, in words, when there is a reason the person can act on.
    private static func reason(_ line: PlanEvaluation.Line, mode: GuardMode, askOnline: Bool) -> String {
        let why: String? = switch line.verdict.why {
        case "code_field"?: String(localized: "words from outside can't go in a field that runs something", comment: "A plan's card: why a line asks")
        case "reach_field"?: String(localized: "where it goes comes from outside content", comment: "A plan's card: why a line asks")
        case "private_read"?: String(localized: "what you copied is yours alone", comment: "A plan's card: why a line asks")
        case "filled_value"?: String(localized: "a value filled in from outside content", comment: "A plan's card: why a line asks")
        case "server_unpinned"?: String(localized: "its program can't be checked", comment: "A plan's card: why a line asks")
        case "switch_off"?: String(localized: "you turned off passing what it reads on to servers", comment: "A plan's card: why a line asks")
        case "high_risk"?: String(localized: "it can't be undone", comment: "A plan's card: why a line asks")
        case "shell"?: String(localized: "it runs a program", comment: "A plan's card: why a line asks")
        case nil where line.step.standing && line.tool?.spec.capabilities.contains(.network) == true && askOnline: String(localized: "you asked the internet to ask each time", comment: "A plan's card: why a line asks")
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

    /// Where words from outside go, line by line, in plain words: the one thing an approval can't fix is what such words say.
    private static func outsideParagraph(_ e: PlanEvaluation, shown: [Int]) -> String? {
        var sentences: [String] = []
        // The whole plan reads private things and outside words and sends words from them to a server or another extension: said where it happens.
        for i in shown where e.lines[i].verdict.warning == "crossing" {
            guard let tool = e.lines[i].tool, let ext = ExtensionPlanRules.extensionTool(tool) else { continue }
            sentences.append(String(localized: "This flow reads things of yours and outside content, and fills “\(safe(tool.spec.title, 60))” from what it reads: a page's words could put your own there, and they go to \(safe(ext.extensionName, 40)).",
                                    comment: "A plan's card: a warning that outside words could carry the person's own words to a server; a tool's title, an extension's name"))
        }
        for i in shown {
            let line = e.lines[i]
            guard let tool = line.tool, line.step.standing else { continue }
            for field in (line.step.sources ?? [:]).filter({ $0.value == "outside" }).keys.sorted() {
                guard let text = line.step.input[field]?.stringValue else { continue }
                let names = sourceNames(text, e)
                let properties = tool.spec.inputSchema["properties"]?.objectValue ?? [:]
                if tool.spec.name == CompanionJobTool.name {
                    sentences.append(String(localized: "Words from “\(safe(names.joined(separator: ", "), 400))” become the instructions of a job for your companion, which picks its own tools under your trust settings.",
                                            comment: "A plan's card: outside words steer a job; a step's title"))
                    continue
                }
                sentences.append(String(localized: "Words from “\(safe(names.joined(separator: ", "), 400))” go into \(safe(field, 300)) of “\(safe(tool.spec.title, 60))”.",
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
            out += " " + String(localized: "This plan ends by itself in about \(max(1, Int((Double(ttl) / 60).rounded(.up)))) minutes; what it set up, a watch or a reminder, stays until it is removed.", comment: "A plan's card")
        } else {
            out += " " + String(localized: "You can end this in Settings › Add-ons.", comment: "A plan's card")
            // Ending the plan doesn't take back what it made.
            if creates { out += " " + String(localized: "A watch, a reminder or an event it creates stays until you remove it.", comment: "A plan's card") }
        }
        return out
    }
}

extension ExtensionPlanRules {
    /// A standing line that stays inside Sidefolk: its tool is Sidefolk's own, nothing it does could carry words out, and it isn't a risk to undo.
    static func staysInside(_ line: PlanEvaluation.Line) -> Bool {
        guard let tool = line.tool, line.step.standing, !line.step.isInFullAccessOnly, extensionTool(tool) == nil else { return false }
        let spec = tool.spec
        return spec.risk != .high && !PermissionEngine.couldCarryOut(spec, outwardUntyped: !spec.capabilities.isDisjoint(with: [.network, .apps]))
    }
}
