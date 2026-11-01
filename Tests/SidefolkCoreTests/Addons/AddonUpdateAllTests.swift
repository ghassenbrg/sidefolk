import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// Update all (D89): every update that asks for nothing new installs, one that would let an extension do more stays
/// for review, a failure in the middle keeps its old copy and lets the rest go on, and a version this Sidefolk can't
/// run is never offered. Also when updates that wait earn a whisper.
@Suite struct AddonUpdateAllTests {
    typealias Gallery = AddonStoreTests.Gallery

    /// Publishes extension `id` at `version`, keeping the gallery's other entries.
    static func publish(_ g: Gallery, _ id: String, _ version: String, permissions: JSONValue = .object([:]), note: String = "",
                        minimum: String? = nil, keepOlder: Bool = false) throws {
        let name = String(id.split(separator: ".").last!)
        var manifest = ExtFixtures.manifest(id: id, permissions: permissions, extra: ["name": .string(name.capitalized)])
        if case .object(var o) = manifest { o["version"] = .string(version); manifest = .object(o) }
        let made = try g.pack(name, id: id, version: version,
                              files: [ExtensionManifest.fileName: manifest.jsonString, "server.py": ExtFixtures.server + note])
        if !keepOlder { g.entries.removeAll { $0["id"] as? String == id } }
        var entry: [String: Any] = ["id": id, "kind": "extension", "name": name.capitalized, "tagline": "A test extension",
                                    "description": "", "author": "Sidefolk", "version": version, "file": made.file,
                                    "bytes": made.bytes, "sha256": made.sha]
        if let minimum { entry["minimum_sidefolk"] = minimum }
        g.entries.append(entry)
    }

    static let alpha = "dev.sidefolk.alpha", beta = "dev.sidefolk.beta"

    /// Alpha, Beta and the companion Otter at 1.0.0 on this Mac, installed from the gallery.
    static func scene() async throws -> (Gallery, HostEnv, AddonUpdater) {
        let g = try Gallery(), h = try HostEnv()
        try publish(g, alpha, "1.0.0")
        try publish(g, beta, "1.0.0")
        try g.companion("otter")
        try g.publish()
        let catalog = try await g.store.catalog()
        for id in [alpha, beta] {
            let entry = try #require(catalog.entry(id))
            try await h.host.install(from: try await g.store.fetch(entry), origin: .official)
            await g.store.discard(entry)
        }
        try await g.store.install(companion: try #require(catalog.companion("otter")))
        return (g, h, AddonUpdater(store: g.store, extensions: h.host, themes: ThemeLibrary(paths: g.paths)))
    }

    /// What each row heard, in order.
    final class Steps: Sendable {
        private let all = Mutex<[String]>([])
        func add(_ entry: AddonEntry, _ step: AddonUpdateStep) {
            let word = switch step {
            case .updating: "updating"
            case .updated: "updated"
            case .needsReview: "review"
            case .failed: "failed"
            }
            all.withLock { $0.append("\(entry.name) \(word)") }
        }
        var list: [String] { all.withLock { $0 } }
    }

    @Test(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
    func updateAllInstallsWhatAsksForNothingNewAndLeavesTheRestForReview() async throws {
        let (g, h, updater) = try await Self.scene()
        try Self.publish(g, Self.alpha, "1.1.0", note: "\n# a fix\n")
        try Self.publish(g, Self.beta, "1.1.0", permissions: ["exec": ["/usr/bin/true"]])
        try g.companion("otter", version: "1.1.0")
        try g.publish()
        _ = try await g.store.catalog(refresh: true)

        // The switch is off: everything waits, and Update all is the person's click.
        let waiting = await updater.run(channel: .releases, automatic: false).waiting
        #expect(Set(waiting.map(\.id)) == ["dev.sidefolk.companions.otter", Self.alpha, Self.beta])
        let steps = Steps()
        let report = await updater.updateAll(waiting) { steps.add($0, $1) }

        #expect(report.companions.map(\.version) == ["1.1.0"])
        #expect(report.extensions.map(\.id) == [Self.alpha])
        #expect(report.review.map(\.id) == [Self.beta])
        #expect(report.failed.isEmpty)
        #expect(report.summary == "2 updated, 1 needs your review")
        #expect(await h.host.info(id: Self.alpha)?.version == "1.1.0")
        #expect(await h.host.info(id: Self.beta)?.version == "1.0.0", "a widening update waits for the install sheet")
        #expect(steps.list.count == 6 && steps.list.contains("Beta review") && steps.list.contains("Alpha updated"))
        for entry in waiting { #expect(steps.list.firstIndex(of: "\(entry.name) updating")! < steps.list.count - 1) }

        // Nothing more installs by itself afterwards: Beta still waits, for review.
        let after = await updater.run(channel: .releases, automatic: true)
        #expect(after.installed == 0 && after.review.map(\.id) == [Self.beta])
        await h.host.shutdown()
    }

    @Test(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
    func aFailureInTheMiddleKeepsItsOldCopyAndTheRestGoOn() async throws {
        let (g, h, updater) = try await Self.scene()
        try Self.publish(g, Self.alpha, "1.1.0", note: "\n# a fix\n")
        try g.companion("otter", version: "1.1.0")
        // Beta's new pack isn't what the catalog says it is: its check fails.
        try Self.publish(g, Self.beta, "1.1.0", note: "\n# a fix\n")
        let beta = try #require(g.entries.firstIndex { $0["id"] as? String == Self.beta })
        g.entries[beta]["sha256"] = String(repeating: "0", count: 64)
        try g.publish()
        _ = try await g.store.catalog(refresh: true)

        let waiting = await updater.run(channel: .releases, automatic: false).waiting
        // Beta in the middle.
        let ordered = [Self.alpha, Self.beta, "dev.sidefolk.companions.otter"].compactMap { id in waiting.first { $0.id == id } }
        #expect(ordered.count == 3)
        let steps = Steps()
        let report = await updater.updateAll(ordered) { steps.add($0, $1) }
        #expect(report.failed.map(\.id) == [Self.beta])
        #expect(report.installed == 2)
        #expect(report.summary == "2 updated, 1 couldn't update")
        #expect(steps.list.contains("Beta failed"))
        #expect(await h.host.info(id: Self.beta)?.version == "1.0.0")
        #expect(await h.host.info(id: Self.alpha)?.version == "1.1.0")
        #expect(await g.store.installedCompanions().first?.version == "1.1.0")
        await h.host.shutdown()
    }

    /// An older Sidefolk never sees a version that needs a newer one (D83): Update all takes the newest it can run.
    @Test(.enabled(if: ExtFixtures.hasPython, ExtFixtures.noPython))
    func aVersionThatNeedsANewerSidefolkIsNeverOffered() async throws {
        let (g, h, updater) = try await Self.scene()
        try Self.publish(g, Self.alpha, "1.1.0", note: "\n# runs here\n")
        try Self.publish(g, Self.alpha, "1.2.0", note: "\n# needs more\n", minimum: "9.0.0", keepOlder: true)
        try Self.publish(g, Self.beta, "1.1.0", note: "\n# needs the next version\n", minimum: "0.2.0")
        try g.publish()
        _ = try await g.store.catalog(refresh: true)

        let waiting = await updater.run(channel: .releases, automatic: false).waiting
        #expect(waiting.map(\.version) == ["1.1.0"] && waiting.map(\.id) == [Self.alpha])
        let report = await updater.updateAll(waiting)
        #expect(report.summary == "1 updated")
        #expect(await h.host.info(id: Self.alpha)?.version == "1.1.0")
        #expect(await h.host.info(id: Self.beta)?.version == "1.0.0")
        #expect(await updater.run(channel: .snapshots, automatic: false).waiting.isEmpty, "nothing left this copy can run")
        await h.host.shutdown()
    }

    @Test func theSummarySaysOnlyWhatHappened() {
        var report = AddonUpdateReport()
        #expect(report.summary == nil)
        report.review = [Self.entry("a")]
        #expect(report.summary == "1 needs your review")
        report.failed = [Self.entry("b"), Self.entry("c")]
        #expect(report.summary == "1 needs your review, 2 couldn't update")
    }

    static func entry(_ name: String, version: String = "1.1.0") -> AddonEntry {
        let json: [String: Any] = ["id": "dev.sidefolk.\(name)", "kind": "extension", "name": name, "tagline": "", "description": "",
                                   "author": "Sidefolk", "version": version, "file": "x.zip", "bytes": 1,
                                   "sha256": String(repeating: "0", count: 64)]
        return try! JSONDecoder().decode(AddonEntry.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: The whisper

    @Test func updatesThatWaitADayEarnOneWhisper() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var nudge = AddonUpdateNudge()
        nudge.note([Self.entry("git"), Self.entry("feeds")], now: start)
        func due(after hours: Double, automatic: Bool = false) -> Bool {
            nudge.due(automatic: automatic, now: start.addingTimeInterval(hours * 3600))
        }
        #expect(!due(after: 23), "not yet a day")
        #expect(!due(after: 25, automatic: true), "they install by themselves")
        #expect(due(after: 25))
        #expect(!due(after: 49), "once")

        // A later update waits its own day; then one whisper again, for all of them.
        nudge.note([Self.entry("git"), Self.entry("feeds"), Self.entry("pdf")], now: start.addingTimeInterval(30 * 3600))
        #expect(!due(after: 40))
        #expect(due(after: 55))

        // An update installed is forgotten; a newer version of it is new.
        nudge.note([Self.entry("git", version: "1.2.0")], now: start.addingTimeInterval(60 * 3600))
        #expect(nudge.seen.keys.sorted() == ["dev.sidefolk.git@1.2.0"] && nudge.told.isEmpty)
    }

    /// Its whispers are a source of their own in Settings › Attention (D88), gentle unless the person says otherwise.
    @Test func addOnUpdatesAreASourceOfTheirOwn() {
        #expect(InterruptSource.of(source: "addons", refKind: "addon-updates", refId: nil) == [.addonUpdates])
        #expect(InterruptSource(key: InterruptSource.addonUpdates.key) == .addonUpdates)
        #expect(InterruptSource.addonUpdates.defaultLevel == .whisper)
        #expect(InterruptSource.addonUpdates.choices.contains(.off))
    }
}
