import Foundation

/// Every location Sidefolk reads or writes. `SIDEFOLK_HOME` moves all of it (tests, dev, QA).
public struct SidefolkPaths: Sendable {
    public let home: URL
    public let logs: URL

    public init(home: URL, logs: URL? = nil) {
        self.home = home
        self.logs = logs ?? home.appendingPathComponent("Logs", isDirectory: true)
    }

    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> SidefolkPaths {
        if let custom = environment["SIDEFOLK_HOME"], !custom.isEmpty {
            return SidefolkPaths(home: URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true))
        }
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return SidefolkPaths(
            home: support.appendingPathComponent("Sidefolk", isDirectory: true),
            logs: library.appendingPathComponent("Logs/Sidefolk", isDirectory: true)
        )
    }

    public var database: URL { home.appendingPathComponent("sidefolk.sqlite") }
    public var extensions: URL { home.appendingPathComponent("Extensions", isDirectory: true) }
    public var extensionData: URL { home.appendingPathComponent("ExtensionData", isDirectory: true) }
    /// Extensions Sidefolk's AI writes for the person, waiting to be reviewed and installed (D39).
    public var extensionDrafts: URL { home.appendingPathComponent("ExtensionDrafts", isDirectory: true) }
    public var skills: URL { home.appendingPathComponent("Skills", isDirectory: true) }
    public var run: URL { home.appendingPathComponent("run", isDirectory: true) }
    public var socket: URL { run.appendingPathComponent("sidefolk.sock") }
    public var brainWorkdir: URL { home.appendingPathComponent("brain", isDirectory: true) }
    /// A new version's disk image while it is downloaded and checked (D46); emptied at launch.
    public var updates: URL { home.appendingPathComponent("Updates", isDirectory: true) }
    /// Companions and the catalog from the add-on gallery (D55).
    public var addons: URL { home.appendingPathComponent("Addons", isDirectory: true) }

    /// Creates the folders with owner-only permissions.
    public func prepare() throws {
        let fm = FileManager.default
        for dir in [home, logs, extensions, extensionData, extensionDrafts, skills, run, brainWorkdir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
    }
}
