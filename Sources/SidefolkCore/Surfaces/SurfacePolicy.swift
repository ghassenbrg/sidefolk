import CoreGraphics
import Foundation

/// The rules a surface lives by that aren't drawing (D99), pure so they are tested without a window: where it may stand,
/// how it fits a screen, who hears a key. The panel controller only asks these.
public enum SurfacePolicy {
    /// The frame Sidefolk draws above the canvas: the extension's icon and name, its title, Back, the speaker and ✕.
    public static let headerHeight: CGFloat = 44
    /// The name chip under an overlay.
    public static let chipHeight: CGFloat = 30
    /// An overlay left alone goes after this: nothing of an extension's stays on the desktop by itself.
    public static let overlayLifetime: TimeInterval = 60
    /// A surface put away is kept this long.
    public static let keptFor: TimeInterval = 600
    /// Two Escs this close always close the surface, whatever the scene does with Esc.
    public static let escapeTwice: TimeInterval = 1

    /// The canvas actually drawn, scaled down if the screen has less room than it asked for: scale 1 unless it must.
    public static func fit(canvas: CGSize, presentation: SurfaceInfo.Presentation, screen: CGRect) -> (size: CGSize, scale: CGFloat) {
        let frame = presentation == .panel ? headerHeight : chipHeight
        let room = CGSize(width: screen.width - 16, height: screen.height - 16 - frame)
        let scale = min(1, room.width / max(canvas.width, 1), room.height / max(canvas.height, 1))
        return (CGSize(width: (canvas.width * scale).rounded(), height: (canvas.height * scale).rounded()), max(scale, 0.25))
    }

    /// Where a surface stands: beside the companion on the side with more room (a panel) or above it (an overlay), inside
    /// the screen, and never over a card. Sidefolk's own cards (approvals among them) stay where they are: the surface
    /// goes to the side, and if no side has room, it goes below them in the window order and takes no input.
    public static func place(size: CGSize, presentation: SurfaceInfo.Presentation, beside anchor: CGRect, screen: CGRect,
                             avoiding cards: [CGRect], gap: CGFloat = 10) -> CGRect {
        var candidates: [CGPoint] = []
        let roomLeft = anchor.minX - screen.minX, roomRight = screen.maxX - anchor.maxX
        let left = CGPoint(x: anchor.minX - gap - size.width, y: anchor.minY + anchor.height * 0.35)
        let right = CGPoint(x: anchor.maxX + gap, y: anchor.minY + anchor.height * 0.35)
        let above = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        let below = CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height)
        switch presentation {
        case .panel: candidates = roomLeft >= roomRight ? [left, right, above, below] : [right, left, above, below]
        case .overlay: candidates = [above, roomLeft >= roomRight ? left : right, roomLeft >= roomRight ? right : left, below]
        }
        // A card in the way: beside it, above it or below it, at the same height.
        for card in cards {
            let first = candidates[0]
            candidates += [CGPoint(x: card.minX - gap - size.width, y: first.y), CGPoint(x: card.maxX + gap, y: first.y),
                           CGPoint(x: first.x, y: card.maxY + gap), CGPoint(x: first.x, y: card.minY - gap - size.height)]
        }
        func inside(_ p: CGPoint) -> CGRect {
            CGRect(x: min(max(p.x, screen.minX + 8), screen.maxX - size.width - 8), y: min(max(p.y, screen.minY + 8), screen.maxY - size.height - 8),
                   width: size.width, height: size.height)
        }
        for point in candidates {
            let rect = inside(point)
            if !cards.contains(where: { $0.intersects(rect) }), !rect.intersects(anchor) { return rect }
        }
        for point in candidates {
            let rect = inside(point)
            if !cards.contains(where: { $0.intersects(rect) }) { return rect }
        }
        return inside(candidates[0])
    }

    /// Where an overlay on screen goes when its scene changes size: it stays where it is, grown from the edge nearest the companion, rather than being placed anew. A coin
    /// that lands shouldn't jump across the screen, whatever else has come or gone since it was placed. Nil when that no longer fits: then it is placed as usual.
    public static func resized(_ current: CGRect, to size: CGSize, beside anchor: CGRect, screen: CGRect, avoiding cards: [CGRect]) -> CGRect? {
        let y = current.midY >= anchor.midY ? current.minY : current.maxY - size.height
        let rect = CGRect(x: current.midX - size.width / 2, y: y, width: size.width, height: size.height)
        guard screen.insetBy(dx: 8, dy: 8).contains(rect), !cards.contains(where: { $0.intersects(rect) }) else { return nil }
        return rect
    }

    /// Where a scene's text field may stand: inside the canvas, or nowhere. Only the layers clip themselves, and a field is a real view
    /// that could otherwise draw over the frame that says whose this is (T40).
    public static func fieldFrame(_ rect: CGRect, canvas: CGSize) -> CGRect? {
        let inside = rect.intersection(CGRect(origin: .zero, size: canvas))
        return inside.isNull || inside.width < 1 || inside.height < 1 ? nil : inside
    }

    /// Whether a surface standing at `frame` may take input now. While an approval is waiting, nothing of an extension's
    /// takes a click or a key: it can't be used to catch a press meant for the card.
    public static func takesInput(approvalWaiting: Bool) -> Bool { !approvalWaiting }

    /// What a key does on a surface that has the keyboard. Command keys are the app's and the system's, and an extension
    /// can never reach them; ⌘[ and ⌘W are the frame's.
    public enum KeyRoute: Equatable, Sendable {
        case scene
        case back
        case close
        case system
    }

    public static func route(_ key: String, command: Bool, scene: SurfaceScene?, lastEscape: Date?, now: Date) -> KeyRoute {
        if command {
            if key == "[" { return scene?.back == true ? .back : .system }
            if key == "w" { return .close }
            return .system
        }
        if key == "escape" {
            let bound = scene?.keys.contains { $0.match == .named(.escape) } ?? false
            guard bound else { return .close }
            // The scene may use Esc (to let go of something being dragged), but pressed twice it always closes: an
            // extension can't hold the person in.
            if let lastEscape, now.timeIntervalSince(lastEscape) < escapeTwice { return .close }
            return .scene
        }
        return .scene
    }

    /// How see-through an area that sends a field's words is drawn: dim while there is nothing to send, as it takes no press then.
    public static func submitOpacity(_ node: SceneNode, typed: String) -> Double {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? node.opacity * 0.5 : node.opacity
    }

    /// The scene's key that answers this press: an exact one before a class of keys.
    public static func match(_ key: String, seat: String?, in scene: SurfaceScene) -> SceneKey? {
        if let seat, let k = scene.keys.first(where: { $0.bySeat && $0.match == .character(seat) }) { return k }
        if let named = SceneKey.Named(rawValue: key), let k = scene.keys.first(where: { $0.match == .named(named) }) { return k }
        guard SceneKey.Named(rawValue: key) == nil else { return nil }
        if let k = scene.keys.first(where: { !$0.bySeat && $0.match == .character(key) }) { return k }
        guard let c = key.first else { return nil }
        if c.isNumber, let k = scene.keys.first(where: { $0.match == .anyDigit }) { return k }
        if c.isLetter, let k = scene.keys.first(where: { $0.match == .anyLetter }) { return k }
        return nil
    }
}
