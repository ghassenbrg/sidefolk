import Foundation

// One check of one watcher: run the probe, apply what it found, tell the user if it matters.
extension WatcherEngine {
    /// - Parameter epoch: set when the timer started this check; a `stop()` since then cancels it.
    func runCheck(_ id: String, epoch checkEpoch: Int? = nil) async {
        guard checkEpoch == nil || checkEpoch == epoch else { return }
        guard let w = watchers[id], w.state == .active, !running.contains(id) else { return }
        let now = clock.now
        if let expires = w.expiresAt, expires <= now {
            await expire(id)
            return
        }
        guard let probe = probes[w.kind] else {
            await parkUnknownKind(id)
            return
        }

        running.insert(id)
        let startEpoch = epoch
        let task = Task { try await probe.check(w, now: now) }
        inflight[id] = task
        let outcome = await task.result
        running.remove(id)
        inflight[id] = nil
        // Stopped, removed or paused while the probe was working: what it found is stale.
        guard startEpoch == epoch, var current = watchers[id], current.state == .active else { return }

        let finished = clock.now
        switch outcome {
        case .success(let result): await apply(result, to: &current, probe: probe, at: finished)
        case .failure(let error): await apply(error, to: &current, at: finished)
        }
    }

    // MARK: Results

    func apply(_ result: ProbeResult, to w: inout Watcher, probe: any WatcherProbe, at now: Date) async {
        if lookouts[w.id] != nil { lookouts[w.id] = FirstLook(answered: true, note: result.firstLookNote, reading: result.reading) }
        w.lastState = result.state
        w.lastCheckedAt = now
        w.errorCount = 0
        w.lastError = nil
        w.updatedAt = now
        if w.mode == .report {
            // A report tells every time, in place: the value goes out as an event and waits for the routine save.
            w.nextCheckAt = now.addingTimeInterval(w.intervalS)
            if let reading = result.reading {
                w.lastState = result.state.setting("reading", ["shown": .string(reading.shown)])
                let value = WatchReading(w, value: reading.shown, at: now)
                readings[w.id] = value
                events.publish(.watchReading(value))
            }
            watchers[w.id] = w
            await persist(w)
            return
        }
        if result.triggered {
            w.fireCount += 1
            switch w.mode {
            case .once:
                w.state = .triggered
                w.nextCheckAt = nil
                cooldownUntil[w.id] = nil
            case .repeat, .report:
                // Stay quiet for a while so a page or file that keeps changing does not ring all day.
                let next = now.addingTimeInterval(max(w.intervalS, cooldown(for: w, probe)))
                w.nextCheckAt = next
                cooldownUntil[w.id] = next
            }
            openTargets[w.id] = result.openTarget
        } else {
            let wait = result.recheckIn.map { min(max($0, 2), w.intervalS) } ?? w.intervalS
            w.nextCheckAt = now.addingTimeInterval(wait)
        }
        watchers[w.id] = w
        await persist(w)
        refreshEvents(w)
        if result.triggered { await announce(w, result) }
    }

    func apply(_ error: any Error, to w: inout Watcher, at now: Date) async {
        w.updatedAt = now
        switch error as? ProbeError {
        case .deferred(let until)?:
            // Not a failure: another request to that host went out a moment ago.
            w.nextCheckAt = max(until, now.addingTimeInterval(1))
            watchers[w.id] = w
            await persist(w)
            return
        case .offline?:
            w.nextCheckAt = now.addingTimeInterval(min(w.intervalS, 60))
            watchers[w.id] = w
            await persist(w)
            return
        case .invalid(let why)?:
            // Looking again can't help: stop here and say why, in Now and on the card that confirms a new watcher.
            if lookouts[w.id] != nil { lookouts[w.id] = FirstLook(answered: true, problem: why, final: true) }
            w.state = .error
            w.nextCheckAt = nil
            w.lastCheckedAt = now
            w.lastError = why
            watchers[w.id] = w
            hub?.remove(w.id)
            await persist(w)
            return
        default:
            break
        }

        let reason = Self.reason(for: error)
        if lookouts[w.id] != nil { lookouts[w.id] = FirstLook(answered: true, problem: reason) }
        Log.shared.info("watch", "check failed", ["kind": w.kind, "attempt": "\(w.errorCount + 1)", "reason": reason])
        w.lastCheckedAt = now
        w.errorCount += 1
        w.lastError = reason
        let backoff = min(w.intervalS * pow(2, Double(w.errorCount)), WatchLimits.maxBackoff)
        w.nextCheckAt = now.addingTimeInterval(max(backoff, w.intervalS))
        watchers[w.id] = w
        await persist(w)

        if w.errorCount == WatchLimits.failuresBeforeNotice {
            let shortReason = reason.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercasedFirst
            // Something the person asked to be told about has stopped working: that deserves more than a 6 s whisper.
            await attention.post(AttentionRequest(
                level: .attention, source: "watcher", title: String(localized: "I can't check \(w.title): \(shortReason)"),
                body: String(localized: "I'll keep trying, a little less often each time."),
                actions: [AttentionAction(id: "stop", title: String(localized: "Stop watching"))], refKind: "watcher", refId: w.id))
        }
    }

    static func reason(for error: any Error) -> String {
        switch error {
        case let e as ProbeError: e.description
        case let e as WatchError: e.description
        case let e as URLPolicy.Violation: e.message
        case let e as UserFacingError: e.message
        default: String(localized: "Something went wrong while checking.")
        }
    }

    func cooldown(for w: Watcher, _ probe: any WatcherProbe) -> TimeInterval {
        if let minutes = w.config["cooldown_minutes"]?.doubleValue, minutes >= 0 { return minutes * 60 }
        return probe.repeatCooldown
    }

    // MARK: Telling the user

    func announce(_ w: Watcher, _ result: ProbeResult) async {
        var actions: [AttentionAction] = []
        if result.openTarget != nil { actions.append(AttentionAction(id: "open", title: String(localized: "Open"), isPrimary: true)) }
        if w.mode == .once { actions.append(AttentionAction(id: "keep", title: String(localized: "Keep watching"), isPrimary: actions.isEmpty)) }
        actions.append(AttentionAction(id: "stop", title: String(localized: "Stop")))

        let title = result.summary.displaySafe.clipped(WatchLimits.summaryLimit)
        let body = result.detail?.components(separatedBy: "\n").map(\.displaySafe).filter { !$0.isEmpty }
            .joined(separator: "\n").clipped(WatchLimits.summaryLimit)
        await attention.post(AttentionRequest(
            level: result.level ?? w.level, source: "watcher", title: title.isEmpty ? w.title : title,
            body: body?.isEmpty == false ? body : nil, actions: actions, refKind: "watcher", refId: w.id))
    }

    func expire(_ id: String) async {
        guard var w = watchers[id] else { return }
        let now = clock.now
        w.state = .expired
        w.nextCheckAt = nil
        w.updatedAt = now
        watchers[id] = w
        hub?.remove(id)
        await persist(w)
        if w.mode == .report {
            // Reports end by design (an hour, a day, or when they were told to): say so quietly, offer more.
            let end = TimeFormat.clock(w.expiresAt ?? now, calendar: .autoupdatingCurrent)
            await attention.post(AttentionRequest(
                level: .gentle, source: "watcher", title: String(localized: "I stopped showing \(w.title)"),
                body: String(localized: "It was set to stop at \(end)."),
                actions: [AttentionAction(id: "keep", title: String(localized: "Keep going"), isPrimary: true),
                          AttentionAction(id: "stop", title: String(localized: "Remove"))],
                refKind: "watcher", refId: id))
            return
        }
        let days = max(1, Int(((w.expiresAt ?? now).timeIntervalSince(w.createdAt) / 86400).rounded()))
        await attention.post(AttentionRequest(
            level: .gentle, source: "watcher", title: String(localized: "I stopped watching \(w.title)"),
            body: String(localized: "It's been \(days) days. I can start again if you still want it."),
            actions: [AttentionAction(id: "keep", title: String(localized: "Watch again"), isPrimary: true),
                      AttentionAction(id: "stop", title: String(localized: "Remove"))],
            refKind: "watcher", refId: id))
    }

    func parkUnknownKind(_ id: String) async {
        guard var w = watchers[id] else { return }
        w.state = .error
        w.nextCheckAt = nil
        w.lastError = String(localized: "I don't know how to watch “\(w.kind)” (the extension that provides it may be off).")
        w.updatedAt = clock.now
        watchers[id] = w
        hub?.remove(id)
        await persist(w)
    }

    // MARK: Answers from the notice

    func handleAction(_ item: AttentionItem, _ actionId: String) async {
        await ensureLoaded()
        guard let id = item.refId, let w = watchers[id] else { return }
        switch actionId {
        case "open": await open(w)
        case "keep": _ = try? await resume(id)
        case "stop": _ = await remove(id)
        default: break
        }
    }

    private func open(_ w: Watcher) async {
        guard let target = openTargets[w.id] ?? w.config.string("url") ?? w.config.string("resolved") else { return }
        if target.hasPrefix("https://") || target.hasPrefix("http://") {
            if let url = URL(string: target) { await opener(url) }
        } else if target.hasPrefix("/") {
            // Files that would run when opened show their folder instead.
            await opener(URL(fileURLWithPath: WatchedPath.openable(target)))
        }
    }
}

extension String {
    fileprivate var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
