import AppKit
import SidefolkCore

/// The real Mac behind `PlatformBridge`: pasteboard, workspace, frontmost app.
final class MacPlatform: PlatformBridge {
    nonisolated init() {}

    nonisolated func calendarEvents(from: Date, to: Date) async -> [CalendarEvent]? {
        #if DEBUG
        if let sample = SampleCalendar.live { return sample.list(from: from, to: to) }
        #endif
        return await MainActor.run { MacCalendar.events(from: from, to: to) }
    }

    nonisolated func calendars() async -> [CalendarInfo]? {
        #if DEBUG
        if SampleCalendar.live != nil { return SampleCalendar.calendars }
        #endif
        return await MainActor.run { MacCalendar.calendars() }
    }

    nonisolated func calendarEvent(id: String) async -> CalendarEvent? {
        #if DEBUG
        if let sample = SampleCalendar.live { return sample.event(id: id) }
        #endif
        return await MainActor.run { MacCalendar.event(id: id) }
    }

    nonisolated func createCalendarEvent(_ draft: CalendarDraft) async throws -> CalendarEvent {
        #if DEBUG
        if let sample = SampleCalendar.live { return try sample.create(draft) }
        #endif
        return try await MainActor.run { try MacCalendar.create(draft) }
    }

    nonisolated func updateCalendarEvent(id: String, to draft: CalendarDraft) async throws -> CalendarEvent {
        #if DEBUG
        if let sample = SampleCalendar.live { return try sample.update(id: id, to: draft) }
        #endif
        return try await MainActor.run { try MacCalendar.update(id: id, to: draft) }
    }

    nonisolated func deleteCalendarEvent(id: String) async throws {
        #if DEBUG
        if let sample = SampleCalendar.live { return try sample.delete(id: id) }
        #endif
        try await MainActor.run { try MacCalendar.delete(id: id) }
    }

    nonisolated func clipboardText() async -> String? {
        await MainActor.run { NSPasteboard.general.string(forType: .string) }
    }

    nonisolated func setClipboard(_ text: String) async {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    nonisolated func open(url: URL) async -> Bool {
        await MainActor.run { NSWorkspace.shared.open(url) }
    }

    nonisolated func openApplication(_ nameOrBundleId: String) async -> Bool {
        let target: URL? = await MainActor.run {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: nameOrBundleId) { return url }
            let name = nameOrBundleId.hasSuffix(".app") ? nameOrBundleId : nameOrBundleId + ".app"
            for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                        NSHomeDirectory() + "/Applications", "/Applications/Utilities"] {
                let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
            return nil
        }
        guard let target else { return false }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: target, configuration: NSWorkspace.OpenConfiguration())
            return true
        } catch {
            return false
        }
    }

    nonisolated func reveal(path: String) async {
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    }

    nonisolated func activateApplication(pid: Int?, bundleId: String?) async -> Bool {
        await MainActor.run {
            let app = pid.flatMap { NSRunningApplication(processIdentifier: pid_t($0)) }
                ?? bundleId.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
            guard let app, app.activationPolicy == .regular else { return false }
            // Activation is cooperative since macOS 14: the active app (Sidefolk, just clicked) has
            // to yield to the other one, or the request is quietly ignored.
            NSApp.yieldActivation(to: app)
            if app.isHidden { app.unhide() }
            return app.activate()
        }
    }

    nonisolated func frontmostApplication() async -> FrontmostApp? {
        await MainActor.run {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            return FrontmostApp(name: app.localizedName ?? "App", bundleId: app.bundleIdentifier,
                                isFullscreen: Fullscreen.isFrontmostFullscreen(pid: app.processIdentifier))
        }
    }
}

/// Fullscreen detection without permissions, from the window server's list (`FullScreenSignals`, D138).
enum Fullscreen {
    static func isFrontmostFullscreen(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let windows = list.compactMap { info -> FullScreenSignals.Window? in
            guard let layer = info[kCGWindowLayer as String] as? Int, let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            let frame = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            return .init(layer: layer, frame: frame, front: (info[kCGWindowOwnerPID as String] as? pid_t) == pid)
        }
        return FullScreenSignals.inFullScreen(windows: windows, displays: displays, desktopIconLevel: Int(CGWindowLevelForKey(.desktopIconWindow)))
    }

    /// The displays in the window server's coordinates: top left of the main display, y down.
    static var displays: [FullScreenSignals.Display] {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map { screen in
            let f = screen.frame
            return .init(frame: CGRect(x: f.minX, y: mainHeight - f.maxY, width: f.width, height: f.height), menuBar: f.maxY - screen.visibleFrame.maxY)
        }
    }
}
