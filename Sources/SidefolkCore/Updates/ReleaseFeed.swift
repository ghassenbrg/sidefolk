import Foundation

/// Which releases a person wants (D46): finished releases only, or snapshots too (prereleases made for testing).
public enum UpdateChannel: String, Codable, Sendable, CaseIterable {
    case releases, snapshots

    /// Whether this choice takes `version`: a snapshot only for people who chose snapshots. Add-ons follow the same
    /// choice as Sidefolk itself (D65): on Releases the gallery shows, and updates offer, released versions only.
    public func includes(_ version: String) -> Bool {
        guard let v = ReleaseVersion(version) else { return false }
        return self == .snapshots || !v.isPrerelease
    }

    /// Whether `new` is offered as an update over `old`: newer, and one this choice takes.
    public func offers(_ new: String, over old: String) -> Bool {
        guard let n = ReleaseVersion(new), let o = ReleaseVersion(old), n > o else { return false }
        return includes(new)
    }
}

/// A newer Sidefolk someone could install: one GitHub release with its disk image.
public struct UpdateOffer: Codable, Sendable, Hashable, Identifiable {
    public struct Asset: Codable, Sendable, Hashable {
        public var name: String
        public var size: Int64
        public var url: URL
        /// GitHub's own SHA-256 of the file, in hex, when the API gives one.
        public var sha256: String?

        public init(name: String, size: Int64, url: URL, sha256: String? = nil) {
            self.name = name
            self.size = size
            self.url = url
            self.sha256 = sha256
        }
    }

    public var version: ReleaseVersion
    public var tag: String
    public var title: String
    /// The release notes as written (Markdown).
    public var notes: String
    public var page: URL
    public var published: Date?
    /// Marked as a prerelease, or numbered as one: only for people who chose snapshots.
    public var isSnapshot: Bool
    /// `Sidefolk-<version>.dmg`.
    public var image: Asset
    /// `Sidefolk-<version>.dmg.sha256`, as scripts/package.sh writes it.
    public var checksum: Asset?

    public var id: String { tag }

    public init(version: ReleaseVersion, tag: String, title: String, notes: String, page: URL, published: Date?,
                isSnapshot: Bool, image: Asset, checksum: Asset?) {
        self.version = version
        self.tag = tag
        self.title = title
        self.notes = notes
        self.page = page
        self.published = published
        self.isSnapshot = isSnapshot
        self.image = image
        self.checksum = checksum
    }

    /// The start of the notes as plain sentences, for a bubble: headings (and lines that are only bold, used as
    /// headings) left out, list items as sentences, no marks or links.
    public func summary(limit: Int = 160) -> String? {
        let lines = notes.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            var s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("#") || (s.hasPrefix("**") && s.hasSuffix("**")) { return nil }
            if s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("> ") { s = String(s.dropFirst(2)) }
            s = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
            guard let last = s.last else { return nil }
            return ".!?…:".contains(last) ? s : s + "."
        }
        let text = lines.joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return text.count <= limit ? text : String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Reads GitHub's list of releases (`GET /repos/{owner}/{repo}/releases`) into offers, and picks the one
/// to offer. Anything unexpected in a release (a draft, a tag that isn't a version, a missing or still
/// uploading disk image) leaves that release out rather than failing the whole list.
public enum ReleaseFeed {
    /// Where Sidefolk's releases are published (.github/workflows/release.yml).
    public static let repository = "ghassenbrg/sidefolk"
    public static var source: URL { URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=30")! }

    public static func offers(from data: Data) throws -> [UpdateOffer] {
        let releases = try JSONDecoder.github.decode([GitHubRelease].self, from: data)
        return releases.compactMap(offer).sorted { $0.version > $1.version }
    }

    /// The newest offer for the channel that is newer than what runs and than a skipped version: skipping one
    /// doesn't bring back the older ones it passed over.
    public static func newest(_ offers: [UpdateOffer], channel: UpdateChannel, after running: ReleaseVersion,
                              skipping skipped: ReleaseVersion? = nil) -> UpdateOffer? {
        let floor = max(running, skipped ?? running)
        return offers.filter { (channel == .snapshots || !$0.isSnapshot) && $0.version > floor }.max { $0.version < $1.version }
    }

    static func offer(_ r: GitHubRelease) -> UpdateOffer? {
        guard !r.draft, let version = ReleaseVersion(r.tag_name), let page = URL(string: r.html_url) else { return nil }
        let uploaded = r.assets.filter { $0.state == nil || $0.state == "uploaded" }
        let imageName = "Sidefolk-\(version).dmg"
        guard let image = uploaded.first(where: { $0.name == imageName }).flatMap(asset) else { return nil }
        let checksum = uploaded.first { $0.name == imageName + ".sha256" }.flatMap(asset)
        let title = r.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Sidefolk \(version.shown)"
        return UpdateOffer(version: version, tag: r.tag_name, title: title, notes: r.body ?? "", page: page,
                           published: r.published_at, isSnapshot: r.prerelease || version.isPrerelease,
                           image: image, checksum: checksum)
    }

    /// Only https addresses on GitHub: the download follows them, so a release can't point it elsewhere.
    static func asset(_ a: GitHubRelease.Asset) -> UpdateOffer.Asset? {
        guard let url = URL(string: a.browser_download_url), UpdateDownloader.allowed(url), a.size > 0 else { return nil }
        let digest = a.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
        return UpdateOffer.Asset(name: a.name, size: a.size, url: url, sha256: digest)
    }
}

/// The fields of GitHub's release object Sidefolk reads.
struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        var name: String
        var size: Int64
        var browser_download_url: String
        var state: String?
        var digest: String?
    }

    var tag_name: String
    var name: String?
    var body: String?
    var draft: Bool
    var prerelease: Bool
    var html_url: String
    var published_at: Date?
    var assets: [Asset]
}

extension JSONDecoder {
    /// GitHub's dates are ISO 8601 with no fractional seconds.
    static var github: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
