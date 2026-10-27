import Foundation

/// Something the person, or Sidefolk's AI, asks the companion to do for fun (D44): a trick on the desktop, or a
/// small game played with it. Core names it and carries it on the event bus (`AppEvent.companion`); the app plays it.
public enum CompanionAct: String, CaseIterable, Sendable, Codable {
    case dance, wave, bow, flip, hop, cheer, nod, giggle
    /// A trick of its choosing ("do a trick", "make me laugh").
    case trick
    /// It hops about near its spot for 20 seconds; each boop catches it.
    case catchMe = "catch_me"
    /// One calm minute of breathing in and out with it.
    case breathe

    public var isGame: Bool { self == .catchMe || self == .breathe }

    /// What the hint and the card call it, in the app's language.
    public var title: String {
        switch self {
        case .dance: String(localized: "A little dance", comment: "The companion dances on the desktop")
        case .wave: String(localized: "A wave", comment: "The companion waves hello")
        case .bow: String(localized: "A bow", comment: "The companion bows")
        case .flip: String(localized: "A flip", comment: "The companion does a somersault")
        case .hop: String(localized: "A hop", comment: "The companion hops")
        case .cheer: String(localized: "A cheer", comment: "The companion cheers, arms up")
        case .nod: String(localized: "A nod", comment: "The companion nods yes")
        case .giggle: String(localized: "A giggle", comment: "The companion giggles")
        case .trick: String(localized: "A trick", comment: "The companion does a trick of its choosing")
        case .catchMe: String(localized: "Catch me!", comment: "A game: the companion hops about and the person boops it")
        case .breathe: String(localized: "Breathe with me", comment: "A one-minute breathing exercise with the companion")
        }
    }
}

/// `companion.play`: the companion does a trick or starts a game. Nothing outside the app changes, so it needs no
/// approval; it is a tool so the local parser and the AI reach it the same way (every action through the executor).
struct CompanionPlayTool: Tool {
    let events: EventBus

    let spec = ToolSpec(
        name: "companion.play", title: String(localized: "Play with the companion"),
        description: """
            Makes your companion do something on the desktop: a trick (dance, wave, bow, flip, hop, cheer, nod, giggle, \
            or trick for one of its choosing), or a game the user plays with it (catch_me: for 20 seconds it hops about \
            and the user boops it; breathe: a calm one-minute breathing exercise). Use it when the user asks you to do \
            something playful, to celebrate with them (cheer) when they win or get an answer right, or when they want a break.
            """,
        inputSchema: Schema.object(["act": Schema.string("What to do.", enum: CompanionAct.allCases.map(\.rawValue))], required: ["act"]),
        risk: .low, capabilities: [.system], category: .system, mutates: false)

    func summary(for input: JSONValue) -> String {
        input.string("act").flatMap(CompanionAct.init(rawValue:))?.title ?? String(localized: "Play with the companion")
    }

    func scope(for input: JSONValue) -> ToolScope { ToolScope() }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let act = input.string("act").flatMap(CompanionAct.init(rawValue:)) else {
            throw ToolError.invalidInput(String(localized: "“act” must be one of \(CompanionAct.allCases.map(\.rawValue).joined(separator: ", ")).", comment: "A list of names"))
        }
        events.publish(.companion(act))
        let text = switch act {
        case .catchMe: "Started catch-me: for 20 seconds the companion hops about and the user boops it. The score shows on the desktop."
        case .breathe: "Started a one-minute breathing exercise; the steps show above the companion."
        default: "The companion did it on the desktop (\(act.rawValue))."
        }
        return ToolResult(text: text, card: ResultCard(kind: .info, title: act.title))
    }
}
