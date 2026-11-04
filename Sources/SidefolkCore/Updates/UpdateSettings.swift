import Foundation

/// What Sidefolk does about a newer version of itself (Settings › General › Updates, D46, D70).
public enum AppUpdateMode: String, Codable, Sendable, CaseIterable {
    /// Looks only when the person asks (Check Now, "Check for Updates…").
    case off
    /// Looks a minute after launch and daily, and asks before installing (D46).
    case notify
    /// Looks as `notify` does, then downloads, checks and installs by itself at a calm moment (D70).
    case install
}

/// What the person chose about updates (Settings › General › Updates, D46, D70).
public struct UpdateSettings: Codable, Sendable, Equatable {
    /// Sidefolk's own updates. "Tell me" by default: a restart is the person's to allow (D70).
    public var app: AppUpdateMode = .notify
    /// Gallery add-ons update by themselves (D70): companions, themes, and extensions whose update asks for
    /// nothing new. On by default, as companions always did (D55).
    public var addons = true
    /// nil means the person never chose: a snapshot build then follows snapshots, any other build releases only (D191).
    public var channel: UpdateChannel?
    /// "Skip this version": never offered again; a newer one is.
    public var skipped: ReleaseVersion?

    public init() {}

    private enum CodingKeys: String, CodingKey { case app, addons, channel, skipped, automatic }

    /// Settings from before D70 had one switch, `automatic`: off means "Don't check", on means "Tell me".
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decode(AppUpdateMode.self, forKey: .app) {
            app = v
        } else if let v = try? c.decode(Bool.self, forKey: .automatic) {
            app = v ? .notify : .off
        }
        if let v = try? c.decode(Bool.self, forKey: .addons) { addons = v }
        channel = try? c.decodeIfPresent(UpdateChannel.self, forKey: .channel)
        skipped = try? c.decodeIfPresent(ReleaseVersion.self, forKey: .skipped)
    }

    /// `automatic` is written too, so a copy from before D70 (an older snapshot opened again) still knows whether
    /// to look.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(app, forKey: .app)
        try c.encode(addons, forKey: .addons)
        try c.encodeIfPresent(channel, forKey: .channel)
        try c.encodeIfPresent(skipped, forKey: .skipped)
        try c.encode(automatic, forKey: .automatic)
    }

    /// Looks by itself, a minute after launch and daily.
    public var automatic: Bool { app != .off }

    public var effectiveChannel: UpdateChannel { effectiveChannel(running: SidefolkVersion.running) }

    /// What is offered for the build `running` (a version as `SidefolkVersion.running` says it): the person's choice, kept
    /// whatever the build, else snapshots on a snapshot, where nothing is released yet, and releases on a release.
    public func effectiveChannel(running: String) -> UpdateChannel {
        channel ?? (ReleaseVersion(running)?.isPrerelease == true ? .snapshots : .releases)
    }
}
