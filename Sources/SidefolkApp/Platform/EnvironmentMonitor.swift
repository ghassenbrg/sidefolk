import AppKit
import CoreGraphics
import SidefolkCore

/// Watches what affects interruptions — idle, lock, sleep, fullscreen — and keeps the attention
/// center informed. Event driven; the only timer runs while something is waiting for the user to return.
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
        observers.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFullscreen() }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFullscreen() }
        })
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
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    nonisolated static var secondsSinceKey: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }

    /// Handed to the attention center so it reads idle times only when it decides something.
    nonisolated static let signals: @Sendable () -> (secondsSinceKey: TimeInterval, secondsSinceInput: TimeInterval) = {
        (secondsSinceKey, secondsSinceInput)
    }

    func refreshFullscreen() {
        let full = NSWorkspace.shared.frontmostApplication.map { Fullscreen.isFrontmostFullscreen(pid: $0.processIdentifier) } ?? false
        Task { await attention.update { $0.fullscreen = full } }
    }

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
