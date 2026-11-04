import Foundation

/// The card for a plan, in Sidefolk's words and nobody else's: what the flow reads, changes and sends out, what it hands to the person's AI and
/// sets off, what still asks, and its limits (D186). Everything is drawn from what the host worked out (`PlanEvaluation`), so the card can't say less
/// than what runs: every line is shown, a server's one by one, and the only grouping is of lines that differ solely in words the plan leaves open.
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
        if !plan.when.isEmpty { parts.append(String(localized: "When, in \(name)'s words: \(plan.when)", comment: "A plan's card: the extension's own description of when it runs and what else it sets off")) }
        let delta = e.previous != nil
        let shown = delta ? e.fresh : Array(e.lines.indices)
        if delta, !shown.isEmpty {
            parts.append(String(localized: "New, asking you now:", comment: "A plan's card, after an edit: only what the person hasn't read yet follows"))
        }
        parts += blocks(e, shown: shown, name: name, mode: mode).map(\.text)
        if let outside = outsideParagraph(e, shown: shown) { parts.append(outside) }
        if delta {
            let kept = e.lines.indices.filter { !e.fresh.contains($0) }.count
            if kept > 0 {
                parts.append(String(localized: "Already allowed, unchanged: \(kept) things. What you took out isn't asked about.", comment: "A plan's card after an edit; a count of lines"))
            }
            if e.widened { parts.append(String(localized: "Its terms changed: how it starts, how long it lasts or how many actions it may make.", comment: "A plan's card after an edit")) }
        }
        // With nothing to allow, there's nothing to return and nothing to count: the card is only what it says it sets off.
        guard !e.lines.isEmpty else { return text(parts) }
        if !delta { parts.append(String(localized: "What these return goes to \(name), which can't reach the internet by itself.", comment: "A plan's card; the extension's name")) }
        if e.lines.contains(where: { $0.step.tool == CompanionJobTool.name }) {
            parts.append(String(localized: "A job for your companion uses your AI and its tools, under your own trust settings. What it does is in History.", comment: "A plan's card"))
        }
        parts.append(limits(plan))
        if !delta {
            parts.append(String(localized: "That's all of it. It won't ask again unless you change it to do something new.", comment: "A plan's card, the last words"))
        }
        return text(parts)
    }

    // MARK: Sections

    private static func blocks(_ e: PlanEvaluation, shown: [Int], name: String, mode: GuardMode) -> [Block] {
        var reads: [(line: PlanEvaluation.Line, i: Int)] = [], changes = reads, sends = reads, asks = reads
        var ai: [String] = [], sets: [String] = []
        for i in shown {
            let line = e.lines[i]
            switch line.step.kind {
            case "ai": ai.append(aiRow(line, e))
            case "flow": sets.append(String(localized: "\(line.step.input["name"]?.stringValue ?? ""), which has its own approval", comment: "A plan's card: another flow it sets off; its name"))
            default:
                // What stands only in Full access asks under every other mode, and the card says so.
                if !line.step.standing || (line.step.isInFullAccessOnly && mode != .fullAccess) { asks.append((line, i)) }
                else if sendsOut(line) { sends.append((line, i)) }
                else if line.tool?.spec.mutates == false { reads.append((line, i)) }
                else { changes.append((line, i)) }
            }
        }
        func rows(_ list: [(line: PlanEvaluation.Line, i: Int)], why: Bool = false) -> [String] {
            grouped(list.map(\.line), e: e).map { row in why ? row.text + reason(row.line, mode: mode) : row.text }
        }
        var out: [Block] = []
        if !reads.isEmpty { out.append(Block(heading: String(localized: "It reads:", comment: "A plan's card"), rows: rows(reads))) }
        if !changes.isEmpty { out.append(Block(heading: String(localized: "It changes:", comment: "A plan's card"), rows: rows(changes))) }
        if !sends.isEmpty { out.append(Block(heading: String(localized: "It sends out:", comment: "A plan's card"), rows: rows(sends))) }
        if !ai.isEmpty { out.append(Block(heading: String(localized: "What these steps read goes to your AI, to write from:", comment: "A plan's card"), rows: ai)) }
        if !sets.isEmpty { out.append(Block(heading: String(localized: "It sets off:", comment: "A plan's card"), rows: sets)) }
        if !asks.isEmpty { out.append(Block(heading: String(localized: "It will still ask you each time:", comment: "A plan's card"), rows: rows(asks, why: true))) }
        return out
    }

    /// Whether a standing line leaves the Mac or hands words to another program: a server, another extension, a link, the network.
    private static func sendsOut(_ line: PlanEvaluation.Line) -> Bool {
        guard let tool = line.tool else { return false }
        return ExtensionPlanRules.extensionTool(tool) != nil || !tool.spec.capabilities.isDisjoint(with: [.network, .apps])
    }

    private struct Row {
        var line: PlanEvaluation.Line
        var text: String
    }

    /// One row a line, a server's always its own. Lines of one tool that differ only in words the plan leaves open come to one row with a count.
    private static func grouped(_ lines: [PlanEvaluation.Line], e: PlanEvaluation) -> [Row] {
        var out: [(row: Row, count: Int)] = [], at: [String: Int] = [:]
        for line in lines {
            guard let tool = line.tool else { continue }
            let open = ExtensionActionPolicy.fillable[tool.spec.name] ?? []
            let isServer = ExtensionPlanRules.extensionTool(tool)?.sandboxed == false
            let fixed = (line.step.input.objectValue ?? [:]).filter { !open.contains($0.key) }
            let key = tool.spec.name + "\u{1}" + (line.step.provider ?? "") + "\u{1}" + JSONValue.object(fixed).jsonString
            if !isServer, !open.isEmpty, let seen = at[key] {
                out[seen].count += 1
                continue
            }
            if !isServer, !open.isEmpty { at[key] = out.count }
            out.append((Row(line: line, text: lineText(line, e)), 1))
        }
        return out.map { row, count in
            guard count > 1 else { return row }
            return Row(line: row.line, text: row.text + " " + String(localized: "(\(count) times, with different words)", comment: "A plan's card: one line standing for several that differ only in words the plan leaves open"))
        }
    }

    private static func lineText(_ line: PlanEvaluation.Line, _ e: PlanEvaluation) -> String {
        guard let tool = line.tool else { return line.step.title ?? "" }
        var from: [String: String] = [:]
        for (field, source) in line.step.sources ?? [:] where source == "outside" || source == "inside" {
            guard let text = line.step.input[field]?.stringValue else { continue }
            let names = ExtensionPlanRules.roots(text).map { root in
                e.lines.first { $0.step.name == root }.map { $0.step.title ?? $0.tool?.spec.title ?? root } ?? root
            }
            from[field] = ToolFormat.oneLine(ExtensionText.clean(names.joined(separator: ", ")), 80)
        }
        return ExtensionPlanWords.line(tool: tool, template: line.step.input, from: from, program: line.step.program)
    }

    private static func aiRow(_ line: PlanEvaluation.Line, _ e: PlanEvaluation) -> String {
        let title = line.step.title ?? String(localized: "Write with your AI", comment: "A plan's card: a step that hands what it read to the person's AI")
        guard let reads = line.step.reads, !reads.isEmpty else {
            return title + " · " + String(localized: "from everything the steps before it read", comment: "A plan's card: an AI step that names nothing")
        }
        let names = reads.map { read in e.lines.first { $0.step.name == read }.map { $0.step.title ?? $0.tool?.spec.title ?? read } ?? read }
        return title + " · " + String(localized: "from “\(ToolFormat.oneLine(ExtensionText.clean(names.joined(separator: ", ")), 120))”", comment: "A plan's card: the steps an AI step reads")
    }

    /// Why a line still asks, in words, when there is a reason the person can act on.
    private static func reason(_ line: PlanEvaluation.Line, mode: GuardMode) -> String {
        let why: String? = switch line.verdict.why {
        case "code_field"?: String(localized: "words from outside can't go in a field that runs something", comment: "A plan's card: why a line asks")
        case "reach_field"?: String(localized: "where it goes comes from outside content", comment: "A plan's card: why a line asks")
        case "crossing"?: String(localized: "it reads your own things and outside content, then sends words on", comment: "A plan's card: why a line asks")
        case "private_read"?: String(localized: "what you copied is yours alone", comment: "A plan's card: why a line asks")
        case "filled_value"?: String(localized: "a value filled in from outside content", comment: "A plan's card: why a line asks")
        case "server_unpinned"?: String(localized: "its program can't be checked", comment: "A plan's card: why a line asks")
        case "switch_off"?: String(localized: "you turned off passing what it reads on to servers", comment: "A plan's card: why a line asks")
        case "high_risk"?: String(localized: "it can't be undone", comment: "A plan's card: why a line asks")
        case "shell"?, "text_to_read"?: String(localized: "it runs a program", comment: "A plan's card: why a line asks")
        case "nested_slot"?, "unreadable_value"?: String(localized: "a value that can't be shown in full", comment: "A plan's card: why a line asks")
        default: nil
        }
        return why.map { " · " + $0 } ?? ""
    }

    // MARK: Outside content and limits

    /// Where words from outside go, line by line, in plain words: the one thing an approval can't fix is what such words say.
    private static func outsideParagraph(_ e: PlanEvaluation, shown: [Int]) -> String? {
        var sentences: [String] = []
        for i in shown {
            let line = e.lines[i]
            guard let tool = line.tool, line.step.standing else { continue }
            for field in (line.step.sources ?? [:]).filter({ $0.value == "outside" }).keys.sorted() {
                guard let text = line.step.input[field]?.stringValue else { continue }
                let names = ExtensionPlanRules.roots(text).map { root in
                    e.lines.first { $0.step.name == root }.map { $0.step.title ?? $0.tool?.spec.title ?? root } ?? root
                }
                let properties = tool.spec.inputSchema["properties"]?.objectValue ?? [:]
                sentences.append(String(localized: "Words from “\(ToolFormat.oneLine(ExtensionText.clean(names.joined(separator: ", ")), 80))” go into \(ArgumentWords.label(field, properties[field])) of “\(ToolFormat.oneLine(ExtensionText.clean(tool.spec.title), 60))”.",
                                        comment: "A plan's card: where outside words go; a step's title, a field, a tool's title"))
            }
        }
        guard !sentences.isEmpty else { return nil }
        return String(localized: "Outside content:", comment: "A plan's card: a paragraph on words that come from a web page, a file or another program") + " "
            + sentences.joined(separator: " ") + " "
            + String(localized: "They can't change which tool, server or fields it uses.", comment: "A plan's card")
    }

    private static func limits(_ plan: ExtensionPlan) -> String {
        let perRun = plan.perRun ?? ExtensionPlanRules.defaultPerRun
        var out = plan.goesRound == true
            ? String(localized: "It goes round a list: up to \(perRun) actions each run, and at most \(plan.perDay) a day.", comment: "A plan's card: its limits")
            : String(localized: "At most \(perRun) actions a run and \(plan.perDay) a day.", comment: "A plan's card: its limits")
        if let ttl = plan.ttl {
            out += " " + String(localized: "This ends by itself in \(max(1, ttl / 60)) minutes.", comment: "A plan's card")
        } else {
            out += " " + String(localized: "You can end this in Settings › Add-ons.", comment: "A plan's card")
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
