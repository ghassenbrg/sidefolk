import Foundation

/// One field's saves, in the order they were made. The page's tool runs for each, and nothing keeps two calls in order, so a slow older one could land last, or fail and bring its old text back over a newer one.
/// Only the newest value is sent once its turn comes, and only the newest outcome is told: what came before it no longer matters.
@MainActor public final class PageFieldSaves {
    private var tail: Task<Void, Never>?
    private var newest = 0
    private var queued: String?

    public init() {}

    /// Whether a save is on its way: until it lands, what's shown isn't yet what was saved.
    public var isBusy: Bool { queued != nil }

    /// `send` says whether it was saved. `finished` is only told about the newest.
    public func save(_ text: String, send: @escaping @MainActor (String) async -> Bool, finished: @escaping @MainActor (_ saved: Bool) -> Void) {
        guard text != queued else { return }
        queued = text
        newest += 1
        let mine = newest, before = tail
        tail = Task { @MainActor [weak self] in
            await before?.value
            guard let self, mine == self.newest else { return }
            let saved = await send(text)
            guard mine == self.newest else { return }
            self.queued = nil
            finished(saved)
        }
    }

    /// When everything asked for so far has been dealt with.
    public func settled() async {
        await tail?.value
    }
}
