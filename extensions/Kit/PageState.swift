import Foundation

/// A change to a page's state (D105): `set` is merged into it (`NSNull()` takes a key out) and the page is read again. No tool runs and
/// History hears nothing, so it's for what is on screen: where the page is, a draft, a search. `push` lets Back return to the state before.
public struct Go {
    public var set: [String: Any]
    public var push: Bool
    public var back: Bool

    public init(set: [String: Any] = [:], push: Bool = false, back: Bool = false) {
        self.set = set
        self.push = push
        self.back = back
    }

    public static var backward: Go { Go(back: true) }

    var json: [String: Any] {
        var out: [String: Any] = ["set": set]
        if push { out["push"] = true }
        if back { out["back"] = true }
        return out
    }
}

/// What a button or a scene's area may do other than run a tool (D105).
public enum PageAct {
    /// Changes the page's state.
    case go(Go)
    /// Puts words the person can see on the clipboard, on their click. Needs no `clipboard` permission.
    case copy(String)
    /// The system's open panel, then `tool` with the chosen file in `param`, which the manifest declares in that tool's `paths`.
    case file(tool: String, param: String, types: [String], input: [String: Any] = [:])
    /// Sidefolk asks the person, in its own words, to let you have this: `place` or `schedule`.
    case allow(String)
    /// Opens `notifications` (the Mac's), `attention` or `place` (Sidefolk's).
    case settings(String)
    /// Opens one of your own palettes, as its shortcut does. The button shows that shortcut.
    case palette(String)
    /// Reads the page again now.
    case refresh

    func fill(_ out: inout [String: Any]) {
        switch self {
        case .go(let go): out["go"] = go.json
        case .copy(let words): out["copy"] = words
        case .file(let tool, let param, let types, let input): out["file"] = ["tool": tool, "param": param, "types": types, "input": input] as [String: Any]
        case .allow(let what): out["allow"] = what
        case .settings(let pane): out["settings"] = pane
        case .palette(let name): out["palette"] = name
        case .refresh: out["refresh"] = true
        }
    }
}

/// `#RRGGBB` for each appearance.
public struct PagePair {
    public var light: String
    public var dark: String

    public init(light: String, dark: String) {
        self.light = light
        self.dark = dark
    }

    var json: [String: Any] { ["light": light, "dark": dark] }
}

/// A page's own ground and cards (D108). Always a pair: its text and controls stay the theme's, which read light on dark and dark on light.
public struct PageDress {
    public var ground: PagePair
    public var card: PagePair?
    public var line: PagePair?
    /// Filled buttons and switches on the page. Too light to hold white words, it holds near-black ones.
    public var accent: PagePair?
    /// What's selected on the page, and the soft tint under it.
    public var selected: PagePair?
    /// Soft wells on its cards: a neutral note, a bar's track.
    public var well: PagePair?
    public var picture: Picture?
    /// The picture repeats rather than filling the page.
    public var tile: Bool

    public init(ground: PagePair, card: PagePair? = nil, line: PagePair? = nil, accent: PagePair? = nil, selected: PagePair? = nil, well: PagePair? = nil, picture: Picture? = nil, tile: Bool = false) {
        self.accent = accent
        self.selected = selected
        self.well = well
        self.ground = ground
        self.card = card
        self.line = line
        self.picture = picture
        self.tile = tile
    }

    var json: [String: Any] {
        var out: [String: Any] = ["ground": ground.json]
        if let card { out["card"] = card.json }
        if let line { out["line"] = line.json }
        if let accent { out["accent"] = accent.json }
        if let selected { out["selected"] = selected.json }
        if let well { out["well"] = well.json }
        if let picture {
            var p = picture.json
            if tile { p["tile"] = true }
            out["picture"] = p
        }
        return out
    }
}

extension Arguments {
    /// What the page was told to remember (D105); empty when it wasn't told anything.
    public var pageState: Arguments { Arguments(values["state"] as? [String: Any] ?? [:]) }
    /// The width of the page's column in points, when Sidefolk knows it yet (D105).
    public var pageWidth: Double? { (values["width"] as? NSNumber)?.doubleValue }
    /// Nobody is looking: Sidefolk reads the page once a minute for Today and the sidebar. A page without charts may answer with its summary alone.
    public var pageIsBackground: Bool { values["background"] as? Bool ?? false }
}
