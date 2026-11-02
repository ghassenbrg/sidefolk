import Foundation
@testable import SidefolkCore
import Testing

/// The prayer-times pack from sidefolk-addons in the real sandbox: a page with places in it (D105), reminders through the host's timer (D107) and what must not
/// happen by itself. Its debug program answers from its own fixtures in the data folder and never touches the network.
@Suite(.serialized) struct PrayerPackSandboxTests {
    static let id = "dev.sidefolk.prayer-times"
    /// Tokyo, 2 November 2026, 16:32: fourteen minutes before the fixture's Maghrib.
    static let moment = ISO8601DateFormatter().date(from: "2026-11-02T07:32:00Z")!

    final class World {
        let h: HostEnv
        let attention: AttentionCenter
        let occurrences: OccurrenceScheduler

        init(place: Bool = true) async throws {
            h = try HostEnv()
            let host = h.host
            h.env.clock.set(PrayerPackSandboxTests.moment)
            h.env.registry.register(ExtensionConsentTool(host: host))
            h.env.registry.register(ExtensionOccurrencesTool(host: host))
            attention = AttentionCenter(store: AttentionStore(h.env.db), events: h.env.events, clock: h.env.clock)
            occurrences = OccurrenceScheduler(store: ExtensionOccurrenceStore(KVStore(h.env.db)), attention: attention, events: h.env.events, clock: h.env.clock)
            await host.setOccurrences(occurrences)
            _ = try await host.install(from: ExtFixtures.builtIn("prayer-times"))
            try plantFixtures()
            await occurrences.start(extensions: await host.scheduling())
            if place {
                try await run("choose_place", ["label": "Tokyo", "country": "Japan", "latitude": 35.6762, "longitude": 139.6503, "zone": "Asia/Tokyo"])
                try await run("use_calculated", ["method": 3])
                try await run("set_display", ["what": "time", "value": "hour24"])
                await settle()
            }
        }

        private func plantFixtures() throws {
            let fm = FileManager.default
            let data = h.host.dataFolder(extensionId: PrayerPackSandboxTests.id)
            let dir = data.appendingPathComponent("debug-fixtures", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let from = ExtFixtures.source("prayer-times").appendingPathComponent("Fixtures")
            func copy(_ name: String, _ to: String) throws { try fm.copyItem(at: from.appendingPathComponent("\(name).json"), to: dir.appendingPathComponent("\(to).json")) }
            try copy("names", "asmaAlHusna")
            try copy("qibla-tokyo", "qibla_35.6762_139.6503")
            try copy("prayer-methods", "methods")
            try copy("calendar-methods", "islamicCalendar_methods")
            try copy("gregorian-month", "gToHCalendar_11_2026")
            try copy("ramadan-month", "hijriCalendar_1448_9")
            try copy("listed-occasions", "islamicHolidaysByHijriYear_1448")
            try copy("date-conversion", "gToH_02-11-2026")
            // The one day the fixtures have: the month it is in doesn't come, so it is asked for on its own.
            try copy("prayer-day", "timings_02-11-2026")
            try Data("fixtures".utf8).write(to: data.appendingPathComponent("debug-network.txt"))
            try Data("2026-11-02T07:32:00Z".utf8).write(to: data.appendingPathComponent("debug-now.txt"))
        }

        @discardableResult
        func run(_ tool: String, _ input: JSONValue = .object([:])) async throws -> String {
            let outcome = await h.env.executor.execute(name: "ext.prayer-times.\(tool)", input: input, caller: .user, pickedFile: input.string("path"))
            return try #require(outcome.okText, "\(tool): \(String(describing: outcome.problem?.message))")
        }

        func page(_ state: JSONValue = .object([:]), width: Int = 1000) async throws -> ExtensionPage {
            try await h.host.renderPage(extensionId: PrayerPackSandboxTests.id, page: "noor", language: "en", state: state, width: width)
        }

        /// Fetching runs beside the pages: read until it has finished.
        func settle() async {
            for _ in 0..<40 {
                if let page = try? await page(), page.summary?.title != "Loading timetable" { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        func pending() async -> Int { await occurrences.status(PrayerPackSandboxTests.id).pending }

        func told() async -> [AttentionItem] { ((try? await AttentionStore(h.env.db).open()) ?? []).filter { $0.source == "extension:\(PrayerPackSandboxTests.id)" } }

        func consent(_ on: Bool) async -> ToolOutcome {
            await h.env.executor.execute(name: "extensions.consent", input: ["extension": .string(PrayerPackSandboxTests.id), "what": "schedule", "on": .bool(on)], caller: .user)
        }
    }

    /// Without the marks Sidefolk puts around values, which keep them the right way round in any language.
    private static func plain(_ text: String?) -> String { String((text ?? "").unicodeScalars.filter { !(0x2066...0x2069).contains($0.value) }.map(Character.init)) }

    private static func scenes(_ sections: [ExtensionPage.Section]) -> [PageScene] {
        sections.flatMap(\.blocks).flatMap { block -> [PageScene] in
            switch block {
            case .scene(let s): [s]
            case .tabs(let t): scenes(t.sections)
            default: []
            }
        }
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func aFirstRunHasNoPlaceAndNoInventedTime() async throws {
        let w = try await World(place: false)
        let page = try await w.page()
        #expect(page.bare && page.dress != nil)
        #expect(page.summary?.title == "Choose a place")
        let words = String(describing: page)
        #expect(!words.contains("16:46"), "no time before there is a place")
        #expect(await w.pending() == 0)
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func everyPlaceDrawsWithinThePagesLimits() async throws {
        let w = try await World()
        let views: [JSONValue] = [["tab": "overview"], ["tab": "prayer"], ["tab": "prayer", "select": "maghrib"], ["tab": "calendar"], ["tab": "qibla"], ["tab": "names"], ["tab": "names", "q": "merciful"],
                                  ["tab": "names", "filter": "saved"], ["sheet": "ramadan"], ["sheet": "convert"], ["sheet": "occasions"], ["sheet": "manual"],
                                  ["sheet": "prefs", "section": "place"], ["sheet": "prefs", "section": "sources"], ["sheet": "prefs", "section": "calculation"], ["sheet": "prefs", "section": "calendar"],
                                  ["sheet": "prefs", "section": "reminders"], ["sheet": "prefs", "section": "data"]]
        for width in [1000, 640] {
            for view in views {
                _ = try await w.page(view, width: width)
            }
        }
        // A scene refused by the reader would be left out without a word: each of these must still have its own.
        for tab in ["overview", "prayer", "calendar", "qibla", "names"] as [JSONValue] {
            let page = try await w.page(["tab": tab])
            #expect(Self.scenes(page.sections).count >= 2, "\(tab): the head and what the tab draws")
        }
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func todayHomeAndAskAgreeAtTheSameInstant() async throws {
        let w = try await World()
        let summary = try #require(try await w.page().summary)
        #expect(summary.title == "Maghrib 16:46", "\(summary)")
        let detail = Self.plain(summary.detail)
        #expect(detail.hasPrefix("In 14 min"))
        let next = try await w.run("ask_noor", ["question": "next"])
        #expect(next.contains("Maghrib") && next.contains("16:46"))
        let fajr = try await w.run("ask_noor", ["question": "prayer", "prayer": "fajr"])
        #expect(fajr.contains("04:37"), "asking for a prayer is its start, whatever the dial is on")
        let qibla = try await w.run("ask_noor", ["question": "qibla"])
        #expect(qibla.contains("293°") && qibla.contains("can't sense"))
        let hijri = try await w.run("ask_noor", ["question": "hijri"])
        #expect(hijri.contains("22 ") && hijri.contains("1448") && hijri.contains("Umm al-Qura"))
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func readingAndDraftsScheduleNothing() async throws {
        let w = try await World()
        #expect(await w.consent(true).isOK)
        for view in [["tab": "overview"], ["sheet": "ramadan"], ["sheet": "prefs", "section": "reminders", "rm_master": true, "rm_maghrib_at": true]] as [JSONValue] {
            _ = try await w.page(view)
        }
        #expect(await w.pending() == 0, "all of it is off until saved")
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func savedRemindersReachTheHostsTimerAndItsLifecycle() async throws {
        let w = try await World()
        let reminders: JSONValue = ["master": true, "companion": true, "system": false, "prayers": ["maghrib": ["before": 5, "at": true, "iqamah": -1]]]
        try await w.run("save_reminders", reminders)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(await w.pending() == 0, "no yes, no plan")

        #expect(await w.consent(true).isOK, "the yes asks for a plan")
        try await waitFor { await w.pending() == 2 }
        #expect(await w.told().isEmpty)

        // Nine minutes on: 5 before Maghrib, on the host's timer, with no program needed.
        w.h.env.clock.advance(9 * 60 + 1)
        await w.occurrences.tick()
        let told = await w.told()
        let titles = told.map { Self.plain($0.title) }
        #expect(titles == ["Maghrib in 5 min"])
        #expect(told.first?.body?.hasPrefix("Noor · ") == true)
        #expect(await w.pending() == 1)

        try await w.h.host.setEnabled(false, id: Self.id)
        #expect(await w.pending() == 0, "off cancels what was to come")
        #expect(await w.told().isEmpty, "and takes back what is up")
        try await w.h.host.setEnabled(true, id: Self.id)

        #expect(await w.consent(false).isOK)
        #expect(await w.pending() == 0)
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func removalLeavesNothingScheduled() async throws {
        let w = try await World()
        try await w.run("save_reminders", ["master": true, "companion": true, "prayers": ["maghrib": ["before": -1, "at": true, "iqamah": -1]]])
        _ = await w.consent(true)
        try await waitFor { await w.pending() == 1 }
        try await w.h.host.uninstall(id: Self.id)
        let status = await w.occurrences.status(Self.id)
        #expect(status.pending == 0 && status.revision == 0)
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func onlyThePersonCanSayYes() async throws {
        let w = try await World()
        for caller in [Caller.extension(id: Self.id), .agent(runId: "r1")] {
            let outcome = await w.h.env.executor.execute(name: "extensions.consent", input: ["extension": .string(Self.id), "what": "schedule", "on": true], caller: caller)
            #expect(!outcome.isOK)
        }
        let plan = await w.h.env.executor.execute(name: "extensions.occurrences", input: ["extension": .string(Self.id), "revision": 1, "occurrences": []], caller: .user)
        #expect(!plan.isOK, "and only the extension plans")
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func aFileIsLookedOverBeforeAnythingIsKept() async throws {
        let w = try await World()
        let dir = try ExtFixtures.tempDir("timetable")
        let bad = dir.appendingPathComponent("bad.csv"), good = dir.appendingPathComponent("mosque.csv")
        try Data("date,prayer,start,iqamah,timezone\n2026-02-31,fajr,05:00,,Asia/Tokyo\n".utf8).write(to: bad)
        var rows = "date,prayer,start,iqamah,timezone\n"
        for (prayer, start, iqamah) in [("fajr", "05:12", "05:30"), ("dhuhr", "11:37", ""), ("asr", "14:39", ""), ("maghrib", "17:42", "17:50"), ("isha", "19:02", "19:30")] {
            rows += "2026-11-02,\(prayer),\(start),\(iqamah),Asia/Tokyo\n"
        }
        try Data(rows.utf8).write(to: good)

        try await w.run("import_csv", ["path": .string(bad.path)])
        var page = try await w.page(["sheet": "import"])
        let shown = Self.plain(String(describing: page))
        #expect(shown.contains("a date like 2027-01-31"))
        let before = try #require(page.summary)
        #expect(before.detail.contains("Calculated"), "nothing changed")

        try await w.run("import_csv", ["path": .string(good.path)])
        try await w.run("save_import", ["name": "Community Mosque"])
        page = try await w.page()
        #expect(page.summary?.title == "Maghrib 17:42", "its own times, and nothing worked out from the calculated ones")
        let source = Self.plain(page.summary?.detail)
        #expect(source.contains("Community Mosque · Manual"))
        let maghrib = try await w.run("ask_noor", ["question": "prayer", "prayer": "maghrib"])
        #expect(maghrib.contains("17:42") && maghrib.contains("17:50"))
        let dhuhr = try await w.run("ask_noor", ["question": "prayer", "prayer": "dhuhr"])
        #expect(!dhuhr.lowercased().contains("iqamah"), "none given, none inferred")
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons))
    func savedNamesStayAcrossAnUpdate() async throws {
        let w = try await World()
        try await w.run("save_name", ["number": 3, "saved": true])
        _ = try await w.h.host.install(from: ExtFixtures.builtIn("prayer-times"))
        let page = try await w.page(["tab": "names", "filter": "saved"])
        #expect(String(describing: page).contains("Al Malik"))
    }

    private func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("it never came")
    }
}
