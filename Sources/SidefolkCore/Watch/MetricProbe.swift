import Foundation
import Synchronization

/// A value the Mac can report about itself.
public enum Metric: String, CaseIterable, Sendable {
    case cpu, memory, battery, disk, network

    /// The report's name, in the person's language.
    var title: String {
        switch self {
        case .cpu: String(localized: "CPU")
        case .memory: String(localized: "metric.memory", defaultValue: "Memory", comment: "The Mac's memory (RAM) in use, as a live value; not Sidefolk's memory of you")
        case .battery: String(localized: "Battery")
        case .disk: String(localized: "Free disk")
        case .network: String(localized: "Network")
        }
    }
}

/// Reports a system metric (CPU, memory, battery, free disk, network speed) at every check: always a reading,
/// never a notice. Readings that are rates (CPU, network) compare with the previous sample, kept in memory.
public struct MetricProbe: WatcherProbe {
    public let kind = WatchKind.metric
    public var defaultInterval: TimeInterval { 60 }
    public var minimumInterval: TimeInterval { ReportFloors.metric }

    let system: any SystemSampling
    let samples = Samples()
    /// How long a first look waits between its two samples, so its very first rate is a real one.
    let settle: TimeInterval

    public init(system: any SystemSampling = MacSampler(), settle: TimeInterval = 1) {
        self.system = system
        self.settle = settle
    }

    public func prepare(_ watcher: Watcher) throws -> Watcher {
        guard let metric = watcher.config.string("metric").flatMap({ Metric(rawValue: $0.lowercased()) }) else {
            throw WatchError.invalid(String(localized: "Tell me which value to show: CPU, memory, battery, disk or network."))
        }
        var w = watcher
        w.mode = .report
        w.config = Report.options(of: w.config).setting("metric", .string(metric.rawValue))
        w.condition = .object([:])
        return w
    }

    public func check(_ w: Watcher, now: Date) async throws -> ProbeResult {
        guard let metric = w.config.string("metric").flatMap(Metric.init(rawValue:)) else {
            throw ProbeError.invalid(String(localized: "This report doesn't say what to show."))
        }
        return ProbeResult(state: .object([:]), reading: try await read(metric))
    }

    private func read(_ metric: Metric) async throws -> ReadingText {
        switch metric {
        case .cpu:
            let (d, _) = try await change("cpu") { system.cpuTicks().map { [$0.busy, $0.total] } }
            let share = d[1] == 0 ? 0 : min(1, Double(d[0]) / Double(d[1]))
            return ReadingText(shown: Self.percent(share), forModel: "\(Int((share * 100).rounded()))%")
        case .memory:
            guard let m = system.memory() else { throw ProbeError.failed(String(localized: "I couldn't read the memory use.")) }
            let used = Report.memory(Int64(m.used)), total = Report.memory(Int64(m.total))
            return ReadingText(shown: String(localized: "\(used) of \(total)", comment: "Memory in use, then all of it: “9.9 GB of 16 GB”"),
                               // Counted the way the pill counts (binary, "24 GB" of RAM), so the model quotes the same numbers.
                               forModel: "\(Self.memoryForModel(m.used)) used of \(Self.memoryForModel(m.total))")
        case .battery:
            guard let b = system.battery() else { throw ProbeError.invalid(String(localized: "This Mac has no battery.")) }
            let level = Self.percent(Double(b.percent) / 100)
            if b.charging { return ReadingText(shown: String(localized: "\(level), charging"), forModel: "\(b.percent)%, charging") }
            if b.onPower { return ReadingText(shown: String(localized: "\(level), on power"), forModel: "\(b.percent)%, on power") }
            return ReadingText(shown: level, forModel: "\(b.percent)%")
        case .disk:
            guard let d = system.disk() else { throw ProbeError.failed(String(localized: "I couldn't read the free disk space.")) }
            return ReadingText(shown: String(localized: "\(Wording.bytes(d.free)) free"), forModel: "\(ToolFormat.bytes(d.free)) free")
        case .network:
            let (d, seconds) = try await change("network") { system.networkBytes().map { [$0.received, $0.sent] } }
            let down = Int64(Double(d[0]) / seconds), up = Int64(Double(d[1]) / seconds)
            return ReadingText(shown: String(localized: "↓ \(Wording.bytes(down))/s ↑ \(Wording.bytes(up))/s"),
                               forModel: "down \(ToolFormat.bytes(down))/s, up \(ToolFormat.bytes(up))/s")
        }
    }

    /// "23 %" in the words' language.
    static func percent(_ share: Double) -> String { share.formatted(.percent.precision(.fractionLength(0)).locale(Wording.locale)) }

    static func memoryForModel(_ bytes: UInt64) -> String {
        Int64(clamping: bytes).formatted(ByteCountFormatStyle(style: .memory, locale: Locale(identifier: "en_US")))
    }

    /// How far a counter moved since the last sample of the same series, and over how many seconds. The first time
    /// (or after a long pause, or a counter that went back) it takes a second sample `settle` seconds later.
    private func change(_ series: String, _ sample: () -> [UInt64]?) async throws -> ([UInt64], TimeInterval) {
        func take() throws -> Samples.Sample {
            guard let values = sample() else { throw ProbeError.failed(String(localized: "I couldn't read that from the Mac.")) }
            return Samples.Sample(values: values, at: system.uptime())
        }
        var current = try take()
        var previous = current
        if let last = samples.swap(series, current), Samples.usable(last, then: current) {
            previous = last
        } else {
            try await Task.sleep(for: .seconds(settle))
            current = try take()
            samples.swap(series, current)
        }
        return (zip(current.values, previous.values).map { $0 >= $1 ? $0 - $1 : 0 }, max(current.at - previous.at, 0.001))
    }

    /// The last sample of each series, shared by every watcher of this kind (two CPU reports compare with whichever
    /// looked last, which is still a true rate).
    final class Samples: Sendable {
        struct Sample: Sendable {
            var values: [UInt64]
            var at: TimeInterval
        }

        private let last = Mutex<[String: Sample]>([:])

        /// Stores `sample` and returns the one it replaces.
        @discardableResult
        func swap(_ series: String, _ sample: Sample) -> Sample? {
            last.withLock { table in
                defer { table[series] = sample }
                return table[series]
            }
        }

        /// Recent enough to compare with, and counters that only went up.
        static func usable(_ old: Sample, then new: Sample) -> Bool {
            new.at > old.at && new.at - old.at < 900 && zip(new.values, old.values).allSatisfy { $0 >= $1 }
        }
    }
}
