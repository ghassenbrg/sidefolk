import Foundation
import Synchronization

/// What an extension may do without a card, because the person read it (D110, SECURITY T44): its tools and their exact values, and
/// the few words left to fill in. Kept with its preferences, gone with it.
public struct ExtensionPlan: Codable, Sendable, Hashable {
    public struct Step: Codable, Sendable, Hashable {
        public var tool: String
        /// The call as written, `{{name}}` where words are filled in.
        public var input: JSONValue
        /// The tool as it was: a changed tool is not what the person allowed.
        public var definition: String
        /// Where the call goes, as the tool says, from what is written: a value that moves it doesn't match.
        public var reach: String
        /// False: it was shown as asking each time, so it asks (`ExtensionActionPolicy`).
        public var standing: Bool
        /// Who offered the tool when it was allowed (`ExtensionTool.provider`; empty for Sidefolk's own). A short name is free again once
        /// its extension is gone, so a tool of the same name and shape from another extension is not what the person read (T52). A plan
        /// written before this has none: its steps on an extension's tool ask until the plan is approved again.
        public var provider: String?
        /// The step's name in the extension's flow, for `{{name}}` in later steps (D186).
        public var name: String?
        /// Where each filled value comes from, by the field it goes in: "inside" (the person's own answer, the clock) or "outside" (everything
        /// else, by default). Worked out by the host from the plan, never taken from the program, except the names a signed extension says are inside.
        public var sources: [String: String]?
        /// It stands only while Full access is on: it would ask under any other mode (D188).
        public var fullAccessOnly: Bool?
        /// A server's program as it was when the person read this, when Sidefolk can check one (D189).
        public var program: String?
        /// A step with no tool of Sidefolk's behind it, which the card still says: "ai" (what it reads goes to the person's AI) or "flow" (it sets
        /// another flow off, which has its own approval). Such a step never stands or asks; it only counts as read.
        public var kind: String?
        /// The step's own title, for the card.
        public var title: String?
        /// For an "ai" step: the names of the steps whose words it reads, when its extension says.
        public var reads: [String]?
        /// What each filled field is fed by, as a fingerprint of the steps it points at (their tool, provider, definition and kind): an edit that points the
        /// same words at another kind of step is something new, though the step itself is unchanged (D187).
        public var feeds: [String: String]?

        var isInFullAccessOnly: Bool { fullAccessOnly == true }
    }

    public var id: String
    public var title: String
    public var when: String
    public var steps: [Step]
    /// Who was allowed: the same permissions, from the same kind of pack. A copy under the same id that isn't, isn't.
    public var owner: String
    public var approvedAt: Date
    public var expiresAt: Date?
    public var perDay: Int
    /// How many actions one run may make, when the extension sends a run id with its calls (D189).
    public var perRun: Int?
    /// How long it was allowed to last, in seconds: a longer one is something new (D187).
    public var ttl: Int?
    /// It goes round a list: what its lines do, they do many times a run.
    public var goesRound: Bool?
    /// Allowed by Full access with no card: nobody read it. It stands only while Full access is on, and any other mode asks for a card first (D188).
    public var answeredUnread: Bool?
    /// It read the person's own things and outside content and fills a server line from them (the card's warning): becoming so is new.
    public var crossing: Bool?

    public func live(at now: Date, owner: String) -> Bool { self.owner == owner && (expiresAt.map { $0 > now } ?? true) }
}

/// A plan as Settings shows it, to end it.
public struct ExtensionPlanInfo: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var when: String
    public var actions: Int
    public var approvedAt: Date
    public var expiresAt: Date?
}

enum ExtensionPlanRules {
    /// The most distinct lines a plan may hold, and the most rows the program may send for them (the same line once, D186).
    static let maxSteps = 64
    static let maxRows = 256
    /// The most a plan may weigh as sent, so working it out stays small on the host's own actor.
    static let maxPlanBytes = 256_000
    static let ttls = 60...3600
    static let perDays = 1...1000
    static let defaultPerDay = 200
    /// How far past the person's click, command or clean request an extension may still ask for a plan: a card is never started by
    /// a timer, a page's words or a model steered by what it read (T3).
    static let personWindow: TimeInterval = 30
    /// How long the person's own click may be used to answer a plan under Full access: a click and the plan it started come close together.
    static let clickWindow: TimeInterval = 10

    static let slot = try! NSRegularExpression(pattern: #"\{\{\s*[A-Za-z0-9_.\[\]-]{1,60}\s*\}\}"#)

    static func hasSlot(_ text: String) -> Bool {
        slot.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The written parts around the slots, in order.
    static func literals(_ template: String) -> [String] {
        var out: [String] = [], from = template.startIndex
        for match in slot.matches(in: template, range: NSRange(template.startIndex..., in: template)) {
            guard let range = Range(match.range, in: template) else { continue }
            out.append(String(template[from..<range.lowerBound]))
            from = range.upperBound
        }
        out.append(String(template[from...]))
        return out
    }

    /// A call too long to match against a plan asks instead: matching runs on the host's own actor.
    static func short(_ input: JSONValue) -> Bool { input.jsonString.utf8.count <= 64_000 }

    /// Whether a program's own word for how a call was written is one to read: a size a card could show, and a call not so long that matching it is work.
    static func readable(written template: JSONValue, for input: JSONValue) -> Bool {
        short(input) && written(template).allSatisfy { plain($0) && $0.count <= ExtensionPlanWords.valueLimit } && objectsFit(template)
    }

    /// Whether a step leaves words to fill in.
    static func fillsIn(_ template: JSONValue) -> Bool {
        (template.objectValue ?? [:]).values.contains { $0.stringValue.map(hasSlot) ?? false }
    }

    /// How long the values a call filled in are, written parts and all.
    static func filledLength(_ input: JSONValue, template: JSONValue) -> Int {
        (template.objectValue ?? [:]).reduce(0) { sum, field in
            guard let written = field.value.stringValue, hasSlot(written) else { return sum }
            return sum + (input[field.key]?.stringValue?.count ?? 0)
        }
    }

    /// Whether two written values are the same bytes. Swift's `==` takes canonically equal strings as equal, and they aren't: `é` written two ways
    /// is two addresses, and a program could say something by which it writes.
    static func same(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
    static func same(_ a: JSONValue, _ b: JSONValue) -> Bool { same(a.jsonString, b.jsonString) }

    /// Whether `text` is `template` with its slots filled in: the written parts unchanged, byte for byte, and in order.
    static func fits(_ text: String, template: String) -> Bool {
        let parts = literals(template).map { Array($0.utf8) }, bytes = Array(text.utf8)
        guard parts.count > 1 else { return same(text, template) }
        guard let first = parts.first, let last = parts.last, bytes.starts(with: first), bytes.count >= first.count + last.count else { return false }
        var from = first.count
        let end = bytes.count - last.count
        guard Array(bytes[end...]) == last else { return false }
        for part in parts.dropFirst().dropLast() where !part.isEmpty {
            guard let found = firstRange(of: part, in: bytes, from: from, to: end) else { return false }
            from = found
        }
        return from <= end
    }

    /// Where `part` ends, the first time it comes in `bytes` between these.
    private static func firstRange(of part: [UInt8], in bytes: [UInt8], from: Int, to end: Int) -> Int? {
        guard part.count <= end - from else { return nil }
        for start in from...(end - part.count) where bytes[start..<(start + part.count)].elementsEqual(part) { return start + part.count }
        return nil
    }

    /// Whether a text is one slot and nothing else: a value of any kind may fill it.
    static func isWholeSlot(_ text: String) -> Bool {
        let parts = literals(text)
        return parts.count == 2 && parts.allSatisfy(\.isEmpty)
    }

    /// The keys a step fills in.
    static func slotKeys(_ template: JSONValue) -> Set<String> {
        Set((template.objectValue ?? [:]).compactMap { key, value in value.stringValue.map(hasSlot) == true ? key : nil })
    }

    /// The keys that may hold a whole value of any kind, or be left out, when the step's own words are one slot and the field isn't one of the
    /// table's text fields (which stay words): a number, a list, a blank form field (D186).
    static func wholeKeys(_ template: JSONValue, tool: String) -> Set<String> {
        let open = ExtensionActionPolicy.fillable[tool] ?? []
        return Set((template.objectValue ?? [:]).compactMap { key, value in
            guard !open.contains(key), let text = value.stringValue, isWholeSlot(text) else { return nil }
            return key
        })
    }

    /// Whether a call is the step: the same keys (a whole-slot field may be left out), every written value equal, and words only where the plan left room.
    static func matches(_ input: JSONValue, template: JSONValue, fillable: Set<String>, whole: Set<String> = []) -> Bool {
        guard let given = input.objectValue, let written = template.objectValue,
              Set(given.keys).isSubset(of: Set(written.keys)), Set(written.keys).subtracting(given.keys).isSubset(of: whole) else { return false }
        return given.allSatisfy { key, call in
            guard let value = written[key] else { return false }
            if case .string(let t) = value, hasSlot(t) {
                guard fillable.contains(key) else { return false }
                if whole.contains(key) { return true }
                guard case .string(let s) = call else { return false }
                return fits(s, template: t)
            }
            return same(call, value)
        }
    }

    /// Why a step can't stand (it then asks each time, and the card says so), or nil. Tools of other extensions take no slots at all:
    /// Sidefolk can't tell what such a tool does with the words.
    static func standing(tool: any Tool, template: JSONValue) -> Bool {
        let name = tool.spec.name
        guard tool.spec.risk != .high, !ExtensionActionPolicy.neverStanding.contains(name), let fields = template.objectValue else { return false }
        guard tool.scope(for: template).text == nil else { return false }
        // What would be refused when it runs doesn't stand on a card that promised it.
        if name == CompanionJobTool.name, (fields["job"]?.stringValue?.count ?? 0) > CompanionJobTool.longest { return false }
        // What runs is what the card showed: nothing hidden in a written value, nothing past where the card stops.
        guard written(template).allSatisfy({ plain($0) && $0.count <= ExtensionPlanWords.valueLimit }),
              objectsFit(template) else { return false }
        let fillable = ExtensionActionPolicy.fillable[name] ?? []
        return fields.allSatisfy { key, value in
            !hasSlot(key) && slotless(value, unless: fillable.contains(key))
        }
    }

    /// What shows is all there is: nothing the card would strip, nothing invisible, nothing so long in bytes that characters hide it. What people's own writing needs stays:
    /// a joiner between letters (Persian, Hindi) or in an emoji, and an emoji's variation selector, each where it joins something, so none can carry anything by itself.
    static func plain(_ text: String) -> Bool {
        guard text.utf8.count <= ExtensionPlanWords.valueLimit * 4 else { return false }
        let scalars = Array(text.unicodeScalars)
        var rest = String.UnicodeScalarView()
        for (i, s) in scalars.enumerated() {
            let before = i > 0 ? scalars[i - 1] : nil, after = i + 1 < scalars.count ? scalars[i + 1] : nil
            func shows(_ o: Unicode.Scalar?) -> Bool { o.map { !$0.properties.isDefaultIgnorableCodePoint && !$0.properties.isWhitespace } ?? false }
            switch s.value {
            case 0xFE0F where shows(before): continue
            case 0x200C, 0x200D:
                // A joiner joins writing that has joiners (an emoji, Persian, Hindi): between two ASCII letters it would only change what a card shows.
                func beyondASCII(_ o: Unicode.Scalar?) -> Bool { o.map { !$0.isASCII } ?? false }
                if shows(after), shows(before) || before?.value == 0xFE0F, beyondASCII(after), beyondASCII(before) { continue }
                return false
            default: rest.append(s)
            }
        }
        let shown = String(rest)
        guard same(ExtensionText.clean(shown), shown), !shown.unicodeScalars.contains(where: { $0.properties.isDefaultIgnorableCodePoint }) else { return false }
        // What the card shows is the bytes: one plain space between words, none at the ends, no other kind of space, no tab or line break, and no pile of
        // marks past what the card keeps on a letter.
        var previous: Unicode.Scalar?, marks = 0
        for scalar in shown.unicodeScalars {
            if scalar.properties.isWhitespace || scalar.properties.generalCategory == .spaceSeparator {
                guard scalar == " ", let last = previous, last != " " else { return false }
            }
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark, .spacingMark:
                marks += 1
                if marks > 8 { return false }
            default: marks = 0
            }
            previous = scalar
        }
        return previous != " "
    }

    /// A value held in an object or a list shows as a whole, clipped: it has to fit whole.
    static func objectsFit(_ value: JSONValue) -> Bool {
        guard let fields = value.objectValue else { return true }
        return fields.values.allSatisfy { field in
            switch field {
            case .object, .array: field.jsonString.count <= ExtensionPlanWords.valueLimit
            default: true
            }
        }
    }

    /// Every string in a value, its keys too.
    static func written(_ value: JSONValue) -> [String] {
        switch value {
        case .string(let s): [s]
        case .array(let items): items.flatMap(written)
        case .object(let fields): fields.keys + fields.values.flatMap(written)
        default: []
        }
    }

    static func slotless(_ value: JSONValue, unless allowed: Bool) -> Bool {
        switch value {
        case .string(let s): return allowed || !hasSlot(s)
        case .array(let items): return items.allSatisfy { slotless($0, unless: false) }
        case .object(let fields): return fields.allSatisfy { !hasSlot($0.key) && slotless($0.value, unless: false) }
        default: return true
        }
    }

    /// Where a call goes, as its tool says: compared whole, so a slot can't move it.
    static func reach(_ scope: ToolScope) -> String {
        let reach: String = switch scope.reach {
        case nil: ""
        case let other?: "\(other)"
        }
        return [scope.url ?? "", scope.command ?? "", scope.commandFolder ?? "", reach, scope.readPaths.joined(separator: "\n"), scope.writePaths.joined(separator: "\n")]
            .joined(separator: "\u{1}")
    }

    /// Who offers `tool`, as a plan keeps it: nothing for Sidefolk's own tools.
    static func provider(_ tool: any Tool) -> String {
        extensionTool(tool)?.provider ?? ""
    }

    /// The extension's tool behind a tool as an extension is offered it.
    static func extensionTool(_ tool: any Tool) -> ExtensionTool? {
        ((tool as? ExternalFacade)?.base ?? tool) as? ExtensionTool
    }

    /// The tool as the person read it. The schema and its risk count: a tool that came to take more isn't what they allowed.
    static func definition(_ spec: ToolSpec) -> String {
        let can = spec.capabilities.map(\.rawValue).sorted().joined(separator: ",")
        return ExtensionHash.sha256(Data([spec.name, spec.title, spec.risk.rawValue, spec.mutates ? "1" : "0", can, spec.inputSchema.jsonString].joined(separator: "\u{1}").utf8))
    }
}

/// What the card says, from what the program sent and nothing else it chose: each step in Sidefolk's words, by the tool's own title, with
/// every written value and what is left to fill in. The title and the when are shown as the author's.
enum ExtensionPlanWords {
    static let valueLimit = 300

    static func line(tool: any Tool, template: JSONValue, from: [String: String] = [:], program: String? = nil, whole: Set<String> = []) -> String {
        let fields = template.objectValue ?? [:]
        // The field's own name, as the tool takes it: a schema's title is its author's, and could name one field after another.
        let values = fields.keys.sorted().compactMap { key -> String? in
            guard let value = fields[key], let said = words(value, from: from[key], whole: whole.contains(key)) else { return nil }
            return "\(ToolFormat.oneLine(ExtensionText.clean(key), 40)): \(said)"
        }
        var title = ToolFormat.oneLine(ExtensionText.clean(tool.spec.title), 80)
        // A plan holds for the extension that offered the tool, so the card says whose it is (as a call's own card does).
        if let ext = ExtensionPlanRules.extensionTool(tool) {
            let who = ToolFormat.oneLine(ExtensionText.clean(ext.extensionName), 40)
            if ext.sandboxed {
                title += " (\(who))"
            } else if let program {
                title += " (" + String(localized: "\(who), a server on this Mac, program \(program.prefix(8))…", comment: "A plan's card: a server the person added, and the start of its program's hash") + ")"
            } else {
                title += " (" + String(localized: "\(who), a server on this Mac; its program can't be checked", comment: "A plan's card: a server the person added") + ")"
            }
        }
        return values.isEmpty ? title : "\(title) · \(values.joined(separator: ", "))"
    }

    /// A written value as the card shows it: the quotes it is wrapped in can't be written inside it, so it can't pass for two fields.
    private static func quoted(_ text: String) -> String { "“" + unquoted(text) + "”" }

    private static func unquoted(_ text: String) -> String { text.replacingOccurrences(of: "“", with: "‘").replacingOccurrences(of: "”", with: "’") }

    private static func words(_ value: JSONValue, from: String? = nil, whole: Bool = false) -> String? {
        switch value {
        case .string(let s) where ExtensionPlanRules.hasSlot(s):
            // One line each, keeping the space a written part has next to a slot (a lone space between two slots too).
            let parts = ExtensionPlanRules.literals(s).map { part -> String in
                let said = unquoted(ToolFormat.oneLine(ExtensionText.clean(part), valueLimit))
                guard !said.isEmpty else { return part.isEmpty ? "" : " " }
                return (part.first?.isWhitespace == true ? " " : "") + said + (part.last?.isWhitespace == true ? " " : "")
            }
            var filled = from.map { String(localized: "from “\($0)”", comment: "A plan's card: where words filled in at run time come from, a step's own title") }
                ?? String(localized: "filled in when it runs", comment: "A plan's card: a value the extension writes at run time")
            if whole { filled += "; " + String(localized: "it may also be a list, a record, a number, or left out", comment: "A plan's card: a field filled with one value of any kind") }
            return "“" + parts.joined(separator: "[\(filled)]") + "”"
        case .string(let s): return quoted(ToolFormat.oneLine(ExtensionText.clean(s), valueLimit))
        // What clears a field is something the person reads too: a null or an empty list sets it to nothing.
        case .null: return String(localized: "nothing", comment: "A plan's card: a value written as null")
        case .array(let items):
            if items.isEmpty { return String(localized: "an empty list", comment: "A plan's card: a value written as an empty list") }
            // A list of lists keeps its shape: it shows as written.
            if items.contains(where: { $0.arrayValue != nil || $0.objectValue != nil }) { return ToolFormat.oneLine(ExtensionText.clean(value.jsonString), valueLimit) }
            return items.map { words($0) ?? String(localized: "nothing", comment: "A plan's card: a value written as null") }.joined(separator: ", ")
        case .object(let o):
            return o.isEmpty ? String(localized: "an empty record", comment: "A plan's card: a value written as an empty object") : ToolFormat.oneLine(ExtensionText.clean(value.jsonString), valueLimit)
        default: return ArgumentWords.words(value)
        }
    }
}

/// `extensions.plan`: the card that lets a plan stand. Its text is read in full, so Auto and Full access never answer it and "Always" is
/// never offered (`PermissionEngine.answeredByMode`). Only the host reaches it, for the extension's own plan, with the words it wrote.
struct ExtensionPlanTool: Tool {
    static let name = "extensions.plan"

    let extensionId: String
    let plan: String
    /// The extension's words for when it runs.
    var when = ""
    let body: String
    /// The host's answer for this person, when the plan needs no card (`PlanAnswer`).
    var answer: PlanAnswer?
    /// What the program says it is for ("run" or "turn_on"), which only chooses the title.
    var intent: String?

    private var title: String {
        switch intent {
        case "run"?: String(localized: "Run “\(plan)”", comment: "A tool, after “<an extension> wants to”: the person runs a flow, and reads what it will do")
        case "turn_on"?: String(localized: "Turn on “\(plan)”", comment: "A tool, after “<an extension> wants to”: the person turns a flow on, and reads what it will do")
        default: String(localized: "Run “\(plan)” without asking you", comment: "A tool, after “<an extension> wants to”: a plan the person reads, then it needs no more cards for exactly that")
        }
    }

    var spec: ToolSpec {
        ToolSpec(name: Self.name, title: title,
                 description: "Lets an extension run what the person read, without further cards.",
                 inputSchema: Schema.object(["extension": Schema.string("The extension's id."), "plan": Schema.string("The plan's id.")], required: ["extension", "plan"]),
                 risk: .medium, capabilities: [.extensions], category: .extensions, mutates: true, offeredToModel: false)
    }

    func summary(for input: JSONValue) -> String { when.isEmpty ? plan : when }
    func scope(for input: JSONValue) -> ToolScope { ToolScope(extensionId: extensionId, text: body, planAnswer: answer) }

    func refusal(for input: JSONValue, context: ToolContext) -> String? {
        if case .extension(let own) = context.caller, own == extensionId { return nil }
        return "Only an extension asks for its own plan."
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        ToolResult(text: "Allowed.", card: ResultCard(kind: .info, title: plan), untrusted: true)
    }
}

/// `extensions.plan_end`: the person ends a plan from Settings › Add-ons. Only their click; audited.
public struct ExtensionPlanEndTool: Tool {
    public static let name = "extensions.plan_end"

    let host: ExtensionHost

    public var spec: ToolSpec {
        ToolSpec(name: Self.name, title: String(localized: "End an extension's plan", comment: "A tool: Settings › Add-ons"),
                 description: "Ends a plan an extension runs without asking.",
                 inputSchema: Schema.object(["extension": Schema.string("The extension's id."), "plan": Schema.string("The plan's id.")], required: ["extension", "plan"]),
                 risk: .low, capabilities: [.extensions], category: .extensions, mutates: true, offeredToModel: false)
    }

    public func summary(for input: JSONValue) -> String { String(localized: "End “\(input.string("plan") ?? "")”", comment: "History: the person ended an extension's plan") }
    public func scope(for input: JSONValue) -> ToolScope { ToolScope(extensionId: input.string("extension")) }

    public func refusal(for input: JSONValue, context: ToolContext) -> String? {
        if case .user = context.caller { return nil }
        return "This is for the person's own click."
    }

    public func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let id = input.string("extension"), let plan = input.string("plan") else { throw ToolError.invalidInput(String(localized: "There's no such plan.")) }
        await host.endPlan(extensionId: id, plan: plan)
        return ToolResult(text: "Ended.", untrusted: true)
    }
}
