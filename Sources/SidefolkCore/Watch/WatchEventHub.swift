import Darwin
import Foundation

/// Listens for folder, file and process events so watchers can look the moment something happens,
/// instead of waiting for their interval. One kernel source is shared by every watcher that wants it.
/// Events are debounced, then reported as the set of watcher ids to check.
final class WatchEventHub: @unchecked Sendable {
    private struct Entry {
        var source: any DispatchSourceProtocol
        var ids: Set<String>
    }

    // Everything below is touched only on `queue`.
    private let queue = DispatchQueue(label: "app.sidefolk.watch.events")
    private var entries: [WatchEventTarget: Entry] = [:]
    private var targetsById: [String: Set<WatchEventTarget>] = [:]
    private var pending: Set<String> = []
    private var flushScheduled = false

    private let debounce: TimeInterval
    private let onEvents: @Sendable (Set<String>) -> Void

    init(debounce: TimeInterval = 0.4, onEvents: @escaping @Sendable (Set<String>) -> Void) {
        self.debounce = debounce
        self.onEvents = onEvents
    }

    /// Replaces what watcher `id` listens to.
    func set(_ targets: [WatchEventTarget], for id: String) {
        queue.sync {
            let wanted = Set(targets)
            for old in (targetsById[id] ?? []).subtracting(wanted) { detach(id, from: old) }
            var attached: Set<WatchEventTarget> = []
            for target in wanted where attach(id, to: target) { attached.insert(target) }
            targetsById[id] = attached
        }
    }

    func remove(_ id: String) { set([], for: id) }

    func stopAll() {
        queue.sync {
            for entry in entries.values { entry.source.cancel() }
            entries.removeAll()
            targetsById.removeAll()
            pending.removeAll()
        }
    }

    // MARK: On the queue

    private func attach(_ id: String, to target: WatchEventTarget) -> Bool {
        if entries[target] != nil {
            entries[target]?.ids.insert(id)
            return true
        }
        guard let source = makeSource(for: target) else { return false }
        entries[target] = Entry(source: source, ids: [id])
        source.resume()
        return true
    }

    private func detach(_ id: String, from target: WatchEventTarget) {
        guard var entry = entries[target] else { return }
        entry.ids.remove(id)
        if entry.ids.isEmpty {
            entry.source.cancel()
            entries[target] = nil
        } else {
            entries[target] = entry
        }
    }

    private func makeSource(for target: WatchEventTarget) -> (any DispatchSourceProtocol)? {
        switch target {
        case .directory(let path), .file(let path):
            let fd = open(path, O_EVTONLY | O_CLOEXEC)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .link, .delete, .rename, .revoke], queue: queue)
            source.setEventHandler { [weak self, weak source] in
                guard let self, let source else { return }
                self.fired(target)
                // The thing we opened was replaced or removed: this source is now deaf, drop it so the
                // next refresh opens the path again.
                if !source.data.isDisjoint(with: [.delete, .rename, .revoke]) { self.drop(target) }
            }
            source.setCancelHandler { close(fd) }
            return source
        case .process(let pid):
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
            source.setEventHandler { [weak self] in
                self?.fired(target)
                self?.drop(target) // an exit happens once
            }
            return source
        }
    }

    private func drop(_ target: WatchEventTarget) {
        guard let entry = entries.removeValue(forKey: target) else { return }
        entry.source.cancel()
        for id in entry.ids { targetsById[id]?.remove(target) }
    }

    private func fired(_ target: WatchEventTarget) {
        guard let ids = entries[target]?.ids else { return }
        pending.formUnion(ids)
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + debounce) { [self] in
            flushScheduled = false
            let ids = pending
            pending.removeAll()
            if !ids.isEmpty { onEvents(ids) }
        }
    }
}
