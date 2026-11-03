import Foundation
import Synchronization

/// What an extension may do without a card, because the person read it (D110, SECURITY T43): its tools and their exact values, and
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
    static let maxSteps = 32
    static let ttls = 60...3600
    static let perDays = 1...1000
    static let defaultPerDay = 200
    /// How far past the person's click, command or clean request an extension may still ask for a plan: a card is never started by
    /// a timer, a page's words or a model steered by what it read (T3).
    static let personWindow: TimeInterval = 30

    private static let slot = try! NSRegularExpression(pattern: #"\{\{[A-Za-z0-9_.-]{1,40}\}\}"#)

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
        for start in from...(end - part.count) where Array(bytes[start..<(start + part.count)]) == part { return start + part.count }
        return nil
    }

    /// Whether a call is the step: the same keys, every written value equal, and words only where the plan left room.
    static func matches(_ input: JSONValue, template: JSONValue, fillable: Set<String>) -> Bool {
        guard let given = input.objectValue, let written = template.objectValue, Set(given.keys) == Set(written.keys) else { return false }
        return written.allSatisfy { key, value in
            guard let call = given[key] else { return false }
            if case .string(let t) = value, hasSlot(t) {
                guard fillable.contains(key), case .string(let s) = call else { return false }
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
        // What runs is what the card showed: nothing hidden in a written value, nothing past where the card stops.
        guard written(template).allSatisfy({ same(ExtensionText.clean($0), $0) && $0.count <= ExtensionPlanWords.valueLimit }) else { return false }
        let fillable = ExtensionActionPolicy.fillable[name] ?? []
        return fields.allSatisfy { key, value in
            !hasSlot(key) && slotless(value, unless: fillable.contains(key))
        }
    }

    /// Every string in a value, its keys too.
    private static func written(_ value: JSONValue) -> [String] {
        switch value {
        case .string(let s): [s]
        case .array(let items): items.flatMap(written)
        case .object(let fields): fields.keys + fields.values.flatMap(written)
        default: []
        }
    }

    private static func slotless(_ value: JSONValue, unless allowed: Bool) -> Bool {
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

    static func line(tool: any Tool, template: JSONValue) -> String {
        let fields = template.objectValue ?? [:]
        let properties = tool.spec.inputSchema["properties"]?.objectValue ?? [:]
        let values = fields.keys.sorted().compactMap { key -> String? in
            guard let value = fields[key], let said = words(value) else { return nil }
            return "\(ArgumentWords.label(key, properties[key])): \(said)"
        }
        let title = ToolFormat.oneLine(ExtensionText.clean(tool.spec.title), 80)
        return values.isEmpty ? title : "\(title) · \(values.joined(separator: ", "))"
    }

    private static func words(_ value: JSONValue) -> String? {
        switch value {
        case .string(let s) where ExtensionPlanRules.hasSlot(s):
            let parts = ExtensionPlanRules.literals(s).map { ToolFormat.oneLine(ExtensionText.clean($0), valueLimit) }
            let filled = String(localized: "filled in when it runs", comment: "A plan's card: a value the extension writes at run time")
            return "“\(parts.joined(separator: "[\(filled)]"))”"
        case .string(let s): return "“\(ToolFormat.oneLine(ExtensionText.clean(s), valueLimit))”"
        case .array(let items):
            let said = items.compactMap(words)
            return said.isEmpty ? nil : said.joined(separator: ", ")
        case .object(let o): return o.isEmpty ? nil : ToolFormat.oneLine(ExtensionText.clean(value.jsonString), valueLimit)
        default: return ArgumentWords.words(value)
        }
    }

    /// The whole card. Plans the person allowed before under the same id say what is new first.
    static func body(name: String, lines: [(text: String, standing: Bool, new: Bool)], when: String, perDay: Int, ttl: Int?, revised: Bool) -> String {
        var out: [String] = []
        func bullets(_ list: [(text: String, standing: Bool, new: Bool)]) -> String { list.map { "• \($0.text)" }.joined(separator: "\n") }
        let standing = lines.filter(\.standing)
        if revised {
            let new = standing.filter(\.new), old = standing.filter { !$0.new }
            if !new.isEmpty { out.append(String(localized: "New, without asking you:", comment: "A plan's card") + "\n" + bullets(new)) }
            if !old.isEmpty { out.append(String(localized: "As before, without asking you:", comment: "A plan's card") + "\n" + bullets(old)) }
        } else if !standing.isEmpty {
            out.append(String(localized: "Without asking you, it will:", comment: "A plan's card") + "\n" + bullets(standing))
        }
        let asking = lines.filter { !$0.standing }
        if !asking.isEmpty { out.append(String(localized: "It will still ask you each time:", comment: "A plan's card") + "\n" + bullets(asking)) }
        out.append(String(localized: "What these return goes to \(name), which can't reach the internet by itself.", comment: "A plan's card; the extension's name"))
        if let ttl {
            let minutes = max(1, ttl / 60)
            out.append(String(localized: "This ends by itself in \(minutes) minutes.", comment: "A plan's card"))
        } else {
            out.append(String(localized: "At most \(perDay) actions a day. You can end this in Settings › Add-ons.", comment: "A plan's card"))
        }
        return out.joined(separator: "\n\n")
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

    var spec: ToolSpec {
        ToolSpec(name: Self.name, title: String(localized: "Run \(plan) without asking you", comment: "A tool, after “<an extension> wants to”: a plan the person reads, then it needs no more cards for exactly that"),
                 description: "Lets an extension run what the person read, without further cards.",
                 inputSchema: Schema.object(["extension": Schema.string("The extension's id."), "plan": Schema.string("The plan's id.")], required: ["extension", "plan"]),
                 risk: .medium, capabilities: [.extensions], category: .extensions, mutates: true, offeredToModel: false)
    }

    func summary(for input: JSONValue) -> String { when.isEmpty ? plan : when }
    func scope(for input: JSONValue) -> ToolScope { ToolScope(extensionId: extensionId, text: body) }

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
