import Foundation
import Synchronization

/// What the first look at a brand-new watcher found, for the card that confirms it. A watcher must not be
/// reported as working when its very first check has already failed (docs/PRODUCT.md E5).
struct FirstLook: Sendable, Equatable {
    /// The probe ran and answered (not postponed for politeness, not offline, not out of time).
    var answered = false
    /// The check failed; the message is written for people ("The page said “Not Found” (404).").
    var problem: String?
    /// The probe's own remark about how things stand ("Xcode isn't running right now.").
    var note: String?

    var isFine: Bool { problem == nil && note == nil }
}

extension WatcherEngine {
    /// Looks at a watcher that was just created, right now, and reports what the look found. The person who
    /// asked is not made to wait their turn at a site (`polite: false`); anything else is. Waits at most
    /// `seconds`: a slow site must not hold up the answer, and the look carries on and is saved like any other.
    func firstLook(of id: String, polite: Bool, within seconds: TimeInterval = 5) async -> FirstLook {
        await ensureLoaded()
        guard watchers[id] != nil else { return FirstLook() }
        lookouts[id] = FirstLook()
        _ = await valueWithin(seconds) { await self.look(id, polite: polite) }
        defer { lookouts[id] = nil }
        return lookouts[id] ?? FirstLook()
    }

    private func look(_ id: String, polite: Bool) async {
        if running.contains(id) {
            // The schedule got there first (a new watcher is due at once); its answer lands in `lookouts` too.
            while running.contains(id) { try? await Task.sleep(for: .milliseconds(25)) }
        } else if polite {
            await runCheck(id)
        } else {
            await WatchContext.$isManualCheck.withValue(true) { await runCheck(id) }
        }
        arm()
    }
}

/// Waits for `work` but no longer than `seconds`. The work is never cancelled: when time runs out it just
/// finishes unseen (a task group cannot do this, it always waits for its children).
func valueWithin<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () async -> T) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let handoff = Handoff(continuation)
        let timer = Task {
            try? await Task.sleep(for: .seconds(seconds))
            handoff.finish(nil)
        }
        Task {
            let value = await work()
            timer.cancel()
            handoff.finish(value)
        }
    }
}

/// Resumes a continuation exactly once, from whichever of two tasks gets there first.
private final class Handoff<T: Sendable>: Sendable {
    private let slot: Mutex<CheckedContinuation<T?, Never>?>

    init(_ continuation: CheckedContinuation<T?, Never>) { slot = Mutex(continuation) }

    func finish(_ value: T?) {
        let continuation = slot.withLock { held in
            defer { held = nil }
            return held
        }
        continuation?.resume(returning: value)
    }
}
