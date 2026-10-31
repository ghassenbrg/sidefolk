import Foundation
import Testing
@testable import SidefolkCore

/// Extension pages (D62): what a page may say, the history Sidefolk keeps for its charts, the manifest's checks, and
/// System Vitals+ drawing its page from inside the sandbox.
struct ExtensionPageTests {
    static func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    @Test func aPageKeepsWhatItKnowsAndDropsTheRest() throws {
        let page = try ExtensionPage.parse(Self.json("""
            {"summary": {"title": "All good", "detail": "CPU 12%", "tone": "good", "symbol": "checkmark.seal.fill"},
             "sections": [
               {"title": "Now", "blocks": [
                 {"type": "gauge", "label": "CPU", "value": "12%", "fraction": 1.7, "tone": "warn"},
                 {"type": "hologram", "label": "from a newer Sidefolk"},
                 {"type": "chart", "id": "cpu", "title": "CPU", "series": [{"key": "total", "label": "CPU", "value": 12}, {"key": "Bad Key", "value": 3}]},
                 {"type": "chart", "id": "../escape", "title": "Bad", "series": [{"key": "x", "value": 1}]},
                 {"type": "stat", "label": "On for", "value": "3 days", "tone": "purple"},
                 {"type": "ask", "label": "Why?", "ask": "Why is my Mac slow?"}]},
               {"title": "Empty", "blocks": [{"type": "facts", "items": []}]}]}
            """))
        #expect(page.summary == ExtensionPage.Summary(title: "All good", detail: "CPU 12%", tone: .good, symbol: "checkmark.seal.fill"))
        #expect(page.sections.count == 1, "a section with nothing left is dropped")
        let blocks = page.sections[0].blocks
        #expect(blocks.count == 4, "the unknown part and the chart with a bad id are left out")
        guard case .gauge(let g) = blocks[0], case .chart(let c) = blocks[1], case .stat(let s) = blocks[2], case .ask = blocks[3] else {
            Issue.record("\(blocks)")
            return
        }
        #expect(g.fraction == 1 && g.tone == .warn)
        #expect(c.series.map(\.key) == ["total"])
        #expect(s.tone == .neutral)
        #expect(page.samples == ["cpu/total": 12])
    }

    @Test func textIsCleanedAndClipped() throws {
        let text = "Look\\u202e here\\n" + String(repeating: "a", count: 600)
        let page = try ExtensionPage.parse(Self.json(#"{"sections": [{"blocks": [{"type": "note", "text": ""# + text + #""}]}]}"#))
        guard case .note(let n) = page.sections.first?.blocks.first else { Issue.record("no note"); return }
        #expect(!n.text.contains("\u{202E}") && !n.text.contains("\n"))
        #expect(n.text.count <= 400)
    }

    @Test func somethingElseIsNotAPage() throws {
        #expect(throws: UserFacingError.self) { try ExtensionPage.parse(Self.json(#"{"hello": "world"}"#)) }
        #expect(throws: UserFacingError.self) { try ExtensionPage.parse(Self.json(#"["a"]"#)) }
        let huge = "{\"sections\": [{\"blocks\": [{\"type\": \"note\", \"text\": \"\(String(repeating: "x", count: 140_000))\"}]}]}"
        #expect(throws: UserFacingError.self) { try ExtensionPage.parse(Self.json(huge)) }
    }

    @Test func historyKeepsEveryValueFor15MinutesThenOneAMinuteForADay() async throws {
        let history = ExtensionPageHistory(folder: nil)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        // Every 5 seconds for 30 minutes, with a spike in the middle of one minute.
        for i in 0..<360 {
            let value = i == 100 ? 99.0 : Double(i % 10)
            await history.record(extensionId: "dev.example.vitals", page: "mac", samples: ["cpu/total": value], at: start.addingTimeInterval(Double(i) * 5))
        }
        let now = start.addingTimeInterval(359 * 5)
        let fine = await history.points(extensionId: "dev.example.vitals", page: "mac", key: "cpu/total", window: 600, now: now)
        #expect(fine.count == 121, "every value of the last ten minutes")
        let day = await history.points(extensionId: "dev.example.vitals", page: "mac", key: "cpu/total", window: 86_400, now: now)
        #expect((29...31).contains(day.count), "one a minute: \(day.count)")
        #expect(day.contains { $0.v == 99 }, "a minute keeps its highest value")
        // A day later, the oldest minutes are gone.
        await history.record(extensionId: "dev.example.vitals", page: "mac", samples: ["cpu/total": 1], at: start.addingTimeInterval(86_400 + 600))
        let later = await history.points(extensionId: "dev.example.vitals", page: "mac", key: "cpu/total", window: 86_400,
                                         now: start.addingTimeInterval(86_400 + 600))
        #expect(later.allSatisfy { $0.t >= start.addingTimeInterval(600) })
    }

    @Test func historySurvivesARestartAndGoesWithTheExtension() async throws {
        let folder = try ExtFixtures.tempDir("page-history")
        let at = Date()
        let first = ExtensionPageHistory(folder: folder)
        await first.record(extensionId: "dev.example.vitals", page: "mac", samples: ["memory/used": 12.5], at: at)
        await first.save(now: at)
        let second = ExtensionPageHistory(folder: folder)
        #expect(await second.points(extensionId: "dev.example.vitals", page: "mac", key: "memory/used", window: 600, now: at).map(\.v) == [12.5])
        await second.forget(extensionId: "dev.example.vitals")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("dev.example.vitals.json").path))
        // An id that isn't one is never a file name.
        await second.record(extensionId: "../../etc", page: "mac", samples: ["a/b": 1], at: at)
        await second.save(now: at)
        #expect((try FileManager.default.contentsOfDirectory(atPath: folder.path)).isEmpty)
    }

    @Test func theManifestSaysWhatAPageMayBe() throws {
        let manifest = try ExtensionManifest.decode(Data("""
            {"id": "dev.example.vitals", "name": "Vitals", "version": "1.0", "run": {"command": "bin/x"},
             "pages": {"mac": {"title": "Your Mac", "symbol": "gauge.with.dots.needle.67percent", "refresh": 3, "history": true, "widget": true},
                       "Bad Name": {"title": "", "symbol": "not a symbol!", "refresh": 1}}}
            """.utf8))
        #expect(manifest.pages["mac"] == ExtensionManifest.PageMeta(title: "Your Mac", symbol: "gauge.with.dots.needle.67percent", refresh: 3,
                                                                     history: true, widget: true))
        var issues: [ValidationIssue] = []
        ManifestValidator(paths: SidefolkPaths(home: try ExtFixtures.tempDir("pages-home"))).checkPages(manifest, issues: &issues)
        #expect(Set(issues.map(\.field)) == ["pages.Bad Name", "pages.Bad Name.title", "pages.Bad Name.symbol", "pages.Bad Name.refresh"])
        // A key a page doesn't have is refused, like everywhere in a manifest.
        #expect(throws: ValidationIssue.self) {
            try ExtensionManifest.decode(Data(#"{"id": "dev.example.v", "name": "V", "version": "1.0", "run": {"command": "bin/x"}, "pages": {"p": {"title": "P", "colour": "red"}}}"#.utf8))
        }
    }

    /// A summary may carry the extension's main switch or button (D67); anything else there is left out.
    @Test func aSummaryCarriesItsMainSwitch() throws {
        let page = try ExtensionPage.parse(["summary": ["title": "Awake", "control": ["type": "switch", "label": "Keep awake", "on": true,
                                                                                      "tool": "keep_awake"]]])
        let control = try #require(page.summary?.control)
        #expect(control.kind == .toggle(on: true) && control.tool == "keep_awake")
        #expect(control.input(switchedTo: false) == ["on": false])
        let button = try ExtensionPage.parse(["summary": ["title": "x", "control": ["type": "button", "label": "Stop", "tool": "stop"]]])
        #expect(button.summary?.control?.kind == .button(.secondary))
        for wrong: JSONValue in [["type": "gauge", "label": "CPU", "value": "1%"], ["type": "switch", "label": "x", "tool": "Bad Name"], "on"] {
            #expect(try ExtensionPage.parse(["summary": ["title": "x", "control": wrong]]).summary?.control == nil, "\(wrong)")
        }
    }

    @Test(.enabled(if: ExtFixtures.addonFolders.contains("system-vitals-plus"), ExtFixtures.noAddons))
    func systemVitalsPlusDrawsItsPageInTheSandbox() async throws {
        let h = try HostEnv()
        let info = try await h.host.install(from: ExtFixtures.builtIn("system-vitals-plus"))
        let pages = await h.host.pages()
        #expect(pages.map(\.id) == ["\(info.id)/mac"])
        #expect(pages.first?.history == true && pages.first?.widget == true)

        let page = try await h.host.renderPage(extensionId: info.id, page: "mac")
        let summary = try #require(page.summary)
        #expect(!summary.title.isEmpty && summary.detail.contains("CPU"), "\(summary)")
        let titles = page.sections.compactMap(\.title)
        for expected in ["Right now", "Over time", "What's using your Mac", "Memory", "Storage", "Network", "This Mac"] {
            #expect(titles.contains(expected), "\(titles)")
        }
        // Read inside the sandbox: other apps' use, the disk's free space and the chip all came through.
        let all = page.sections.flatMap(\.blocks)
        let bars = all.compactMap { if case .bars(let b) = $0 { b } else { nil } }
        #expect(bars.first { $0.title == "Memory" }?.items.isEmpty == false, "apps' memory")
        let disk = all.compactMap { if case .gauge(let g) = $0, g.label == "Disk" { g } else { nil } }.first
        // Free space as System Settings counts it (what macOS can clear counts as free), read inside the sandbox.
        let settings = try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage.map { Double($0) / 1e9 } ?? 0
        let shown = disk.flatMap { Double($0.value.split(separator: " ").first ?? "") } ?? 0
        #expect(abs(shown - settings) < max(2, settings * 0.05), "page \(shown) GB, macOS \(settings) GB")
        #expect(page.samples.keys.contains("cpu/total") && page.samples.keys.contains("memory/used"))
        let kept = await h.host.pageHistory.points(extensionId: info.id, page: "mac", key: "cpu/total", window: 600, now: Date())
        #expect(kept.count == 1)
        #expect(await h.host.latestPage(extensionId: info.id, page: "mac") != nil)

        // Its answers and heads-ups come from the same readings.
        let health = try #require(await h.call("ext.system-vitals-plus.health").okText)
        #expect(health.contains("CPU") && health.contains("Temperature"), "\(health)")
        let top = try #require(await h.call("ext.system-vitals-plus.top_apps").okText)
        #expect(top.contains("Memory: "), "\(top)")
        let low = try await h.host.checkWatcher(extensionId: info.id, watcher: "disk_low", config: ["below_gb": 1_000_000], state: .null)
        #expect(low.triggered)

        try await h.host.uninstall(id: info.id)
        #expect(await h.host.pages().isEmpty)
        #expect(await h.host.pageHistory.points(extensionId: info.id, page: "mac", key: "cpu/total", window: 600, now: Date()).isEmpty)
        await h.host.shutdown()
    }
}
