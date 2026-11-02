#if DEBUG
import AppKit
import SwiftUI

/// Native mouse regression check on UISnapshots' offscreen, isolated fixture. A picture cannot detect a hidden
/// buffer week taking clicks over the header. Run with --ui-snapshots <folder> --check-calendar-input (English).
enum CalendarInputCheck {
    private final class Window: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
    }

    static func run(model: HomeModel, into folder: URL) async throws {
        let window = Window()
        HomeWindowController.configure(window, model: model)
        window.setFrameOrigin(CGPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        model.selection = .calendar
        model.calendar.sidebarShown = false
        for size in [CGSize(width: 1280, height: 800), CGSize(width: 860, height: 560)] {
            window.setContentSize(size)
            model.calendar.mode = .month
            await model.calendar.reload()
            try await settle()
            if let view = window.contentView?.superview, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("month-\(Int(size.width)).png"))
            }
            // The title is above the grid in both the one-row and wrapped header layouts.
            // Try an initial month and a partially scrolled month: its extra week must never take this double-click.
            for offset in [CGFloat(0), CalendarScrollCatcher.monthRow / 2] {
                model.calendar.monthScroll = offset
                model.calendar.draft = nil
                try await settle()
                await click(window, x: 400, top: 82, count: 2)
                try require(model.calendar.draft == nil, "Hidden month cell received the header double-click at width \(size.width), offset \(offset)")
                print("PASS header double-click", size.width, offset)
            }
            if size.width == 1280 {
                model.calendar.monthScroll = 0
                try await settle()
                await click(window, x: 400, top: 120, count: 2)
                try require(model.calendar.draft == nil, "Hidden buffer week received a weekday-header double-click")
                for (x, mode) in [(CGFloat(1105), CalendarModel.Mode.week), (1168, .month), (1049, .day), (1168, .month)] {
                    await click(window, x: x, top: 82, count: 1)
                    try require(model.calendar.mode == mode, "Header failed to switch to \(mode)")
                    try require(model.calendar.draft == nil, "View button opened an invisible cell's editor")
                }
                let row = CalendarScrollCatcher.monthRow
                let cellWidth: CGFloat = (1280 - 233 - 48) / 7
                let room = max(1, Int((row - 28) / 19))
                let busy = model.calendar.days.firstIndex { model.calendar.entries(on: $0).count > room }
                try require(busy != nil, "The fixture needs a busy day to check its overflow link")
                if let busy {
                    await click(window, x: 257 + CGFloat(busy % 7) * cellWidth + 20,
                                top: 132 + CGFloat(busy / 7) * row + 26 + CGFloat(room - 1) * 19 + 8, count: 1)
                }
                try require(model.calendar.mode == .day, "Month overflow link did not open Day")
                model.calendar.mode = .month
                await model.calendar.reload()
                try await settle()
                let quiet = model.calendar.days.indices.min { a, b in
                    model.calendar.entries(on: model.calendar.days[a]).count < model.calendar.entries(on: model.calendar.days[b]).count
                } ?? 0
                await click(window, x: 257 + (CGFloat(quiet % 7) + 0.5) * cellWidth,
                            top: 132 + CGFloat(quiet / 7 + 1) * row - 12, count: 2)
                try require(model.calendar.draft?.fromButton == false, "Visible month cell no longer accepts a double-click")
                model.calendar.draft = nil
                try await settle()
                print("PASS view buttons, overflow link and visible-cell double-click")
            }
        }
    }

    private static func click(_ window: NSWindow, x: CGFloat, top: CGFloat, count: Int) async {
        for n in 1...count {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: window.frame.height - top), modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: n, pressure: type == .leftMouseUp ? 0 : 1)!
                NSApp.postEvent(event, atStart: false)
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
        try? await Task.sleep(for: .milliseconds(250))
    }

    private static func settle() async throws { try await Task.sleep(for: .milliseconds(400)) }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw NSError(domain: "CalendarInputCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
#endif
