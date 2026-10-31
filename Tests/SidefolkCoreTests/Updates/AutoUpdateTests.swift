import Foundation
import Testing
@testable import SidefolkCore

/// Sidefolk updating itself without asking, and the choices behind it (D70): when an automatic install may restart
/// the app, and settings from before D70 loading with the defaults.
@Suite struct AutoUpdateTests {
    // MARK: When to install

    @Test func anAutomaticInstallWaitsForTheCalmAndTheAway() {
        let away = InstallMoment.away
        #expect(InstallMoment.decide(.init(secondsSinceInput: away)) == .now)
        #expect(InstallMoment.decide(.init(secondsSinceInput: away + 3600)) == .now)
        #expect(InstallMoment.decide(.init(secondsSinceInput: 0)) == .wait(.present))
        #expect(InstallMoment.decide(.init(secondsSinceInput: away - 1)) == .wait(.present), "a few minutes away, not one")
        // Whatever would be cut off holds it back even when the person is away: an approval card waits for them.
        let long = away * 10
        #expect(InstallMoment.decide(.init(conversation: true, secondsSinceInput: long)) == .wait(.conversation))
        #expect(InstallMoment.decide(.init(approval: true, secondsSinceInput: long)) == .wait(.approval))
        #expect(InstallMoment.decide(.init(voice: true, secondsSinceInput: long)) == .wait(.voice))
        #expect(InstallMoment.decide(.init(asking: true, secondsSinceInput: long)) == .wait(.asking))
        #expect(InstallMoment.decide(.init(work: true, secondsSinceInput: long)) == .wait(.work))
        #expect(InstallMoment.decide(.init(conversation: true, approval: true, voice: true, asking: true, work: true)) == .wait(.conversation))
    }

    // MARK: Settings

    @Test func settingsFromBeforeD70KeepWhatThePersonChose() throws {
        func decode(_ json: String) throws -> UpdateSettings { try JSONDecoder().decode(UpdateSettings.self, from: Data(json.utf8)) }
        let none = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"companionName": "Pip"}"#.utf8)).updates
        #expect(none.app == .notify && none.addons, "Tell me for Sidefolk, add-ons by themselves")
        #expect(try decode(#"{"automatic": false}"#).app == .off, "the old switch off: don't check")
        #expect(try decode(#"{"automatic": true, "channel": "snapshots"}"#).app == .notify)
        #expect(try decode(#"{"automatic": true, "channel": "snapshots"}"#).effectiveChannel == .snapshots)
        // The new choice wins over the old switch, and something unreadable falls back to the default.
        #expect(try decode(#"{"app": "install", "automatic": false}"#).app == .install)
        #expect(try decode(#"{"app": "sometimes", "addons": "yes"}"#) == UpdateSettings())

        var chosen = UpdateSettings()
        chosen.app = .install
        chosen.addons = false
        chosen.channel = .snapshots
        chosen.skipped = ReleaseVersion("0.1.0-snapshot.430")
        let data = try JSONEncoder().encode(chosen)
        #expect(try JSONDecoder().decode(UpdateSettings.self, from: data) == chosen)
        // An older snapshot opened again still reads whether to look.
        let written = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(written["automatic"] as? Bool == true)
        chosen.app = .off
        let off = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(chosen)) as? [String: Any])
        #expect(off["automatic"] as? Bool == false)
    }

    // MARK: After installing by itself

    @Test func theNewCopySaysUpdatedOnce() async throws {
        let checker = UpdateChecker(kv: nil)
        #expect(await checker.takeInstalled() == nil)
        let offer = UpdateOffer(version: ReleaseVersion("0.1.0-snapshot.540")!, tag: "v0.1.0-snapshot.540", title: "", notes: "",
                                page: URL(string: "https://github.com/ghassenbrg/sidefolk/releases/tag/v0.1.0-snapshot.540")!,
                                published: nil, isSnapshot: true,
                                image: .init(name: "Sidefolk.dmg", size: 1, url: URL(string: "https://github.com/x.dmg")!), checksum: nil)
        await checker.markInstalling(offer)
        let installed = try #require(await checker.takeInstalled())
        #expect(installed.version == offer.version && installed.page == offer.page)
        #expect(await checker.takeInstalled() == nil, "said once")
    }
}
