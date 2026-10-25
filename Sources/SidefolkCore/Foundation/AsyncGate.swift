import Foundation

/// Runs async work one at a time. An actor alone isn't enough for "count, then create": it lets
/// another call in at every `await`, so two calls could both see room for one more (a quota race).
public actor AsyncGate {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func run<T: Sendable>(_ work: @Sendable () async throws -> T) async rethrows -> T {
        await enter()
        defer { leave() }
        return try await work()
    }

    private func enter() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func leave() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }
}
