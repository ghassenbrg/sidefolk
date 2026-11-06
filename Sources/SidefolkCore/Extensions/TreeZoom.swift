import CoreGraphics

/// How a tree board zooms and scrolls (D233): only the view moves, never the tree, and nothing is told to the extension.
public enum TreeZoom {
    /// From a quarter of its size to twice it.
    public static let range: ClosedRange<CGFloat> = 0.25...2
    /// What a key or a button press changes it by.
    public static let step: CGFloat = 0.1

    public static func clamped(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return 1 }
        return min(range.upperBound, max(range.lowerBound, scale))
    }

    /// All of it in view, and never past its own size: a small tree isn't blown up.
    public static func fit(_ content: CGSize, in view: CGSize) -> CGFloat {
        clamped(min(1, view.width / max(1, content.width), view.height / max(1, content.height)))
    }

    /// Where to scroll so the point under `anchor` (in the view) stays under it as the scale goes from `old` to `new`, as a
    /// whiteboard zooms around the pointer. Never before the start: the board has no room there.
    public static func offset(_ offset: CGPoint, keeping anchor: CGPoint, from old: CGFloat, to new: CGFloat) -> CGPoint {
        let ratio = new / max(old, 0.01)
        return CGPoint(x: max(0, (offset.x + anchor.x) * ratio - anchor.x), y: max(0, (offset.y + anchor.y) * ratio - anchor.y))
    }

    /// The offset a carried card asks for at an edge, one tick of the scroll: toward that edge, never before the start.
    public static func nudged(_ offset: CGPoint, toward edge: CGRectEdge, by distance: CGFloat = 14) -> CGPoint {
        switch edge {
        case .minXEdge: CGPoint(x: max(0, offset.x - distance), y: offset.y)
        case .maxXEdge: CGPoint(x: offset.x + distance, y: offset.y)
        case .minYEdge: CGPoint(x: offset.x, y: max(0, offset.y - distance))
        case .maxYEdge: CGPoint(x: offset.x, y: offset.y + distance)
        }
    }
}
