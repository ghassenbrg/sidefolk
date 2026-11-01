import Foundation

/// A watch's newest run of checks as the engine holds it, and when it last reached the database.
struct OpenRun: Sendable {
    var check: WatchCheck
    var savedAt: Date
    var dirty = false
}

// A watch's history (D87): every check it made, a run of the same outcome as one row, and the last two versions of the
// text a page or file watch compared. Reports aren't logged: they read every few seconds and keep their own line of
// values in memory (D58).
extension WatcherEngine {
    // MARK: Recording

    /// After a check that answered: unchanged or changed, and the text it compared.
    func note(_ result: ProbeResult, for w: Watcher, comparedSince before: Date?, at now: Date, took: Duration) async {
        guard w.mode != .report else { return }
        if let compared = result.compared { await keep(compared, for: w.id, before: before, at: now) }
        guard result.triggered else { return await note(.unchanged, for: w, at: now, took: took) }
        let summary = result.summary.displaySafe
        await note(.changed, for: w, at: now, reason: summary.isEmpty ? w.title : summary, took: took)
    }

    /// After a check that failed. Waiting a moment for a busy site, or for the network to come back, isn't a check.
    func note(_ error: any Error, for w: Watcher, at now: Date, took: Duration) async {
        switch error as? ProbeError {
        case .deferred?, .offline?: return
        default: await note(.failed, for: w, at: now, reason: w.lastError ?? Self.reason(for: error), took: took)
        }
    }

    /// Adds a check to the watch's newest run when it found the same, or starts a new run. A run that only grew is saved
    /// with the watcher's routine saves (every few minutes), so a watch looking every 30 s writes no more than before;
    /// readers ask the engine, which has the run as it stands (`checks(for:)`).
    func note(_ result: WatchCheck.Result, for w: Watcher, at now: Date, reason: String? = nil, took: Duration? = nil) async {
        guard w.mode != .report else { return }
        let reason = result == .unchanged || result == .paused ? nil : reason?.clipped(WatchHistoryLimits.reasonCharacters)
        let ms = took.map { Int(($0.components.seconds * 1000) + $0.components.attoseconds / 1_000_000_000_000_000) }
        // After a relaunch the newest run is the database's: a quiet watch goes on counting in the same row.
        if openRuns[w.id] == nil, let newest = try? await log.checks(watcherId: w.id, limit: 1).first {
            openRuns[w.id] = OpenRun(check: newest, savedAt: newest.lastAt)
        }
        if var run = openRuns[w.id], run.check.continues(result, reason: reason) {
            run.check.count += 1
            run.check.lastAt = now
            run.check.durationMs = ms
            run.dirty = true
            if now.timeIntervalSince(run.savedAt) >= Self.routineSaveInterval, let saved = await save(run.check) {
                run = OpenRun(check: saved, savedAt: now)
            }
            openRuns[w.id] = run
            return
        }
        await flushRun(w.id)
        let check = WatchCheck(watcherId: w.id, result: result, at: now, reason: reason, durationMs: ms)
        // A new run is saved at once: a change, a failure or a pause is what the timeline is for.
        openRuns[w.id] = await save(check).map { OpenRun(check: $0, savedAt: now) }
    }

    /// The text before (when the probe had it) and now, unless the newest kept version already is that text.
    func keep(_ compared: ComparedText, for id: String, before: Date?, at now: Date) async {
        do {
            if let text = compared.before { try await log.addVersion(watcherId: id, text: text, at: before ?? now) }
            try await log.addVersion(watcherId: id, text: compared.text, at: now)
        } catch {
            Log.shared.warning("watch", "could not keep a version", ["error": "\(error)"])
        }
    }

    private func save(_ check: WatchCheck) async -> WatchCheck? {
        do { return try await log.save(check) } catch {
            // The watcher was removed in the meantime (its rows went with it), or the disk is full: the log is a record,
            // never a reason for a check to fail.
            Log.shared.warning("watch", "could not record a check", ["error": "\(error)"])
            return nil
        }
    }

    private func flushRun(_ id: String) async {
        guard let run = openRuns[id], run.dirty else { return }
        openRuns[id] = await save(run.check).map { OpenRun(check: $0, savedAt: clock.now) }
    }

    /// Saves every run that grew since it was last written. Call before quitting.
    public func flushHistory() async {
        for id in Array(openRuns.keys) { await flushRun(id) }
    }

    // MARK: Reading

    /// A watch's runs of checks, newest first, the newest as it stands now.
    public func checks(for id: String, limit: Int = 200) async -> [WatchCheck] {
        var rows = (try? await log.checks(watcherId: id, limit: limit)) ?? []
        if let open = openRuns[id]?.check, let i = rows.firstIndex(where: { $0.id == open.id }) { rows[i] = open }
        return rows
    }

    /// The newest checks of each watch as one result each, oldest first (On duty's bars).
    public func recentTicks(for ids: [String], count: Int) async -> [String: [WatchCheck.Result]] {
        let found = (try? await log.latest(watcherIds: ids, rows: count)) ?? [:]
        return found.reduce(into: [:]) { out, entry in
            let runs = entry.value.map { row in openRuns[entry.key].flatMap { $0.check.id == row.id ? $0.check : nil } ?? row }
            out[entry.key] = WatchCheck.ticks(runs, count: count)
        }
    }

    /// The newest change each watch saw (`watch.list`). Changes are saved as they happen, so the database has them.
    public func lastChanges(for ids: [String]) async -> [String: WatchCheck] {
        (try? await log.lastChanges(watcherIds: ids)) ?? [:]
    }

    /// The text a page or file watch kept, oldest first: the latest change's before and after.
    public func versions(for id: String) async -> [WatchVersion] {
        (try? await log.versions(watcherId: id)) ?? []
    }
}
