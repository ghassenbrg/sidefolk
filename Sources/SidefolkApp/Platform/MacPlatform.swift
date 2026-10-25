import AppKit
import SidefolkCore

/// The real Mac behind `PlatformBridge`: pasteboard, workspace, frontmost app.
final class MacPlatform: PlatformBridge {
    nonisolated init() {}

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
            if let pid, let app = NSRunningApplication(processIdentifier: pid_t(pid)) { return app.activate() }
            if let bundleId, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                return app.activate()
            }
            return false
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

/// Fullscreen detection without permissions: a window of the frontmost app covers a whole display.
enum Fullscreen {
    static func isFrontmostFullscreen(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let screens = NSScreen.screens.map { $0.frame }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let size = CGSize(width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if screens.contains(where: { abs($0.width - size.width) < 2 && abs($0.height - size.height) < 2 }) { return true }
        }
        return false
    }
}
