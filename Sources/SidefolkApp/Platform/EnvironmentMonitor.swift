import AppKit
import CoreGraphics
import SidefolkCore

/// Watches what affects interruptions — idle, lock, sleep, fullscreen — and keeps the attention
/// center informed. Event driven; the only timer runs while something is waiting for the user to return, and a space change
/// looks again twice in its next second and a half.
@MainActor
final class EnvironmentMonitor {
    private let attention: AttentionCenter
    private var observers: [NSObjectProtocol] = []
    private var awayPoll: Timer?
    private(set) var isLocked = false
    var onWake: (() -> Void)?
    var onAwayChanged: ((Bool) -> Void)?
    var onClockChange: (() -> Void)?

    static let awayAfter: TimeInterval = 300

    init(attention: AttentionCenter) { self.attention = attention }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.spaceMoved() }
            })
        }
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWake?() }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setAway(true) }
        })
        let dnc = DistributedNotificationCenter.default()
        // Any process can post these two, so they are only a hint: the window server has the answer.
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard ScreenLock.isLocked else { return }
                self?.isLocked = true
                self?.setAway(true)
            }
        })
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard !ScreenLock.isLocked else { return }
                self?.isLocked = false
                self?.setAway(false)
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onClockChange?() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onClockChange?() }
        })
        refreshFullscreen()
        Task { await attention.setSignalProvider(Self.signals) }
    }

    /// Seconds since the last keyboard or mouse input anywhere (no permission needed).
    nonisolated static var secondsSinceInput: TimeInterval {
        #if DEBUG
        // A debug run nobody sits at can still say someone is here, to see what they would (SIDEFOLK_DEV_PRESENT=1).
        if ProcessInfo.processInfo.environment["SIDEFOLK_DEV_PRESENT"] == "1" { return 1 }
        #endif
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    nonisolated static var secondsSinceKey: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }

    /// Handed to the attention center so it reads idle times only when it decides something.
    nonisolated static let signals: @Sendable () -> (secondsSinceKey: TimeInterval, secondsSinceInput: TimeInterval) = {
        (secondsSinceKey, secondsSinceInput)
    }

    var onSpaceChanged: (() -> Void)?

    private var fullScreen = FullScreenState()
    private var settling: Task<Void, Never>?

    /// Whether the person is on a full-screen app (D138), looked at now. Sidefolk in front keeps the last answer.
    var inFullScreen: Bool {
        if let app = NSWorkspace.shared.frontmostApplication {
            let own = app.processIdentifier == ProcessInfo.processInfo.processIdentifier
            let was = fullScreen.inFullScreen
            fullScreen.observe(frontmostIsSidefolk: own, inFullScreen: !own && Fullscreen.isFrontmostFullscreen(pid: app.processIdentifier))
            if fullScreen.inFullScreen != was { Log.shared.info("fullscreen", "changed", ["full_screen": "\(fullScreen.inFullScreen)"]) }
        }
        return fullScreen.inFullScreen
    }

    func refreshFullscreen() {
        let full = inFullScreen
        Task { await attention.update { $0.fullscreen = full } }
    }

    private func spaceMoved() {
        #if DEBUG
        layersLine("moved")
        #endif
        refreshFullscreen()
        onSpaceChanged?()
        // A swipe is still moving when this comes, and the space may not have settled: look again, and tell only when the
        // answer changed.
        settling?.cancel()
        settling = Task { [weak self] in
            for pause in [0.4, 1.2] {
                try? await Task.sleep(for: .seconds(pause))
                guard let self, !Task.isCancelled else { return }
                let was = self.fullScreen.inFullScreen
                #if DEBUG
                self.layersLine("settled \(pause)")
                #endif
                self.refreshFullscreen()
                if self.fullScreen.inFullScreen != was { self.onSpaceChanged?() }
            }
        }
    }

    #if DEBUG
    /// The desktop's layers on screen at each space change, levels and sizes only, to check the rule on a real space.
    private func layersLine(_ when: String) {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let layers = list.compactMap { info -> String? in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer < 0, let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            return "\(layer):\(Int(b["Width"] ?? 0))x\(Int(b["Height"] ?? 0))"
        }
        Log.shared.info("fullscreen", "layers", ["when": when, "desktop": layers.joined(separator: " "), "full_screen": "\(fullScreen.inFullScreen)"])
    }
    #endif

    private func setAway(_ away: Bool) {
        Task { await attention.update { $0.away = away } }
        onAwayChanged?(away)
        if away {
            // While away, look for the user's return every 20 s (cheap; stops once they are back).
            guard awayPoll == nil else { return }
            awayPoll = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isLocked else { return }
                    if Self.secondsSinceInput < 20 { self.setAway(false) }
                }
            }
        } else {
            awayPoll?.invalidate()
            awayPoll = nil
        }
    }
}
