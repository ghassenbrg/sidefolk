import AppKit
import SidefolkCore
import SwiftUI

/// The stack's arc (D88): held cards come out of the count on the companion's shoulder and fold back into it along a
/// short curve. It moves only at those moments (a few tenths of a second) and never with Reduce Motion; at rest
/// nothing animates, so the desktop costs what it did.
extension SidecardController {
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// The stack just appeared: its cards come out of the shoulder, the front one first.
    func fanOut() {
        guard !Self.reduceMotion, let badge = badgeProvider?() else {
            model.fanFrom = nil
            model.stackOut = true
            return
        }
        let glass = glassFrame
        // From the stack's foot to the count, in the view's terms (y down); kept short, so the cards are inside the
        // window when they can be seen (they start a fifth of their size, faded).
        model.fanFrom = CGSize(width: min(max(badge.x - glass.midX, -140), 140), height: min(max(glass.minY - badge.y, 24), 90))
        model.stackOut = false
        DispatchQueue.main.async { [weak self] in self?.model.stackOut = true }
    }

    /// A card folds into the stack: a small copy of it drops into the count while the card goes.
    func flyToShoulder(_ item: AttentionItem) {
        guard !Self.reduceMotion, hosted.panel.isVisible, model.shape == .card, model.item?.id == item.id,
              let badge = badgeProvider?(), let screen = hosted.panel.screen else { return }
        let card = SidecardView.stackItem(item, companion: model.companionName, sessions: model.sessions)
        FoldFlight.fly(card, from: glassFrame, to: badge, on: screen)
    }

    /// The glass on screen, without the shadow's room around it.
    private var glassFrame: NSRect {
        let m = SidecardView.margin, f = hosted.panel.frame
        return NSRect(x: f.minX + m.leading, y: f.minY + m.bottom, width: f.width - m.leading - m.trailing, height: f.height - m.top - m.bottom)
    }
}

/// The moment a card folds: a held card's look, shrinking along an arc from where the card was into the count, in a
/// window of its own that takes no clicks and is gone half a second later.
@MainActor
enum FoldFlight {
    private static var flying: [FloatingPanel] = []
    static let seconds = 0.42

    static func fly(_ card: SidecardStack.Item, from start: NSRect, to end: NSPoint, on screen: NSScreen) {
        let area = start.union(NSRect(x: end.x - 20, y: end.y - 20, width: 40, height: 40)).insetBy(dx: -24, dy: -24)
        let panel = FloatingPanel(size: area.size)
        panel.allowsKey = false
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.setFrame(area, display: false)
        // In the view's terms: top-left origin.
        let from = CGPoint(x: start.midX - area.minX, y: area.maxY - start.midY)
        let to = CGPoint(x: end.x - area.minX, y: area.maxY - end.y)
        let host = NSHostingView(rootView: FoldFlightView(card: card, from: from, to: to))
        host.frame = NSRect(origin: .zero, size: area.size)
        panel.contentView = host
        panel.orderFrontRegardless()
        flying.append(panel)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds + 0.08))
            panel.orderOut(nil)
            flying.removeAll { $0 === panel }
        }
    }
}

private struct FoldFlightView: View {
    var card: SidecardStack.Item
    var from: CGPoint
    var to: CGPoint
    @State private var gone = false

    var body: some View {
        SidecardStack(items: [card])
            .scaleEffect(gone ? 0.12 : 1)
            .opacity(gone ? 0.15 : 1)
            .animation(.easeIn(duration: FoldFlight.seconds), value: gone)
            // Sideways late and down early: the path bends like something set down on a shoulder.
            .offset(x: gone ? to.x - from.x : 0)
            .animation(.easeIn(duration: FoldFlight.seconds), value: gone)
            .offset(y: gone ? to.y - from.y : 0)
            .animation(.easeOut(duration: FoldFlight.seconds), value: gone)
            .position(from)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { DispatchQueue.main.async { gone = true } }
            .accessibilityHidden(true)
    }
}
