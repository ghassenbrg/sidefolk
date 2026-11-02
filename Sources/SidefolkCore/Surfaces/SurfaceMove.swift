import Foundation

/// What the person did on a surface, as Sidefolk makes it from a click, a key or a clock on a thing the scene offered
/// (D99). An extension hears nothing else: no pointer, no keys it didn't name, nothing about the companion or the person.
public enum SurfaceMove: Sendable, Hashable {
    /// `ms`: from the area's `timed_from_ms` to the press, below 0 before it.
    case click(area: String, value: String?, ms: Int?)
    case dragGrid(area: String, value: String?, fromRow: Int, fromColumn: Int, toRow: Int, toColumn: Int)
    case dragFree(area: String, value: String?, fromX: Double, fromY: Double, toX: Double, toY: Double)
    case key(id: String, character: String?, ms: Int?)
    case entry(id: String, text: String)
    case timer(String)
    /// A scene's `after_ms` passed.
    case next
    /// The frame's Back.
    case back

    public var json: JSONValue {
        func click(_ area: String, _ value: String?, _ ms: Int?) -> JSONValue {
            var out: [String: JSONValue] = ["area": .string(area)]
            if let value { out["value"] = .string(value) }
            if let ms { out["ms"] = .number(Double(ms)) }
            return .object(out)
        }
        switch self {
        case .click(let area, let value, let ms): return ["click": click(area, value, ms)]
        case .dragGrid(let area, let value, let r, let c, let r2, let c2):
            var out = click(area, value, nil).objectValue ?? [:]
            out["mode"] = "cells"
            out["from"] = [.number(Double(r)), .number(Double(c))]
            out["to"] = [.number(Double(r2)), .number(Double(c2))]
            return ["drag": .object(out)]
        case .dragFree(let area, let value, let x, let y, let x2, let y2):
            var out = click(area, value, nil).objectValue ?? [:]
            out["mode"] = "points"
            out["from"] = [.number(x.rounded()), .number(y.rounded())]
            out["to"] = [.number(x2.rounded()), .number(y2.rounded())]
            return ["drag": .object(out)]
        case .key(let id, let character, let ms):
            var out: [String: JSONValue] = ["id": .string(id)]
            if let character { out["char"] = .string(character) }
            if let ms { out["ms"] = .number(Double(ms)) }
            return ["key": .object(out)]
        case .entry(let id, let text): return ["entry": ["id": .string(id), "text": .string(text)]]
        case .timer(let id): return ["timer": .string(id)]
        case .next: return ["next": true]
        case .back: return ["back": true]
        }
    }

    /// What was typed in a field, as the extension may hear it: cleaned, one line, not empty.
    public static func typed(_ raw: String) -> String? {
        let text = ExtensionText.clean(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text.contains(where: \.isNewline) ? nil : text
    }

    /// Whether the scene on screen offered this: an extension only hears what its scene asked for. `inputOpen`: its
    /// animations no longer hold moves; a clock's, the frame's and anything marked `always` go through regardless.
    public func offered(by scene: SurfaceScene, inputOpen: Bool = true) -> Bool {
        switch self {
        case .click(let area, let value, _):
            return scene.areas.contains { $0.id == area && $0.value == value && !$0.disabled && (inputOpen || $0.always) }
        case .dragGrid(let area, let value, let r, let c, let r2, let c2):
            guard inputOpen else { return false }
            return scene.areas.contains { a in
                guard a.id == area, a.value == value, !a.disabled, case .grid(let rows, let columns)? = a.drag?.mode else { return false }
                return (0..<rows).contains(r) && (0..<rows).contains(r2) && (0..<columns).contains(c) && (0..<columns).contains(c2)
            }
        case .dragFree(let area, let value, let x, let y, let x2, let y2):
            guard inputOpen, [x, y, x2, y2].allSatisfy(\.isFinite) else { return false }
            let inside = (-1...scene.size.width + 1).contains(x) && (-1...scene.size.width + 1).contains(x2)
                && (-1...scene.size.height + 1).contains(y) && (-1...scene.size.height + 1).contains(y2)
            return inside && scene.areas.contains { $0.id == area && $0.value == value && !$0.disabled && $0.drag?.mode == .free }
        case .key(let id, let character, _):
            return scene.keys.contains { k in
                guard k.id == id, k.area == nil, inputOpen || k.always else { return false }
                return switch k.match {
                case .character(let c): character == nil || character == c
                case .named: character == nil
                case .anyLetter: character?.first?.isLetter == true
                case .anyDigit: character?.first?.isNumber == true
                }
            }
        case .entry(let id, let text):
            guard inputOpen else { return false }
            return scene.entries.contains { $0.id == id && !$0.locked && text.count <= $0.max && !text.isEmpty }
        case .timer(let id): return scene.timers.contains { $0.id == id }
        case .next: return scene.after != nil
        case .back: return scene.back
        }
    }
}

/// Why a surface ended, as `sidefolk/surface.close` says it.
public enum SurfaceCloseReason: String, Sendable {
    /// The person closed it (✕, Esc, or another panel taking its place).
    case closed
    /// Left put away past the time it is kept.
    case timeout
    /// The scene asked to close, or ended.
    case finished
    /// The extension was turned off or removed.
    case removed
}
