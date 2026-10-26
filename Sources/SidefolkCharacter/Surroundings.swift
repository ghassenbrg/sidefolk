import AppKit

/// What a companion can sense of the desk without asking for any permission: how long since a key
/// was pressed, the frame of the window being worked in, the pointer and the clock. Read only when
/// a moment is being chosen (every half minute or so), never polled.
@MainActor
protocol Surroundings {
    /// Seconds since a key was pressed anywhere (CGEventSource; no Input Monitoring needed).
    var secondsSinceKey: TimeInterval { get }
    /// The frontmost other app's front window, in AppKit screen coordinates (y up). Only its
    /// bounds: window titles and contents would need Screen Recording, and aren't wanted.
    var activeWindow: CGRect? { get }
    var pointer: CGPoint { get }
    var now: Date { get }
}

@MainActor
struct Desktop: Surroundings {
    var secondsSinceKey: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }

    var activeWindow: CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        // Front to back: the first normal window of the frontmost app is the one being worked in.
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard rect.width > 80, rect.height > 60 else { continue }
            // Window server coordinates start at the top of the main display, y down.
            let top = NSScreen.screens.first?.frame.maxY ?? rect.maxY
            return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
        }
        return nil
    }

    var pointer: CGPoint { NSEvent.mouseLocation }
    var now: Date { Date() }
}
