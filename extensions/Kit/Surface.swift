import Foundation

/// A panel or overlay Sidefolk frames beside the companion for this extension (docs/EXTENSIONS.md › Surfaces, D99). The
/// extension keeps its own state and answers with a `Scene`; Sidefolk draws it natively, keeps the time, plays the
/// animations and sends back only moves the scene offered. Moves are not tool calls: they can only change the extension.
///
/// ```swift
/// ext.surface("coin", open: { request in
///     SurfaceReply(session: UUID().uuidString, scene: Scene(width: 200, height: 200) { Node.image("coin.png").size(120, 120).at(40, 40) })
/// }, move: { request in
///     Scene(width: 200, height: 200) { Node.text("Done") }.closing()
/// })
/// ```
public struct SurfaceRequest {
    public var session: String
    /// The person's language, as Sidefolk speaks it (`en`, `fr`, `pt-BR`, `zh-Hans`, `ar`).
    public var language: String
    /// What opened it passed along; nothing about the person, and never the companion's picture or name.
    public var arguments: Arguments
    public var move: SurfaceMove?
    /// Why it closed, in `close`: `closed`, `timeout`, `finished`.
    public var reason: String?

    init(_ params: [String: Any]) {
        session = params["session"] as? String ?? ""
        language = params["language"] as? String ?? "en"
        arguments = Arguments(params["arguments"] as? [String: Any] ?? [:])
        move = (params["move"] as? [String: Any]).map(SurfaceMove.init)
        reason = params["reason"] as? String
    }
}

/// What a tool answers: its text for whoever called it, and what it asks of Sidefolk. Only ever for your own surfaces and pages as the
/// manifest declares them; a person's click or words take the keyboard, the AI opens only a surface marked `ai`, and waits for a click.
public struct ToolReply {
    public var text: String
    var asks: [String: Any] = [:]

    public init(_ text: String) { self.text = text }

    public func opening(surface: String, arguments: [String: Any] = [:]) -> ToolReply {
        var copy = self
        copy.asks["open_surface"] = ["surface": surface, "arguments": arguments] as [String: Any]
        return copy
    }

    /// Puts it away, kept to come back to. No name: whichever of yours are open.
    public func closingSurface(_ surface: String? = nil) -> ToolReply {
        var copy = self
        copy.asks["close_surface"] = surface.map { $0 as Any } ?? true
        return copy
    }

    public func opening(page: String) -> ToolReply {
        var copy = self
        copy.asks["open_page"] = page
        return copy
    }

    /// The AI's words about this wait so long, at most 5 s, so they don't give away what an animation is still showing.
    public func holdingAnswer(ms: Int) -> ToolReply {
        var copy = self
        copy.asks["hold_answer_ms"] = ms
        return copy
    }
}

/// What opening a surface returns: the session Sidefolk sends back with every move (up to 64 letters, digits, `_`, `-`).
public struct SurfaceReply {
    public var session: String
    public var scene: Scene

    public init(session: String, scene: Scene) {
        self.session = session
        self.scene = scene
    }
}

/// The person's move, as Sidefolk sends it: only ever one the scene on screen offered.
public enum SurfaceMove: Equatable {
    /// `value` is the area's own; `ms` is from its `timedFrom` to the press, below 0 before it.
    case click(area: String, value: String?, ms: Int?)
    case dragCells(area: String, value: String?, from: [Int], to: [Int])
    case dragPoints(area: String, value: String?, from: [Double], to: [Double])
    /// A key the scene took for itself (one tied to an area comes as its `click`).
    case key(id: String, character: String?, ms: Int?)
    case entry(id: String, text: String)
    case timer(String)
    /// The scene's `afterMs` passed: answer with the next one.
    case next
    /// The frame's Back.
    case back
    case unknown

    public init(_ json: [String: Any]) {
        if let c = json["click"] as? [String: Any], let area = c["area"] as? String {
            self = .click(area: area, value: c["value"] as? String, ms: c["ms"] as? Int)
        } else if let d = json["drag"] as? [String: Any], let area = d["area"] as? String {
            if d["mode"] as? String == "cells", let f = d["from"] as? [Int], let t = d["to"] as? [Int], f.count == 2, t.count == 2 {
                self = .dragCells(area: area, value: d["value"] as? String, from: f, to: t)
            } else if let f = d["from"] as? [Double], let t = d["to"] as? [Double], f.count == 2, t.count == 2 {
                self = .dragPoints(area: area, value: d["value"] as? String, from: f, to: t)
            } else {
                self = .unknown
            }
        } else if let k = json["key"] as? [String: Any], let id = k["id"] as? String {
            self = .key(id: id, character: k["char"] as? String, ms: k["ms"] as? Int)
        } else if let e = json["entry"] as? [String: Any], let id = e["id"] as? String, let text = e["text"] as? String {
            self = .entry(id: id, text: text)
        } else if let t = json["timer"] as? String {
            self = .timer(t)
        } else if json["next"] as? Bool == true {
            self = .next
        } else if json["back"] as? Bool == true {
            self = .back
        } else {
            self = .unknown
        }
    }
}
