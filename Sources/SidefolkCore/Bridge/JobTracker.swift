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

    public init(id: String? = nil, title: String, command: String? = nil, cwd: String? = nil, pid: Int? = nil,
                exitCode: Int? = nil, signal: Int? = nil, durationSeconds: Double? = nil) {
        self.id = id
        self.title = title
        self.command = command
        self.cwd = cwd
        self.pid = pid
        self.exitCode = exitCode
        self.signal = signal
        self.durationSeconds = durationSeconds
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
        case .succeeded: title = "\(job.title) finished in \(took)"
        case .cancelled: title = "\(job.title) was stopped after \(took)"
        default: title = "\(job.title) failed (exit \(job.exitCode ?? -1))"
        }
        let body = job.state == .failed ? "After \(took)" + (job.cwd.map { " in \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? "") : nil
        let quiet = duration < shortJob || job.state == .cancelled
        return AttentionRequest(level: quiet ? .gentle : .attention, source: "job", title: title, body: body,
                                actions: quiet ? [] : [AttentionAction(id: "dismiss", title: "Dismiss", isPrimary: true)],
                                refKind: "job", refId: job.id)
    }

    /// "4m 12s", "12s", "1h 3m".
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}
