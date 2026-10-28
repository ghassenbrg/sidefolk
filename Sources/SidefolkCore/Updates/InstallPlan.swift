import Foundation

/// The Sidefolk that is running, as the updater sees it (D46).
public struct RunningApp: Sendable {
    public var bundle: URL
    public var bundleID: String?
    /// The release this copy was published as (Info.plist `SidefolkRelease`, set by scripts/release.sh); nil for
    /// a development or local build.
    public var release: ReleaseVersion?
    public var signing: SigningFacts?
    public var pid: Int32

    public init(bundle: URL, bundleID: String?, release: ReleaseVersion?, signing: SigningFacts?,
                pid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.bundle = bundle
        self.bundleID = bundleID
        self.release = release
        self.signing = signing
        self.pid = pid
    }

    public static func current(_ bundle: Bundle = .main) -> RunningApp {
        RunningApp(bundle: bundle.bundleURL, bundleID: bundle.bundleIdentifier,
                   release: (bundle.object(forInfoDictionaryKey: releaseKey) as? String).flatMap(ReleaseVersion.init),
                   signing: SigningFacts.ofRunningApp())
    }

    public static let releaseKey = "SidefolkRelease"

    /// What offers are compared with. A build that wasn't published counts as an early build of its version
    /// ("0.1.0-dev"), so every release and snapshot of that version reads as newer.
    public var version: ReleaseVersion {
        release ?? ReleaseVersion("\(SidefolkVersion.current)-dev")!
    }
}

/// How an update reaches this copy: it replaces itself, or the disk image waits in Downloads with the reason.
public enum InstallPlan: Equatable, Sendable {
    case replace
    case download(Reason)

    public enum Reason: String, Sendable {
        /// Built on this Mac, not published: replacing it with a release would lose the build.
        case notPublished
        /// Not signed with a Developer ID, so there is no developer for the new version to match.
        case notDeveloperID
        /// macOS runs it from a hidden, read-only copy (App Translocation): it was opened where it was downloaded.
        case translocated
        /// On a read-only volume, such as the disk image it came in.
        case readOnly
        /// Its folder can't be written by this account.
        case notWritable
    }

    /// Where the running copy sits, as far as replacing it goes.
    public struct Place: Equatable, Sendable {
        public var translocated: Bool
        public var readOnlyVolume: Bool
        public var folderWritable: Bool

        public init(translocated: Bool, readOnlyVolume: Bool, folderWritable: Bool) {
            self.translocated = translocated
            self.readOnlyVolume = readOnlyVolume
            self.folderWritable = folderWritable
        }

        public static func of(_ bundle: URL) -> Place {
            let readOnly = (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? true
            return Place(translocated: bundle.path.contains("/AppTranslocation/"), readOnlyVolume: readOnly,
                         folderWritable: access(bundle.deletingLastPathComponent().path, W_OK) == 0)
        }
    }

    public static func decide(_ app: RunningApp, place: Place) -> InstallPlan {
        guard app.release != nil else { return .download(.notPublished) }
        guard app.signing?.replacementRequirement != nil else { return .download(.notDeveloperID) }
        if place.translocated { return .download(.translocated) }
        if place.readOnlyVolume { return .download(.readOnly) }
        if !place.folderWritable { return .download(.notWritable) }
        return .replace
    }
}

extension InstallPlan.Reason {
    /// Why the disk image is in Downloads instead, said to the person.
    public var explanation: String {
        switch self {
        case .notPublished:
            String(localized: "This copy of Sidefolk was built on this Mac, so it doesn't replace itself.",
                   comment: "Why an update is downloaded rather than installed")
        case .notDeveloperID:
            String(localized: "This copy of Sidefolk isn't signed by its developer, so it doesn't replace itself.",
                   comment: "Why an update is downloaded rather than installed")
        case .translocated:
            String(localized: "macOS runs this copy from a protected place because it was opened where it was downloaded.",
                   comment: "Why an update is downloaded rather than installed (App Translocation)")
        case .readOnly:
            String(localized: "This copy runs from a disk that can't be changed, such as the disk image it came in.",
                   comment: "Why an update is downloaded rather than installed")
        case .notWritable:
            String(localized: "Your account can't change the folder Sidefolk is in.",
                   comment: "Why an update is downloaded rather than installed")
        }
    }
}
