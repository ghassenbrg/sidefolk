import Foundation
import Testing
@testable import SidefolkCore

@Suite struct ReleaseVersionTests {
    private func v(_ s: String) -> ReleaseVersion { ReleaseVersion(s)! }

    @Test func snapshotsOrderByNumberAndComeBeforeTheirRelease() {
        #expect(v("0.1.0-snapshot.9") < v("0.1.0-snapshot.411"))
        #expect(v("0.1.0-snapshot.411") < v("0.1.0"))
        #expect(v("0.1.0") < v("0.1.1-snapshot.2"))
        #expect(v("0.1.0") < v("0.2.0"))
        #expect(v("0.9.9") < v("0.10.0"))
        #expect(v("1.0.0-alpha") < v("1.0.0-alpha.1"))
        #expect(v("1.0.0-alpha.1") < v("1.0.0-beta"))
        #expect(v("1.0.0-2") < v("1.0.0-alpha"))   // numbers before words
        // A copy built on this Mac counts as an early build of its version.
        #expect(v("0.1.0-dev") < v("0.1.0-snapshot.1"))
    }

    @Test func readsTagsAndRefusesWhatIsntAVersion() {
        #expect(v("v0.1.0-snapshot.411").description == "0.1.0-snapshot.411")
        #expect(v("0.1").description == "0.1.0")
        #expect(v("1.2.3+build.7") == v("1.2.3"))
        #expect(v("0.1.0-snapshot.411").shown == "0.1.0 snapshot 411")
        for bad in ["", "nightly", "v", "1.2.3.4", "1.-2.0", "1.2.3-", "1.2.3-snap shot", "1..2"] {
            #expect(ReleaseVersion(bad) == nil, "\(bad)")
        }
    }

    @Test func storesAsItsText() throws {
        let data = try JSONEncoder().encode([v("0.1.0-snapshot.411")])
        #expect(String(decoding: data, as: UTF8.self) == #"["0.1.0-snapshot.411"]"#)
        #expect(try JSONDecoder().decode([ReleaseVersion].self, from: data) == [v("0.1.0-snapshot.411")])
    }
}

@Suite struct ReleaseFeedTests {
    static let base = "https://github.com/ghassenbrg/sidefolk/releases/download"

    static func release(_ tag: String, prerelease: Bool = true, draft: Bool = false, assets: [String]? = nil,
                        digest: String? = "sha256:" + String(repeating: "ab", count: 32), host: String = base) -> String {
        let version = tag.dropFirst()
        let names = assets ?? ["Sidefolk-\(version).dmg", "Sidefolk-\(version).dmg.sha256"]
        let list = names.map { name in
            """
            {"name": "\(name)", "size": \(name.hasSuffix(".dmg") ? 23676873 : 98), "state": "uploaded",
             "browser_download_url": "\(host)/\(tag)/\(name)"\(digest.map { #", "digest": "\#($0)""# } ?? "")}
            """
        }.joined(separator: ",")
        return """
            {"tag_name": "\(tag)", "name": "Sidefolk \(version)", "body": "**What's new**\\n- Something", "draft": \(draft),
             "prerelease": \(prerelease), "html_url": "https://github.com/ghassenbrg/sidefolk/releases/tag/\(tag)",
             "published_at": "2026-10-28T09:00:00Z", "assets": [\(list)]}
            """
    }

    static func feed(_ releases: String...) -> Data { Data("[\(releases.joined(separator: ","))]".utf8) }

    @Test func readsReleasesNewestFirstAndLeavesOutWhatCantBeInstalled() throws {
        let offers = try ReleaseFeed.offers(from: Self.feed(
            Self.release("v0.1.0-snapshot.411"),
            Self.release("v0.1.0", prerelease: false),
            Self.release("v0.1.0-snapshot.430"),
            Self.release("v0.1.0-snapshot.440", draft: true),
            Self.release("v0.1.0-snapshot.450", assets: ["Sidefolk-0.1.0-snapshot.450.zip"]),   // no disk image
            Self.release("nightly"),
            Self.release("v0.1.0-snapshot.460", host: "https://downloads.example.com")))          // not GitHub
        #expect(offers.map(\.tag) == ["v0.1.0", "v0.1.0-snapshot.430", "v0.1.0-snapshot.411"])
        let release = try #require(offers.first)
        #expect(!release.isSnapshot)
        #expect(release.image.name == "Sidefolk-0.1.0.dmg")
        #expect(release.image.size == 23676873)
        #expect(release.image.sha256 == String(repeating: "ab", count: 32))
        #expect(release.checksum?.name == "Sidefolk-0.1.0.dmg.sha256")
        #expect(release.published != nil)
        #expect(offers[1].isSnapshot)
    }

    @Test func aReleaseNumberedAsASnapshotIsOneWhateverItsFlag() throws {
        let offers = try ReleaseFeed.offers(from: Self.feed(Self.release("v0.2.0-beta.1", prerelease: false)))
        #expect(offers.first?.isSnapshot == true)
    }

    @Test func picksTheNewestForTheChannelAboveWhatRunsAndWhatWasSkipped() throws {
        let offers = try ReleaseFeed.offers(from: Self.feed(
            Self.release("v0.1.0-snapshot.430"), Self.release("v0.1.0-snapshot.440"), Self.release("v0.1.0", prerelease: false)))
        let snapshot = ReleaseVersion("0.1.0-snapshot.411")!
        #expect(ReleaseFeed.newest(offers, channel: .snapshots, after: snapshot)?.tag == "v0.1.0")
        #expect(ReleaseFeed.newest(offers, channel: .releases, after: snapshot)?.tag == "v0.1.0")
        let only = offers.filter(\.isSnapshot)
        #expect(ReleaseFeed.newest(only, channel: .snapshots, after: snapshot)?.tag == "v0.1.0-snapshot.440")
        #expect(ReleaseFeed.newest(only, channel: .releases, after: snapshot) == nil)
        // Skipping 440 doesn't bring back 430.
        #expect(ReleaseFeed.newest(only, channel: .snapshots, after: snapshot, skipping: ReleaseVersion("0.1.0-snapshot.440")) == nil)
        #expect(ReleaseFeed.newest(offers, channel: .snapshots, after: ReleaseVersion("0.1.0")!) == nil)
    }

    @Test func defaultChannelFollowsTheBuildThatRuns() {
        let s = UpdateSettings()
        #expect(s.channel(running: ReleaseVersion("0.1.0-snapshot.411")!) == .snapshots)
        #expect(s.channel(running: ReleaseVersion("0.1.0")!) == .releases)
        var chosen = UpdateSettings()
        chosen.channel = .releases
        #expect(chosen.channel(running: ReleaseVersion("0.1.0-snapshot.411")!) == .releases)
    }

    @Test func settingsFromBeforeUpdatesExistedDecodeWithDefaults() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"companionName": "Pip"}"#.utf8))
        #expect(s.updates == UpdateSettings())
        #expect(s.updates.automatic)
        let skipped = try JSONDecoder().decode(UpdateSettings.self, from: Data(#"{"skipped": "0.1.0-snapshot.430", "channel": "releases"}"#.utf8))
        #expect(skipped.skipped == ReleaseVersion("0.1.0-snapshot.430"))
        #expect(skipped.channel == .releases)
    }

    @Test func summaryIsPlainSentences() throws {
        let offer = try #require(try ReleaseFeed.offers(from: Self.feed(Self.release("v0.1.0", prerelease: false))).first)
        var long = offer
        long.notes = "## Highlights\n- **Updates** in [Settings](https://x)\n- `code` too!\n\n" + String(repeating: "word ", count: 80)
        #expect(offer.summary() == "Something.")
        let summary = try #require(long.summary(limit: 60))
        #expect(summary.hasPrefix("Updates in Settings. code too! word word"))
        #expect(summary.count <= 60 && summary.hasSuffix("…"))
        long.notes = "  \n"
        #expect(long.summary() == nil)
    }
}
