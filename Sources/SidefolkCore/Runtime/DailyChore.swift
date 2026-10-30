import Foundation

/// Work done once a day while Sidefolk runs. As a login item it can run for weeks, and "history is kept
/// for 7 days" must hold all that time, not only from one launch to the next. One sleeping task, one
/// wake-up a day.
actor DailyChore {
    private var task: Task<Void, Never>?
    private let interval: TimeInterval

    init(every interval: TimeInterval = 86_400) { self.interval = interval }

    func start(_ work: @escaping @Sendable () async -> Void) {
        task?.cancel()
        let interval = interval
        task = Task {
            while true {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await work()
            }
        }
    }

    /// Stops it, and waits for a run already under way: once this returns, nothing more runs (a run that had
    /// passed its check when the task was cancelled used to finish afterwards, seen on CI).
    func stop() async {
        let running = task
        task = nil
        running?.cancel()
        await running?.value
    }
}
