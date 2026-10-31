import Foundation
import Testing
@testable import SidefolkCore

/// Extensions' pages in Home as the person arranged them (D67): order, hidden pages, tiles off, and new pages after.
struct HomePagesTests {
    let ids = ["a/x", "b/y", "c/z"]

    @Test func newPagesComeAfterThePlacedOnesInTheirOwnOrder() {
        var pages = HomePages()
        #expect(pages.sorted(ids) == ids)
        pages.move("c/z", before: "a/x", among: ids)
        #expect(pages.order == ["c/z", "a/x", "b/y"])
        #expect(pages.sorted(ids + ["d/w"]) == ["c/z", "a/x", "b/y", "d/w"])
        // A page that went away is skipped, not kept in the list.
        #expect(pages.sorted(["b/y", "c/z"]) == ["c/z", "b/y"])
    }

    @Test func movingStepsAmongTheShownPagesOnly() {
        var pages = HomePages()
        pages.setInSidebar("b/y", false)
        #expect(pages.shown(ids) == ["a/x", "c/z"])
        pages.step("a/x", by: 1, among: ids)
        #expect(pages.shown(ids) == ["c/z", "a/x"])
        pages.step("a/x", by: 1, among: ids)
        #expect(pages.shown(ids) == ["c/z", "a/x"], "already last")
        pages.step("a/x", by: -1, among: ids)
        #expect(pages.shown(ids) == ["a/x", "c/z"])
        pages.setInSidebar("b/y", true)
        #expect(pages.shown(ids).contains("b/y") && pages.hidden.isEmpty)
    }

    @Test func tilesAndFoldingAreRememberedWithTheSettings() throws {
        var settings = AppSettings()
        settings.homePages.setTile("a/x", false)
        settings.homePages.collapsed = true
        settings.homePages.move("b/y", before: nil, among: ids)
        settings.sidebarIcons = .colorful
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(back.homePages == settings.homePages && !back.homePages.tile("a/x") && back.homePages.tile("b/y"))
        #expect(back.sidebarIcons == .colorful)
        // Settings saved before any of this read as nothing arranged, icons as the theme says.
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"companionName": "Mochi"}"#.utf8))
        #expect(old.homePages == HomePages() && old.sidebarIcons == nil)
    }
}
