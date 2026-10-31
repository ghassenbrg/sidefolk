#if DEBUG
import AppKit
import SidefolkCore

/// Debug builds only: post the distributed notification `app.sidefolk.dev.snapshot` and every visible
/// Sidefolk window is written as a PNG to `$SIDEFOLK_HOME/snapshots/`. Lets developers (and agents
/// without screen capture) check the composed UI.
enum DebugSnapshots {
    static let notification = Notification.Name("app.sidefolk.dev.snapshot")
    /// `object` = "ask:<text>", "respond:<action id>", "dismiss", "hideAsk" — drives the UI for QA.
    static let command = Notification.Name("app.sidefolk.dev.command")
    private static var observers: [NSObjectProtocol] = []
    static var handler: ((String) -> Void)?

    static func install(home: URL) {
        let dnc = DistributedNotificationCenter.default()
        let mine = home.standardizedFileURL.resolvingSymlinksInPath().path
        // A note naming another home is for another debug app running beside this one (scripts/dev.swift).
        let forMe: @Sendable (Notification) -> Bool = { note in (note.userInfo?["home"] as? String).map { $0 == mine } ?? true }
        observers.append(dnc.addObserver(forName: notification, object: nil, queue: .main) { note in
            guard forMe(note) else { return }
            MainActor.assumeIsolated { capture(into: home.appendingPathComponent("snapshots", isDirectory: true)) }
        })
        observers.append(dnc.addObserver(forName: command, object: nil, queue: .main) { note in
            guard forMe(note) else { return }
            let text = note.object as? String ?? ""
            MainActor.assumeIsolated {
                Log.shared.info("dev", "command", ["command": text])
                handler?(text)
            }
        })
    }

    static func capture(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        for (i, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView, view.bounds.width > 1 else { continue }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = "\(stamp)-\(i)-\(type(of: window))-\(Int(window.frame.minX))x\(Int(window.frame.minY)).png"
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
        }
        Log.shared.info("dev", "snapshots written", ["dir": dir.path])
    }

    /// Scrolls the tallest scroll view among Sidefolk's visible windows (Settings, Home) to `fraction` of the way down
    /// (0 top, 1 bottom), so `snap` sees below the fold.
    static func scroll(to fraction: Double) {
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            if let scroll = view as? NSScrollView { return [scroll] }
            return view.subviews.flatMap(scrollViews)
        }
        let all = NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap(scrollViews)
        guard let scroll = all.max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }),
              let document = scroll.documentView else { return }
        let room = max(document.frame.height - scroll.contentView.bounds.height, 0)
        let y = document.isFlipped ? room * fraction : room * (1 - fraction)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
#endif
