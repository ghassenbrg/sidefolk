import CoreGraphics

/// Whether a card stands above the companion or under it. Above, it has a tail, which makes it taller; under, it hasn't. Near the top of the screen a card with no tail
/// fits above and one with a tail doesn't, so judging by its size just now flips it at every layout: over the companion, tail, too tall, under it, no tail, fits, over it.
/// The window then resizes without end until AppKit gives up, and the app goes down (`_postWindowNeedsUpdateConstraints`: any card out while the companion stands high, or
/// hops high in catch-me). So above always counts the tail's room, whether it shows now or not.
public enum CardPlacement {
    /// - Parameter roomAbove: how much taller it would be up there than it is now.
    public static func standsAbove(top: CGFloat, height: CGFloat, roomAbove: CGFloat, screenTop: CGFloat) -> Bool {
        top + height + roomAbove <= screenTop
    }
}
