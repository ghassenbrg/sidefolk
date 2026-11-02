import Foundation

/// What a Sidefolk extension's tool may ask for with its reply (`sidefolk`, beside `content`, D100): its own surface opened or
/// put away, its own page shown, or the AI's answer held for a moment. This is how a menu item, a command, a page's button or
/// a tool the AI called starts a surface. Only ever in answer to a call someone made through Guard, and only for what its
/// signed manifest declares: a program can't push anything by itself (T40).
public struct ExtensionToolAsks: Sendable, Hashable {
    public var openSurface: String?
    public var arguments: [String: JSONValue] = [:]
    /// Which of its surfaces goes away, kept to come back to. Empty: whichever of its are open.
    public var closeSurface: String?
    public var openPage: PageMove?
    /// The AI's words wait this long, so they don't give away what an animation is still showing.
    public var holdAnswer: TimeInterval?
    /// What History says this call did, in place of the tool's title and arguments ("Heads!"). Believed only for packs Sidefolk signed, like `summary` (D98).
    public var row: String?

    /// The longest an answer waits.
    public static let longestHold: TimeInterval = 5

    /// Anything naming what the manifest doesn't declare is left out.
    init?(_ json: JSONValue?, manifest: ExtensionManifest) {
        guard let json, json.objectValue != nil else { return nil }
        if let open = json["open_surface"] {
            let name = open.stringValue ?? open["surface"]?.stringValue
            if let name, manifest.surfaces[name] != nil {
                openSurface = name
                arguments = SurfacesOpenTool.arguments(open["arguments"])
            }
        }
        if let close = json["close_surface"] {
            if close.boolValue == true { closeSurface = "" } else if let name = close.stringValue, manifest.surfaces[name] != nil { closeSurface = name }
        }
        if let move = PageMove.parse(json["open_page"]), manifest.pages[move.page] != nil { openPage = move }
        if let ms = json["hold_answer_ms"]?.doubleValue, ms.isFinite, ms > 0 { holdAnswer = min(ms / 1000, Self.longestHold) }
        if let said = json["row"]?.stringValue { row = ExtensionText.line(said, characters: 120) }
        guard openSurface != nil || closeSurface != nil || openPage != nil || holdAnswer != nil || row != nil else { return nil }
    }
}

/// When what a tool said may be shown or said aloud, whichever road it came by: an extension's animation may still be building up to the result, and nothing
/// gives that away early (D100, D101). A read-only tool's words reach the person through the AI's, so this reads every finished tool, not only those shown as cards.
public struct AnswerHold: Sendable {
    private var until: Date?

    public init() {}

    public mutating func note(_ card: ResultCard?, now: Date = Date()) {
        guard let hold = card?.holdAnswer else { return }
        let end = now.addingTimeInterval(hold)
        if until.map({ end > $0 }) ?? true { until = end }
    }

    /// How long is left to wait.
    public func remaining(now: Date = Date()) -> TimeInterval { until.map { max(0, $0.timeIntervalSince(now)) } ?? 0 }
}

extension ExtensionHost {
    /// Does what a tool's reply asked. The person's own click or words take the keyboard; the AI's call opens only a surface
    /// marked `ai`, and waits for a click (D75). A routine, another agent or the extension's own background work opens nothing.
    func performAsks(_ id: String, _ asks: ExtensionToolAsks, caller: Caller) async {
        let person: Bool
        switch caller {
        case .user: person = true
        case .command(let own): person = own == id
        case .agent: person = false
        case .routine, .external, .extension: return
        }
        if let name = asks.openSurface, let run = configuration.runTool, let surface = runtimes[id]?.manifest?.surfaces[name], person || surface.ai == true {
            _ = await run(SurfacesOpenTool.name, ["surface": .string("\(id)/\(name)"), "arguments": .object(asks.arguments), "focus": .bool(person)], .extension(id: id), 10)
        }
        if let close = asks.closeSurface { events.publish(.surfaceAway(extensionId: id, surface: close.isEmpty ? nil : close)) }
        if let move = asks.openPage, person {
            let page = "\(id)/\(move.page)"
            if let go = move.go { pageMoves[page, default: []].append(go) }
            events.publish(.extensionPage(id: page))
        }
    }
}
