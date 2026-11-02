import Foundation
import Synchronization
import Testing
@testable import SidefolkCore

/// A companion that can't say what version it is feels broken (D120). The app's side is a seam here.
@Suite struct SelfToolsTests {
    final class App: SelfReporting, @unchecked Sendable {
        let opened = Mutex<[SelfPlace]>([])
        let installs = Mutex(0)
        let look = Mutex((appearance: AppAppearance.system, theme: "harbor"))
        let updates: SelfUpdates
        let failing: Bool
        var installing: SelfInstall = .nothingNewer

        init(updates: SelfUpdates = SelfUpdates(running: "0.1.0-snapshot.876", published: true, newest: nil, ready: false, addons: []), failing: Bool = false) {
            self.updates = updates
            self.failing = failing
        }

        func about() async -> SelfAbout {
            SelfAbout(version: "0.1.0-snapshot.876", published: true, companion: "Mochi", ai: "Claude Code", theme: "Harbor", appearance: "light",
                      language: "en", extensions: ["Weather"], extensionsOff: ["Feeds"])
        }

        func lookForUpdates() async throws -> SelfUpdates {
            if failing { throw UserFacingError("Sidefolk couldn't reach GitHub to look for updates.") }
            return updates
        }

        func installUpdate() async -> SelfInstall {
            installs.withLock { $0 += 1 }
            return installing
        }

        func open(_ place: SelfPlace) async { opened.withLock { $0.append(place) } }

        func setAppearance(_ appearance: AppAppearance) async -> AppAppearance {
            look.withLock { l in
                defer { l.appearance = appearance }
                return l.appearance
            }
        }

        func setTheme(_ name: String) async -> (name: String, was: String)? {
            guard name.lowercased() == "paper garden" || name == "harbor" else { return nil }
            return look.withLock { l in
                defer { l.theme = name }
                return (name, l.theme)
            }
        }
    }

    struct Lister: SoftwareUpdateListing {
        var output: String
        func list() async throws -> String { output }
    }

    func env(_ app: App = App(), mac: String = "No new software available.") throws -> TestEnv {
        let env = try TestEnv()
        env.registry.register(SelfTools.make(app: app, softwareUpdates: Lister(output: mac)))
        return env
    }

    func result(_ outcome: ToolOutcome) throws -> ToolResult {
        guard case .ok(let r) = outcome.status else {
            Issue.record("expected success, got \(outcome.status)")
            throw CancellationError()
        }
        return r
    }

    func run(_ env: TestEnv, _ tool: String, _ input: JSONValue = .object([:]), as caller: Caller = .agent(runId: "r")) async -> ToolOutcome {
        await env.executor.execute(name: tool, input: input, caller: caller)
    }

    @Test func itKnowsWhatItIs() async throws {
        let r = try result(await run(try env(), "sidefolk.about"))
        for part in ["0.1.0-snapshot.876", "Mochi", "Claude Code", "Harbor", "Weather", "Feeds"] { #expect(r.text.contains(part), "\(part)") }
    }

    @Test func itSaysWhenItsTheNewest() async throws {
        let r = try result(await run(try env(), "sidefolk.updates"))
        #expect(r.text.contains("is the newest"))
    }

    @Test func itSaysWhatsNewerAndWhichAddOns() async throws {
        let e = try env(App(updates: SelfUpdates(running: "0.1.0-snapshot.876", published: true, newest: "0.1.0 snapshot 880", ready: false, addons: ["Weather"])))
        let r = try result(await run(e, "sidefolk.updates"))
        #expect(r.text.contains("0.1.0 snapshot 880"))
        #expect(r.text.contains("Weather"))
    }

    @Test func aDevelopmentBuildSaysSo() async throws {
        let e = try env(App(updates: SelfUpdates(running: "0.1.0", published: false, newest: nil, ready: false, addons: [])))
        #expect(try result(await run(e, "sidefolk.updates")).text.contains("development build"))
    }

    /// Looking failed: it says so, never "you're up to date".
    @Test func aFailedLookIsAFailure() async throws {
        let outcome = await run(try env(App(failing: true)), "sidefolk.updates")
        #expect(!outcome.isOK)
        #expect(outcome.problem?.message.contains("GitHub") == true)
    }

    /// Installing ends in a restart, so the person says yes first, and the AI can't do it unasked.
    @Test func installingAsksFirst() async throws {
        let app = App(updates: SelfUpdates(running: "a", published: true, newest: "b", ready: false, addons: []))
        let e = try env(app)
        let answered = e.autoAnswer(.deny)
        let denied = await run(e, "sidefolk.install_update")
        _ = await answered.value
        #expect(!denied.isOK)
        #expect(app.installs.withLock { $0 } == 0)
    }

    /// Each says what really happened: only one has started anything, and none has installed.
    @Test(arguments: [(SelfInstall.downloading("2"), "isn't installed yet"), (.readyToRestart("2"), "clicks to restart"), (.underWay, "already under way"), (.nothingNewer, "no newer")])
    func installingSaysWhatItCameTo(state: SelfInstall, words: String) async throws {
        let app = App()
        app.installing = state
        let e = try env(app)
        let answered = e.autoAnswer(.allowOnce)
        let r = try result(await run(e, "sidefolk.install_update"))
        _ = await answered.value
        #expect(r.text.contains(words))
    }

    /// The gallery out of reach isn't "no add-on has a newer version".
    @Test func addOnsNotCheckedSaySo() async throws {
        let e = try env(App(updates: SelfUpdates(running: "a", published: true, newest: nil, ready: false, addons: nil)))
        let r = try result(await run(e, "sidefolk.updates"))
        #expect(r.text.contains("weren't checked"))
        #expect(!r.text.contains("No add-on"))
    }

    /// Anything but its own "nothing new" isn't "up to date".
    @Test func anUnexpectedAnswerFromMacOSIsAFailure() async throws {
        let outcome = await run(try env(mac: "Software Update Tool\n\nFinding available software\nCan't connect to the server"), "mac.software_updates")
        #expect(!outcome.isOK)
    }

    @Test func noneOfThisIsForOtherAgents() throws {
        for tool in SelfTools.make(app: App(), softwareUpdates: Lister(output: "")) { #expect(!tool.spec.external, "\(tool.spec.name)") }
        #expect(ExternalToolPolicy.all.isDisjoint(with: ["sidefolk.about", "sidefolk.updates", "sidefolk.install_update", "sidefolk.open", "sidefolk.look", "mac.software_updates"]))
    }

    @Test func itOpensPlaces() async throws {
        let app = App()
        let e = try env(app)
        #expect(await run(e, "sidefolk.open", ["place": "updates"]).isOK)
        #expect(app.opened.withLock { $0 } == [.updates])
        #expect(!(await run(e, "sidefolk.open", ["place": "nowhere"])).isOK)
    }

    @Test func itChangesItsLookAndUndoPutsItBack() async throws {
        let app = App()
        let e = try env(app)
        let outcome = await run(e, "sidefolk.look", ["appearance": "dark", "theme": "Paper Garden"])
        #expect(outcome.isOK)
        #expect(app.look.withLock { $0.appearance } == .dark)
        _ = try await e.executor.undo.undo(outcome.activity.id)
        #expect(app.look.withLock { $0.appearance } == .system)
        #expect(app.look.withLock { $0.theme } == "harbor")
        #expect(!(await run(e, "sidefolk.look", ["theme": "Neon"])).isOK)
        #expect(!(await run(e, "sidefolk.look")).isOK)
    }

    // MARK: The Mac's own updates

    @Test func aMacWithNothingWaitingSaysSo() async throws {
        #expect(try result(await run(try env(), "mac.software_updates")).text.contains("no software updates"))
    }

    @Test func theMacsListIsRead() async throws {
        let output = """
            Software Update Tool

            Finding available software
            Software Update found the following new or updated software:
            * Label: macOS Tahoe 26.1-25B78
            \tTitle: macOS Tahoe 26.1, Version: 26.1, Size: 3800000KiB, Recommended: YES, Action: restart,
            * Label: Safari26.1
            \tTitle: Safari, Version: 26.1, Size: 200000KiB, Recommended: YES,
            """
        let r = try result(await run(try env(mac: output), "mac.software_updates"))
        #expect(r.text.contains("macOS Tahoe 26.1;"), "its version isn't said twice")
        #expect(r.text.contains("Safari 26.1"))
        #expect(r.text.contains("restart"))
        #expect(SoftwareUpdateTool.parse(output).count == 2)
        #expect(SoftwareUpdateTool.parse("Software Update Tool\n\nNo new software available.").isEmpty)
    }

    // MARK: What the model is told

    @Test func theModelIsToldItCanAnswerForItself() {
        let names = SelfTools.make(app: App(), softwareUpdates: Lister(output: "")).map(\.spec)
        let reach = ContextBuilder.reach(names)
        #expect(reach.contains("never offer to build an extension"))
        #expect(!ContextBuilder.reach([]).contains("sidefolk_about"))
    }
}
