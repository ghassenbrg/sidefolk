import Foundation

/// What the person chose about updates (Settings › General › Updates, D46).
public struct UpdateSettings: Codable, Sendable, Equatable {
    /// Look once a day (and a minute after launch) without being asked.
    public var automatic = true
    /// nil follows the build that runs: a snapshot looks for snapshots too, a release for releases only.
    public var channel: UpdateChannel?
    /// "Skip This Version": never offered again; a newer one is.
    public var skipped: ReleaseVersion?

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decode(Bool.self, forKey: .automatic) { automatic = v }
        channel = try? c.decodeIfPresent(UpdateChannel.self, forKey: .channel)
        skipped = try? c.decodeIfPresent(ReleaseVersion.self, forKey: .skipped)
    }

    public func channel(running: ReleaseVersion) -> UpdateChannel {
        channel ?? (running.isPrerelease ? .snapshots : .releases)
    }
}
