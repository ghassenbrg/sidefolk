import Foundation
import Synchronization

/// The extensions a fresh Mac starts with (D98), so the first run works offline and the person has something to try.
/// The app carries each as a pack signed like the gallery's, with a data list; it installs them once, from the pack,
/// checked as a download is. From then on they are ordinary gallery extensions: the gallery updates them, removing one
/// is remembered, and an app update never touches them.
public final class SeedPacks: Sendable {
    public static let listFile = "seed-packs.json"
    public static let ledgerFile = "seed-packs.json"

    /// One line of the app's list, as scripts/seed-packs.py wrote it from the signed catalog.
    public struct Seed: Sendable, Hashable, Decodable {
        public var id: String
        public var name: String
        public var version: String
        public var file: String
        public var bytes: Int64
        public var sha256: String
        /// Whether it starts switched on.
        public var on: Bool
    }

    /// A seed that couldn't be installed on this Mac, and why; it is tried again at the next launch or from Settings.
    public struct Problem: Sendable, Hashable {
        public var id: String
        public var name: String
        public var message: String
    }

    /// What is left to install. Its being there at all says this Mac has had its seeds, so nothing new is ever added to
    /// it by an app update, and what the person removed stays gone.
    private struct Ledger: Codable {
        var pending: [String]
    }

    /// `Resources/SeedPacks` in the app.
    public let directory: URL?
    private let ledger: URL
    private let problems = Mutex<[Problem]>([])

    public init(directory: URL?, paths: SidefolkPaths) {
        self.directory = directory
        ledger = paths.addons.appendingPathComponent(Self.ledgerFile)
    }

    /// The packs this copy carries. A build that fetched none (a debug build offline) has an empty list here: the list
    /// in the repository names no files, so it reads as nothing to install.
    public func seeds() -> [Seed] {
        struct List: Decodable { var seeds: [Seed] }
        guard let directory, let data = FileManager.default.contents(atPath: directory.appendingPathComponent(Self.listFile).path) else { return [] }
        return (try? JSONDecoder().decode(List.self, from: data))?.seeds ?? []
    }

    /// Seeds the last `install` couldn't install, for Settings.
    public var unavailable: [Problem] { problems.withLock { $0 } }

    /// Installs what this Mac still has coming. Runs at every launch; once done it reads one small file.
    public func install(into host: ExtensionHost, store: AddonStore) async {
        let seeds = seeds()
        guard !seeds.isEmpty else { return }
        var left = read()?.pending ?? seeds.map(\.id)
        write(Ledger(pending: left))
        var found: [Problem] = []
        for seed in seeds where left.contains(seed.id) {
            // A copy the app shipped before D98 is here already, as the person left it: data, switch and all.
            if await host.info(id: seed.id) == nil {
                do {
                    let folder = try await store.unpack(seed: seed, from: directory)
                    defer { Task { await store.discard(id: seed.id) } }
                    try await host.install(from: folder, origin: .official, enabled: seed.on)
                } catch {
                    let message = (error as? UserFacingError)?.message ?? String(describing: error)
                    found.append(Problem(id: seed.id, name: seed.name, message: message))
                    Log.shared.warning("extensions", "seed pack not installed", ["id": seed.id, "why": message])
                    continue
                }
            }
            left.removeAll { $0 == seed.id }
            write(Ledger(pending: left))
        }
        // Coming only from what this copy carries: a pack it no longer has isn't waited for.
        let carried = Set(seeds.map(\.id))
        write(Ledger(pending: left.filter(carried.contains)))
        problems.withLock { $0 = found }
        host.events.changed(.extensions)
    }

    private func read() -> Ledger? {
        FileManager.default.contents(atPath: ledger.path).flatMap { try? JSONDecoder().decode(Ledger.self, from: $0) }
    }

    private func write(_ value: Ledger) {
        Self.write(value.pending, to: ledger)
    }

    private static func write(_ pending: [String], to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? JSONEncoder().encode(Ledger(pending: pending)).write(to: file, options: .atomic)
    }

    /// The person removed it, however it came: a seed still waiting its turn doesn't come back.
    static func removed(_ id: String, paths: SidefolkPaths) {
        let file = paths.addons.appendingPathComponent(ledgerFile)
        guard let ledger = FileManager.default.contents(atPath: file.path).flatMap({ try? JSONDecoder().decode(Ledger.self, from: $0) }),
              ledger.pending.contains(id) else { return }
        write(ledger.pending.filter { $0 != id }, to: file)
    }

    /// After a restore (D91) this Mac's add-ons are the backup's: of the seeds, only those it had come back, and any
    /// the person had removed there stay gone. The `Addons` folder was just swapped out, so this writes the ledger anew.
    static func restored(_ pending: [String], paths: SidefolkPaths) {
        write(pending, to: paths.addons.appendingPathComponent(ledgerFile))
    }
}
