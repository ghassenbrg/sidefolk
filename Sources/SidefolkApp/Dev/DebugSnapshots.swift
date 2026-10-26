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
        observers.append(dnc.addObserver(forName: notification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { capture(into: home.appendingPathComponent("snapshots", isDirectory: true)) }
        })
        observers.append(dnc.addObserver(forName: command, object: nil, queue: .main) { note in
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
}
#endif
