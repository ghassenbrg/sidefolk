import AppKit
import SidefolkCore
import SwiftUI

/// The trackpad on the Calendar (D97): two fingers sideways turn the day, week, month or year, the page following the
/// fingers until it lets go; two fingers up and down scroll the month on, row by row, and it settles on a whole week
/// when the momentum ends. Vertical scrolling elsewhere is the scroll views' own. Only scroll events over the page are
/// read, and only while it is on screen (a local monitor, gone with the view).
struct CalendarScrollCatcher: NSViewRepresentable {
    var model: CalendarModel
    var step: (Int?) -> Void
    @Environment(\.layoutDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.handle = { context.coordinator.handle($0, in: view) }
        #if DEBUG
        Self.dev = context.coordinator
        #endif
        return view
    }

    #if DEBUG
    /// The page's catcher, for the dev channel's synthetic swipes.
    @MainActor static weak var dev: Coordinator?
    #endif

    func updateNSView(_ view: CatcherView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// The month's row height, as the month draws it.
    @MainActor static var monthRow: CGFloat = 96

    @MainActor final class Coordinator {
        var parent: CalendarScrollCatcher
        private enum Axis { case across, down }
        private var axis: Axis?
        private var across: CGFloat = 0
        private var turned = false
        private var settle: Task<Void, Never>?

        /// How far the fingers go before a period turns, and how far the page follows them at most.
        private static let turn: CGFloat = 90
        private static let follow: CGFloat = 140

        init(parent: CalendarScrollCatcher) { self.parent = parent }

        /// Whether the event was the Calendar's.
        func handle(_ event: NSEvent, in view: NSView) -> Bool {
            #if DEBUG
            CalendarScrollCatcher.dev = self
            #endif
            guard event.window === view.window, view.window != nil,
                  view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return false }
            return scroll(event)
        }

        /// A scroll over the page: a period turned, the month moved, or nothing (the scroll views have it).
        func scroll(_ event: NSEvent) -> Bool {
            let model = parent.model
            // A mouse wheel: the month moves a row a notch; everything else scrolls as it does.
            guard event.hasPreciseScrollingDeltas else {
                guard model.mode == .month, event.scrollingDeltaY != 0 else { return false }
                animate { model.scrollMonth(by: event.scrollingDeltaY > 0 ? -Self.row : Self.row, row: Self.row) }
                return true
            }
            if event.phase == .began || event.phase == .mayBegin {
                axis = nil
                across = 0
                turned = false
                settle?.cancel()
            }
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            if axis == nil, event.momentumPhase.isEmpty, abs(dx) + abs(dy) > 1.5 {
                axis = abs(dx) > abs(dy) * 1.3 ? .across : .down
            }
            switch axis {
            case .across:
                // Momentum after a turn is the same gesture going on: swallowed.
                if !event.momentumPhase.isEmpty { return true }
                if !turned {
                    across += dx
                    model.swipe = max(-Self.follow, min(Self.follow, across * 0.6))
                    if abs(across) > Self.turn {
                        turned = true
                        // Fingers moving left show what comes after, as pages do; where time runs right to left, before.
                        let later = (across < 0) != (parent.direction == .rightToLeft)
                        model.swipe = 0
                        parent.step(later ? 1 : -1)
                    }
                }
                if event.phase == .ended || event.phase == .cancelled, !turned {
                    animate { model.swipe = 0 }
                }
                return true
            case .down where model.mode == .month:
                model.scrollMonth(by: -dy, row: Self.row)
                if event.momentumPhase == .ended || event.phase == .cancelled {
                    animate { model.settleMonth(row: Self.row) }
                } else if event.phase == .ended {
                    // No momentum may follow a slow lift: settle unless it starts.
                    settle = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(120))
                        guard !Task.isCancelled else { return }
                        self?.animate { model.settleMonth(row: Self.row) }
                    }
                } else if event.momentumPhase == .began {
                    settle?.cancel()
                }
                return true
            default:
                return false
            }
        }

        private static var row: CGFloat { CalendarScrollCatcher.monthRow }

        private func animate(_ change: () -> Void) {
            withAnimation(parent.reduceMotion ? nil : Theme.Motion.standard) { change() }
        }
    }

    final class CatcherView: NSView {
        var handle: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let handle = self.handle else { return event }
                return MainActor.assumeIsolated { handle(event) } ? nil : event
            }
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}
