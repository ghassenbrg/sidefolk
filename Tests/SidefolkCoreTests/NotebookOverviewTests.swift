import Foundation
import Testing
@testable import SidefolkCore

@Suite struct NotebookOverviewTests {
    private let now = Date(timeIntervalSince1970: 1_793_700_000)
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func collection(_ name: String, kind: NotebookCollection.Kind = .project) -> NotebookCollection {
        NotebookCollection(name: name, kind: kind)
    }

    private func task(_ title: String, in c: NotebookCollection, dueIn days: Double?, done: Bool = false) -> NotebookItem {
        var item = NotebookItem(collectionId: c.id, kind: .task, title: title, source: "user", now: now)
        item.dueAt = days.map { now.addingTimeInterval($0 * 86400) }
        if done { item.status = .done }
        return item
    }

    @Test func tasksAreLateOrDueWithinAWeekSoonestFirstAndOpenOnly() {
        let home = collection("Home")
        let items = [
            task("next week", in: home, dueIn: 6), task("late", in: home, dueIn: -3), task("today", in: home, dueIn: 0),
            task("next month", in: home, dueIn: 30), task("no date", in: home, dueIn: nil), task("finished", in: home, dueIn: -1, done: true),
        ]
        let overview = NotebookOverview(collections: [home], items: items, now: now, calendar: calendar)
        #expect(overview.needsDoing.map(\.title) == ["late", "today", "next week"])
        #expect(overview.needsDoingCount == 3)
        // Six things, and only the finished one isn't still to do.
        #expect(overview.tiles[home.id]?.items == 6)
        #expect(overview.tiles[home.id]?.openTasks == 5)
    }

    @Test func showsAFewAndCountsThemAll() {
        let home = collection("Home")
        let items = (0..<8).map { task("t\($0)", in: home, dueIn: Double($0) / 2) }
        let overview = NotebookOverview(collections: [home], items: items, now: now, calendar: calendar)
        #expect(overview.needsDoing.count == NotebookOverview.tasksShown)
        #expect(overview.needsDoingCount == 8)
    }

    @Test func aboutYouAndWhatIsntLiveStayOut() {
        let home = collection("Home"), you = collection("About you", kind: .profile), archived = collection("Old")
        var pinned = NotebookItem(collectionId: home.id, kind: .note, title: "pinned", source: "user", now: now)
        pinned.pinnedAt = now
        var fact = NotebookItem(collectionId: you.id, kind: .note, title: "fact", source: "user", now: now)
        fact.pinnedAt = now
        var trashed = pinned
        trashed.id = "trashed"
        trashed.deletedAt = now
        let overview = NotebookOverview(collections: [home, you], items: [pinned, fact, trashed, task("old", in: archived, dueIn: 0)], now: now, calendar: calendar)
        #expect(overview.collections.map(\.name) == ["Home"])
        #expect(overview.itemCount == 1)
        #expect(overview.needsDoing.isEmpty)
        #expect(overview.pinned.map(\.title) == ["pinned"])
    }

    @Test func aPinnedTaskDueSoonIsShownOnce() {
        let home = collection("Home")
        var both = task("both", in: home, dueIn: 1)
        both.pinnedAt = now
        var later = task("later", in: home, dueIn: 20)
        later.pinnedAt = now.addingTimeInterval(-60)
        let overview = NotebookOverview(collections: [home], items: [both, later], now: now, calendar: calendar)
        #expect(overview.needsDoing.map(\.title) == ["both"])
        #expect(overview.pinned.map(\.title) == ["later"])
    }

    @Test func aTileSaysWhenItLastChanged() {
        let home = collection("Home"), empty = collection("Empty")
        var older = NotebookItem(collectionId: home.id, kind: .note, title: "a", source: "user", now: now)
        older.updatedAt = now.addingTimeInterval(-500)
        let newer = NotebookItem(collectionId: home.id, kind: .note, title: "b", source: "user", now: now)
        let overview = NotebookOverview(collections: [home, empty], items: [older, newer], now: now, calendar: calendar)
        #expect(overview.tiles[home.id]?.lastChange == now)
        #expect(overview.tiles[empty.id] == nil)
    }
}
