import CoreGraphics

/// Whether the person is on a full-screen app (D138), from the window server's list alone: no permission needed.
///
/// A window the display's size isn't enough: on a Mac with a notch a full-screen app is exactly as big as a window zoomed to
/// the desktop (measured, 1512 × 949 both), and the menu bar stays on screen in either. What differs, measured on the
/// founder's: Finder's desktop window (the desktop icons' level) is on screen on a desktop and gone on a full-screen space.
/// Missing it alone isn't trusted, since someone may run without Finder's desktop: the front app's windows must also fill
/// the display below the menu bar, together, as Chrome's tab strip and page do.
public enum FullScreenSignals {
    /// One on-screen window, in the window server's coordinates (top left of the main display, y down).
    public struct Window: Sendable, Equatable {
        public var layer: Int
        public var frame: CGRect
        /// Owned by the frontmost app.
        public var front: Bool
        public init(layer: Int, frame: CGRect, front: Bool) {
            self.layer = layer
            self.frame = frame
            self.front = front
        }
    }

    /// A display, with the height of its menu bar (the display's height less its visible frame's top).
    public struct Display: Sendable, Equatable {
        public var frame: CGRect
        public var menuBar: CGFloat
        public init(frame: CGRect, menuBar: CGFloat) {
            self.frame = frame
            self.menuBar = menuBar
        }
    }

    public static func inFullScreen(windows: [Window], displays: [Display], desktopIconLevel: Int) -> Bool {
        displays.contains { display in
            let wide = windows.filter { abs($0.frame.minX - display.frame.minX) < 1 && abs($0.frame.width - display.frame.width) < 1 }
            let front = wide.filter { $0.front && $0.layer == 0 }
            // The whole display, as before: something that takes it without a space of its own.
            if front.contains(where: { abs($0.frame.height - display.frame.height) < 1 }) { return true }
            guard !wide.contains(where: { $0.layer == desktopIconLevel }), let top = front.map(\.frame.minY).min(),
                  let bottom = front.map(\.frame.maxY).max() else { return false }
            return top <= display.frame.minY + display.menuBar + 1 && bottom >= display.frame.maxY - 1
        }
    }
}

/// What the person is on, as far as full screen goes. Sidefolk coming forward itself (a card, a slip, Ask) says nothing about
/// the space under it, so the last answer for another app stands until another app is in front.
public struct FullScreenState: Sendable, Equatable {
    public private(set) var inFullScreen = false
    public init() {}

    public mutating func observe(frontmostIsSidefolk: Bool, inFullScreen full: Bool) {
        guard !frontmostIsSidefolk else { return }
        inFullScreen = full
    }
}
