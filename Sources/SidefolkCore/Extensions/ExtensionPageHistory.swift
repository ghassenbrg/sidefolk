import Foundation

/// The past of every chart on extension pages (D62). A page only says the value now; Sidefolk keeps what it said,
/// so an extension needs no storage of its own, a chart isn't empty when the page opens, and a restarted extension
/// loses nothing. Every value of the last 15 minutes, then one a minute for a day: a few hundred kilobytes for a
/// busy page. Saved under `PageHistory/` at most every five minutes and when Sidefolk quits.
public actor ExtensionPageHistory {
    public struct Point: Sendable, Hashable, Codable {
        public var t: Date
        public var v: Double

        public init(_ t: Date, _ v: Double) {
            self.t = t
            self.v = v
        }
    }

    struct Series: Codable {
        var fine: [Point] = []
        var coarse: [Point] = []
    }

    static let fineSpan: TimeInterval = 15 * 60
    static let coarseStep: TimeInterval = 60
    static let span: TimeInterval = 24 * 60 * 60
    static let maxSeries = 64
    static let saveEvery: TimeInterval = 5 * 60

    private let folder: URL?
    /// By extension id, then `page/chart/key`.
    private var series: [String: [String: Series]] = [:]
    private var loaded: Set<String> = []
    private var dirty: Set<String> = []
    private var lastSave = Date.distantPast

    /// - Parameter folder: where it is kept between launches; nil keeps it in memory only.
    public init(folder: URL?) {
        self.folder = folder
    }

    /// Adds what a page said at `now`: one value per chart series.
    public func record(extensionId: String, page: String, samples: [String: Double], at now: Date) {
        guard !samples.isEmpty else { return }
        load(extensionId)
        var all = series[extensionId] ?? [:]
        for (key, value) in samples.sorted(by: { $0.key < $1.key }) {
            let name = "\(page)/\(key)"
            guard all[name] != nil || all.count < Self.maxSeries else { continue }
            var s = all[name] ?? Series()
            s.fine.append(Point(now, value))
            s.fine.removeAll { now.timeIntervalSince($0.t) > Self.fineSpan }
            if let last = s.coarse.last, now.timeIntervalSince(last.t) < Self.coarseStep {
                // Within the minute: the minute keeps its highest value, so a spike still shows a day later.
                if value > last.v { s.coarse[s.coarse.count - 1].v = value }
            } else {
                s.coarse.append(Point(now, value))
            }
            s.coarse.removeAll { now.timeIntervalSince($0.t) > Self.span }
            all[name] = s
        }
        series[extensionId] = all
        dirty.insert(extensionId)
        if now.timeIntervalSince(lastSave) > Self.saveEvery { save(now: now) }
    }

    /// One chart series over the last `window` seconds, oldest first: every value for a short window, one a minute
    /// for a long one.
    public func points(extensionId: String, page: String, key: String, window: TimeInterval, now: Date) -> [Point] {
        load(extensionId)
        guard let s = series[extensionId]?["\(page)/\(key)"] else { return [] }
        let from = now.addingTimeInterval(-window)
        let source = window <= Self.fineSpan ? s.fine : s.coarse
        return source.filter { $0.t >= from }
    }

    /// Forgets an extension's past, when it is removed.
    public func forget(extensionId: String) {
        series[extensionId] = nil
        loaded.insert(extensionId)
        dirty.remove(extensionId)
        if let url = file(extensionId) { try? FileManager.default.removeItem(at: url) }
    }

    /// Writes what changed since the last save.
    public func save(now: Date = Date()) {
        lastSave = now
        guard let folder else { dirty.removeAll(); return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for id in dirty.sorted() {
            guard let url = file(id), let data = try? JSONEncoder().encode(series[id] ?? [:]) else { continue }
            try? data.write(to: url, options: [.atomic])
        }
        dirty.removeAll()
    }

    private func load(_ id: String) {
        guard !loaded.contains(id) else { return }
        loaded.insert(id)
        guard let url = file(id), let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([String: Series].self, from: data) else { return }
        series[id] = stored.merging(series[id] ?? [:]) { _, new in new }
    }

    private func file(_ id: String) -> URL? {
        // Ids are reverse-DNS checked at install; the file name is only ever one of them.
        guard let folder, id.range(of: #"^[a-z0-9]+(\.[a-z0-9-]+)+$"#, options: .regularExpression) != nil else { return nil }
        return folder.appendingPathComponent("\(id).json")
    }
}
