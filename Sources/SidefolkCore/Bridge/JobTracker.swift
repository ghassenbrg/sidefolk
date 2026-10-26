import Darwin
import Foundation

/// A command started with `sidefolk run`, as the helper reports it. The helper runs the command
/// itself, in the caller's process and sandbox; the app only records start and end (T4).
public struct JobReport: Sendable, Equatable {
    public var id: String?
    public var title: String
    public var command: String?
    public var cwd: String?
    public var pid: Int?
    public var exitCode: Int?
    public var signal: Int?
    public var durationSeconds: Double?
    /// The last lines a failed command printed to stderr (at most three, one line each). Written by
    /// the command, so it is only ever shown to the user.
    public var errorTail: String?

    public init(id: String? = nil, title: String, command: String? = nil, cwd: String? = nil, pid: Int? = nil,
                exitCode: Int? = nil, signal: Int? = nil, durationSeconds: Double? = nil, errorTail: String? = nil) {
        self.id = id
        self.title = title
        self.command = command
        self.cwd = cwd
        self.pid = pid
        self.exitCode = exitCode
        self.signal = signal
        self.durationSeconds = durationSeconds
        self.errorTail = errorTail
    }

    public var json: JSONValue {
        var o: [String: JSONValue] = ["title": .string(title)]
        o["id"] = id.map(JSONValue.string)
        o["command"] = command.map(JSONValue.string)
        o["cwd"] = cwd.map(JSONValue.string)
        o["pid"] = pid.map { .number(Double($0)) }
        o["exit_code"] = exitCode.map { .number(Double($0)) }
        o["signal"] = signal.map { .number(Double($0)) }
        o["duration_seconds"] = durationSeconds.map(JSONValue.number)
        o["error_tail"] = errorTail.map(JSONValue.string)
        return .object(o)
    }

    /// Validates and caps a report received over the socket.
    public init?(json: JSONValue) {
        guard let title = json.string("title") else { return nil }
        self.title = SessionEvent.oneLine(title, 80)
        id = json.string("id").flatMap { $0.count <= 64 && $0.allSatisfy { $0.isLetter || $0.isNumber } ? $0 : nil }
        command = json.string("command").map { SessionEvent.oneLine($0, 500) }
        cwd = json.string("cwd").flatMap { $0.hasPrefix("/") && $0.utf8.count <= 1024 && !$0.contains("\0") ? $0 : nil }
        pid = json["pid"]?.intValue.flatMap { $0 > 1 && $0 < Int(Int32.max) ? $0 : nil }
        exitCode = json["exit_code"]?.intValue.flatMap { (0...255).contains($0) ? $0 : nil }
        signal = json["signal"]?.intValue.flatMap { (1...64).contains($0) ? $0 : nil }
        durationSeconds = json["duration_seconds"]?.doubleValue.flatMap { $0.isFinite && $0 >= 0 && $0 < 365 * 86400 ? $0 : nil }
        let tail = (json.string("error_tail") ?? "").components(separatedBy: "\n").suffix(3)
            .map { SessionEvent.oneLine($0, 160) }.filter { !$0.isEmpty }
        errorTail = tail.isEmpty ? nil : tail.joined(separator: "\n")
    }
}

/// Records `sidefolk run` jobs and tells the user how they ended.
public actor JobTracker {
    /// Jobs shorter than this only get a gentle notice: you were probably still watching.
    public static let shortJob: TimeInterval = 10

    private let store: JobStore
    private let attention: AttentionCenter
    private let events: EventBus
    private let clock: any Clock

    public init(store: JobStore, attention: AttentionCenter, events: EventBus, clock: any Clock = SystemClock()) {
        self.store = store
        self.attention = attention
        self.events = events
        self.clock = clock
    }

    public func start(_ r: JobReport, client: String) async -> Job {
        let job = Job(kind: .command, title: r.title, command: r.command, cwd: r.cwd, pid: r.pid, source: "external:\(client)",
                      now: clock.now)
        try? await store.save(job)
        events.changed(.runs)
        return job
    }

    /// Ends a job. A report without a known id (the app started while the command ran) is recorded
    /// as a finished job of its own.
    @discardableResult
    public func finish(_ r: JobReport, client: String) async -> Job {
        let now = clock.now
        var known: Job?
        if let id = r.id { known = try? await store.job(id: id) }
        var job = known ?? Job(kind: .command, title: r.title, command: r.command, cwd: r.cwd, pid: r.pid, source: "external:\(client)",
                               now: now.addingTimeInterval(-(r.durationSeconds ?? 0)))
        guard job.state == .running else { return job }
        let duration = r.durationSeconds ?? now.timeIntervalSince(job.startedAt)
        job.endedAt = now
        job.exitCode = r.exitCode
        job.outputTail = r.errorTail
        job.state = r.signal != nil ? .cancelled : (r.exitCode == 0 ? .succeeded : .failed)
        try? await store.save(job)
        events.changed(.runs)
        await attention.post(Self.notice(for: job, duration: duration, signal: r.signal))
        return job
    }

    /// Marks running jobs whose process is gone (the helper was killed) as cancelled. Run at launch.
    @discardableResult
    public func reconcile() async -> Int {
        let running = (try? await store.running()) ?? []
        var count = 0
        for var job in running where job.pid.map({ kill(pid_t($0), 0) != 0 && errno == ESRCH }) ?? true {
            job.state = .cancelled
            job.endedAt = clock.now
            try? await store.save(job)
            count += 1
        }
        if count > 0 { events.changed(.runs) }
        return count
    }

    static func notice(for job: Job, duration: TimeInterval, signal: Int?) -> AttentionRequest {
        let took = formatDuration(duration)
        let title: String
        switch job.state {
        case .succeeded: title = String(localized: "\(job.title) finished after \(took)", comment: "A command, then how long it ran: “npm test finished after 3 min”")
        case .cancelled: title = String(localized: "\(job.title) was stopped after \(took)")
        default: title = String(localized: "\(job.title) failed (exit \(job.exitCode ?? -1))")
        }
        let quiet = duration < shortJob || job.state == .cancelled
        guard job.state == .failed else {
            return AttentionRequest(level: quiet ? .gentle : .attention, source: "job", title: title,
                                    actions: quiet ? [] : [AttentionAction(id: "dismiss", title: String(localized: "Dismiss"), isPrimary: true)],
                                    refKind: "job", refId: job.id)
        }
        // A failure says what it printed last, when, and where, with the two things you'd do next.
        let when: String
        switch (duration < 1, job.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }) {
        case (true, nil): when = String(localized: "Right away")
        case (true, let folder?): when = String(localized: "Right away in \(folder)")
        case (false, nil): when = String(localized: "After \(took)")
        case (false, let folder?): when = String(localized: "After \(took) in \(folder)")
        }
        let body = [job.outputTail, when].compactMap { $0 }.joined(separator: "\n")
        var actions: [AttentionAction] = []
        if job.command != nil { actions.append(AttentionAction(id: "copy", title: String(localized: "Copy command"), isPrimary: true)) }
        if job.cwd != nil { actions.append(AttentionAction(id: "open", title: String(localized: "Open folder"))) }
        return AttentionRequest(level: quiet ? .gentle : .attention, source: "job", title: title, body: body,
                                actions: actions, refKind: "job", refId: job.id)
    }

    /// "4m 12s", "12s", "1h 3m", in the app's language.
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let units: Set<Duration.UnitsFormatStyle.Unit> = s < 3600 ? [.minutes, .seconds] : [.hours, .minutes]
        return Duration.seconds(s).formatted(.units(allowed: units, width: .narrow).locale(Wording.locale))
    }
}
