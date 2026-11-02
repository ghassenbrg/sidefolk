import Foundation

/// One moment an extension asked Sidefolk to tell the person about (D107). The words are its author's, cleaned and clipped here, and go only
/// to the person: nothing that builds a model's context reads attention items' words (SECURITY T42).
public struct ScheduledOccurrence: Codable, Sendable, Hashable {
    public static let maxPending = 256
    public static let horizon: TimeInterval = 35 * 86400

    public var id: String
    public var at: Date
    public var expiresAt: Date
    public var title: String
    public var body: String?
    /// A new one of a group takes the last one's place on screen, so unanswered notices of one kind don't pile up.
    public var group: String?
    public var systemFallback: Bool
    public var openPage: String?
    public var openState: [String: JSONValue]?

    /// Reads `{id, at, expires_at, title, body, group, system_fallback, open: {page, state}}`. Nil for one that breaks a rule: never half of it.
    static func parse(_ j: JSONValue, pages: Set<String>) -> ScheduledOccurrence? {
        guard let id = j["id"]?.stringValue, id.range(of: #"^[a-z0-9._:-]{1,120}$"#, options: .regularExpression) != nil,
              let at = date(j["at"]), let title = ExtensionPage.text(j["title"], 120) else { return nil }
        let expires = date(j["expires_at"]) ?? at.addingTimeInterval(30 * 60)
        guard expires > at else { return nil }
        var open: String?
        var state: [String: JSONValue]?
        if let page = j["open"]?["page"]?.stringValue, pages.contains(page) {
            open = page
            let wanted = j["open"]?["state"]?.objectValue
            if JSONValue.object(wanted ?? [:]).jsonString.utf8.count <= 1024 { state = wanted }
        }
        return ScheduledOccurrence(id: id, at: at, expiresAt: expires, title: title, body: ExtensionPage.text(j["body"], 240),
                                   group: j["group"]?.stringValue.flatMap { $0.range(of: #"^[a-z0-9._:-]{1,60}$"#, options: .regularExpression) != nil ? $0 : nil },
                                   systemFallback: j["system_fallback"]?.boolValue ?? false, openPage: open, openState: state)
    }

    private static func date(_ j: JSONValue?) -> Date? {
        guard let text = j?.stringValue else { return nil }
        let plain = ISO8601DateFormatter()
        if let found = plain.date(from: text) { return found }
        plain.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: text)
    }
}

/// What one extension has scheduled, kept across launches: its plan, what was told and may still be on screen, what is over so it never comes
/// again, and what was left to macOS while Sidefolk was off.
public struct ExtensionOccurrenceFile: Codable, Sendable, Equatable {
    /// One that was told, for as long as it is worth showing.
    public struct Shown: Codable, Sendable, Equatable {
        public var expiresAt: Date
        public var group: String?
        public var openPage: String?
        public var openState: [String: JSONValue]?
    }

    public var revision = 0
    public var pending: [ScheduledOccurrence] = []
    public var shown: [String: Shown] = [:]
    /// Ids told or missed, with when, kept a while so a later plan can't bring one back.
    public var settled: [String: Date] = [:]
    /// Ids macOS was given at the last quit.
    public var handedOver: [String] = []
    public var missed = 0
    public var toldDay: String?
    public var toldToday = 0

    public init() {}

    mutating func tidy(now: Date) {
        settled = settled.filter { now.timeIntervalSince($0.value) < ScheduledOccurrence.horizon + 86400 }
    }
}

/// In the app's key-value store, one value per extension, so everything that wipes or exports Sidefolk's data takes this too.
public struct ExtensionOccurrenceStore: Sendable {
    let kv: KVStore

    public init(_ kv: KVStore) { self.kv = kv }

    private func key(_ id: String) -> String { "extension.occurrences.\(id)" }

    public func load(_ id: String) async -> ExtensionOccurrenceFile {
        (try? await kv.get(key(id), as: ExtensionOccurrenceFile.self)) ?? ExtensionOccurrenceFile()
    }

    public func save(_ file: ExtensionOccurrenceFile, for id: String) async { try? await kv.set(key(id), file) }

    public func remove(_ id: String) async { try? await kv.remove(key(id)) }
}

/// Tells the person about extensions' moments when they come (D107): one timer for the soonest, as `ReminderScheduler` keeps for reminders, so
/// nothing polls and no extension's process has to be awake. After sleep or a restart, what is at most `grace` late is still told; anything older
/// is missed and stays silent, so waking never floods the person. Nothing told once is told again, and a notice is taken back when its time is over.
public actor OccurrenceScheduler {
    /// How late an occurrence may still be told.
    public static let grace: TimeInterval = 120
    /// The most one extension tells in a day: a plan can make up ids without end, the person's patience can't.
    public static let dailyLimit = 64
    static let longestSleep: TimeInterval = 6 * 3600
    /// `refKind` of a notice; the second may also reach the person through macOS while they are away.
    public static let attentionKind = "occurrence"
    public static let systemAttentionKind = "occurrence.system"
    public static let openAction = "open"

    private let store: ExtensionOccurrenceStore
    private let attention: AttentionCenter
    private let events: EventBus
    private let clock: any Clock
    private var files: [String: ExtensionOccurrenceFile] = [:]
    /// What Sidefolk calls each, so a notice can't pass for another extension's or for Sidefolk's own.
    private var names: [String: String] = [:]
    /// Asked at the moment of telling: on, and the person's yes still stands.
    private var mayTell: @Sendable (String) async -> Bool = { _ in true }
    /// Takes the person to an extension's page; the host says how.
    private var opened: (@Sendable (_ extensionId: String, _ page: String, _ state: [String: JSONValue]?) -> Void)?
    private var timer: Task<Void, Never>?
    private var generation = 0
    private var started = false

    public init(store: ExtensionOccurrenceStore, attention: AttentionCenter, events: EventBus, clock: any Clock = SystemClock()) {
        self.store = store
        self.attention = attention
        self.events = events
        self.clock = clock
    }

    public func configure(mayTell: @escaping @Sendable (String) async -> Bool,
                          onOpen: @escaping @Sendable (_ extensionId: String, _ page: String, _ state: [String: JSONValue]?) -> Void) {
        self.mayTell = mayTell
        opened = onOpen
    }

    /// `extensions`: each with its name. Before the attention center restores what was waiting, so a notice past its time doesn't come back.
    public func start(extensions: [(id: String, name: String)]) async {
        guard !started else { return }
        started = true
        let answer: AttentionCenter.ActionHandler = { [weak self] item, actionId in await self?.answer(item: item, actionId: actionId) }
        await attention.onAction(kind: Self.attentionKind, answer)
        await attention.onAction(kind: Self.systemAttentionKind, answer)
        let now = clock.now
        for (id, name) in extensions {
            names[id] = name
            var file = await store.load(id)
            // What macOS was given at the last quit was told, or passed while the Mac was off: never again here.
            let told = file.pending.filter { file.handedOver.contains($0.id) && $0.at <= now }
            for occurrence in told { file.settled[occurrence.id] = occurrence.at }
            file.pending.removeAll { o in told.contains { $0.id == o.id } }
            file.handedOver = []
            await write(file, id)
            await takeBack(id) { $0.value.expiresAt <= now }
        }
        await tick()
    }

    public func stop() {
        started = false
        timer?.cancel()
        timer = nil
        generation += 1
    }

    /// On wake and when the clock or the zone changes.
    public func reschedule() async {
        if started { await tick() }
    }

    public func status(_ id: String) async -> (pending: Int, revision: Int) {
        let file = await file(id)
        return (file.pending.count, file.revision)
    }

    /// Would this plan change anything? If not, nothing need be written or told in History; only its number moves on.
    public func isSame(_ id: String, revision: Int, occurrences: [ScheduledOccurrence]) async -> Bool {
        var file = await file(id)
        guard revision >= file.revision, usable(occurrences, file: &file) == file.pending else { return false }
        file.revision = revision
        await write(file, id)
        return true
    }

    /// The whole plan, at once. An older revision is refused, so a plan overtaken on its way here can't undo a newer one. What was told stays told, and
    /// a moment already gone isn't added, beyond `grace`. How many are pending now, or nil when it was refused.
    @discardableResult
    public func replace(_ id: String, name: String, revision: Int, occurrences: [ScheduledOccurrence]) async -> Int? {
        names[id] = name
        var file = await file(id)
        guard revision >= file.revision else { return nil }
        file.pending = usable(occurrences, file: &file)
        file.revision = revision
        await write(file, id)
        await tick()
        return file.pending.count
    }

    private func usable(_ occurrences: [ScheduledOccurrence], file: inout ExtensionOccurrenceFile) -> [ScheduledOccurrence] {
        let now = clock.now
        file.tidy(now: now)
        var seen = Set<String>()
        var kept: [ScheduledOccurrence] = []
        for occurrence in occurrences.sorted(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            guard seen.insert(occurrence.id).inserted, file.settled[occurrence.id] == nil,
                  occurrence.at <= now.addingTimeInterval(ScheduledOccurrence.horizon),
                  now.timeIntervalSince(occurrence.at) <= Self.grace, occurrence.expiresAt > now else { continue }
            kept.append(occurrence)
            if kept.count == ScheduledOccurrence.maxPending { break }
        }
        return kept
    }

    /// Everything of one extension still to come goes, and what it said that is still up: off, or the person took back their yes. Its revision
    /// stays, so a plan sent before this can't bring them back.
    public func cancel(_ id: String) async {
        var file = await file(id)
        file.pending = []
        await write(file, id)
        await takeBack(id) { _ in true }
        await tick()
    }

    /// The extension is gone: nothing of it stays, its numbering included.
    public func forget(_ id: String) async {
        await takeBack(id) { _ in true }
        files[id] = nil
        names[id] = nil
        await store.remove(id)
        await tick()
    }

    /// What macOS should tell the person while Sidefolk is off, soonest first, for moments the extension marked for it and where the person
    /// hasn't kept this extension off the desktop. Noted, so the next launch doesn't tell them again.
    public func fallbackNotifications(horizon: TimeInterval = 7 * 86400, limit: Int = 20) async -> [FallbackNotification] {
        let now = clock.now
        let route = await attention.environment.interruptions
        var out: [(extensionId: String, occurrence: ScheduledOccurrence)] = []
        for (id, file) in files {
            guard case .deliver = route.route(level: .attention, source: "extension:\(id)", refKind: Self.systemAttentionKind, refId: nil), await mayTell(id) else { continue }
            out += file.pending.filter { $0.systemFallback && $0.at > now && $0.at <= now.addingTimeInterval(horizon) }.map { (id, $0) }
        }
        let chosen = out.sorted { $0.occurrence.at < $1.occurrence.at }.prefix(limit)
        for id in files.keys {
            guard var file = files[id] else { continue }
            file.handedOver = chosen.filter { $0.extensionId == id }.map(\.occurrence.id)
            await write(file, id)
        }
        return chosen.map { FallbackNotification(id: "occurrence-\($0.extensionId)-\($0.occurrence.id)", title: $0.occurrence.title, body: words($0.occurrence, id: $0.extensionId), date: $0.occurrence.at) }
    }

    // MARK: The timer

    /// Tells what is due and takes back what is over, then sleeps until the next of either.
    public func tick() async {
        let now = clock.now
        for id in files.keys.sorted() {
            guard var file = files[id] else { continue }
            let due = file.pending.filter { $0.at <= now }
            let allowed = due.isEmpty ? false : await mayTell(id)
            for occurrence in due {
                file.settled[occurrence.id] = now
                let day = String(ISO8601DateFormatter().string(from: now).prefix(10))
                if file.toldDay != day {
                    file.toldDay = day
                    file.toldToday = 0
                }
                // Too late to be any use, past its own end, or no longer allowed: gone without a word.
                guard allowed, now.timeIntervalSince(occurrence.at) <= Self.grace, occurrence.expiresAt > now, file.toldToday < Self.dailyLimit else {
                    file.missed += 1
                    continue
                }
                file.toldToday += 1
                if let group = occurrence.group {
                    for (other, shown) in file.shown where shown.group == group {
                        await attention.withdraw(refKind: Self.kind(systemFallback: true), refId: "\(id)/\(other)")
                        await attention.withdraw(refKind: Self.kind(systemFallback: false), refId: "\(id)/\(other)")
                        file.shown[other] = nil
                    }
                }
                file.shown[occurrence.id] = .init(expiresAt: occurrence.expiresAt, group: occurrence.group, openPage: occurrence.openPage, openState: occurrence.openState)
                await tell(occurrence, id: id)
            }
            if !due.isEmpty {
                file.pending.removeAll { $0.at <= now }
                await write(file, id)
            }
            await takeBack(id) { $0.value.expiresAt <= now }
        }
        arm()
    }

    private func arm() {
        timer?.cancel()
        generation += 1
        let mine = generation
        let times = files.values.flatMap(\.pending).map(\.at) + files.values.flatMap(\.shown.values).map(\.expiresAt)
        guard started, let soonest = times.min() else { return }
        let wait = min(Self.longestSleep, max(0, soonest.timeIntervalSince(clock.now)))
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait), tolerance: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.woke(mine)
        }
    }

    private func woke(_ mine: Int) async {
        guard mine == generation else { return }
        await tick()
    }

    private static func kind(systemFallback: Bool) -> String { systemFallback ? systemAttentionKind : attentionKind }

    private func tell(_ occurrence: ScheduledOccurrence, id: String) async {
        let open = occurrence.openPage.map { _ in AttentionAction(id: Self.openAction, title: String(localized: "Open", comment: "A reminder from an extension: opens its page")) }
        // A source of its own: the person's ceilings for this extension, Focus and Quiet all apply (D88).
        await attention.post(AttentionRequest(level: .attention, source: "extension:\(id)", title: occurrence.title, body: words(occurrence, id: id),
                                              actions: open.map { [$0] } ?? [], refKind: Self.kind(systemFallback: occurrence.systemFallback), refId: "\(id)/\(occurrence.id)"))
    }

    /// Its body under its name, always: the title is the extension's to choose, so the name is what says it isn't Sidefolk's or another's.
    private func words(_ occurrence: ScheduledOccurrence, id: String) -> String {
        let name = names[id] ?? id
        guard let body = occurrence.body else { return name }
        return "\(name) · \(body)"
    }

    private func takeBack(_ id: String, _ which: (Dictionary<String, ExtensionOccurrenceFile.Shown>.Element) -> Bool) async {
        guard var file = files[id] else { return }
        let over = file.shown.filter(which)
        guard !over.isEmpty else { return }
        for other in over.keys {
            await attention.withdraw(refKind: Self.kind(systemFallback: true), refId: "\(id)/\(other)")
            await attention.withdraw(refKind: Self.kind(systemFallback: false), refId: "\(id)/\(other)")
            file.shown[other] = nil
        }
        await write(file, id)
    }

    private func answer(item: AttentionItem, actionId: String) async {
        guard let refId = item.refId, let slash = refId.firstIndex(of: "/") else { return }
        let id = String(refId[..<slash]), occurrence = String(refId[refId.index(after: slash)...])
        guard var file = files[id], let shown = file.shown[occurrence] else { return }
        file.shown[occurrence] = nil
        await write(file, id)
        if actionId == Self.openAction, let page = shown.openPage { opened?(id, page, shown.openState) }
    }

    private func file(_ id: String) async -> ExtensionOccurrenceFile {
        if let kept = files[id] { return kept }
        let loaded = await store.load(id)
        files[id] = loaded
        return loaded
    }

    private func write(_ file: ExtensionOccurrenceFile, _ id: String) async {
        files[id] = file
        await store.save(file, for: id)
    }
}
