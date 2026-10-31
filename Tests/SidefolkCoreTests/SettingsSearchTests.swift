import Foundation
import Testing
@testable import SidefolkCore

/// Settings' search (D84): every word typed starts a word of the row, titles first.
@Suite struct SettingsSearchTests {
    let entries = [
        SettingsSearch.Entry(id: "login", title: "Open at login", detail: "Sidefolk starts quietly when you log in.", section: "Start"),
        SettingsSearch.Entry(id: "hours", title: "Quiet hours", detail: "Every night. Reminders still fire.", section: "Quiet on its own"),
        SettingsSearch.Entry(id: "notifications", title: "System notifications", detail: "Reminders can reach you."),
        SettingsSearch.Entry(id: "theme", title: "Thème", detail: "Couleurs et coins."),
    ]

    @Test func titlesComeFirstAndEveryWordMustMatch() {
        #expect(SettingsSearch.find("quiet", in: entries).map(\.id) == ["hours", "login"])
        #expect(SettingsSearch.find("notif", in: entries).map(\.id) == ["notifications"])
        #expect(SettingsSearch.find("quiet night", in: entries).map(\.id) == ["hours"])
        #expect(SettingsSearch.find("quiet zebra", in: entries).isEmpty)
        #expect(SettingsSearch.find("  ", in: entries).isEmpty)
    }

    @Test func accentsAndCaseDontMatter() {
        #expect(SettingsSearch.find("THEME", in: entries).map(\.id) == ["theme"])
        #expect(SettingsSearch.find("thè", in: entries).map(\.id) == ["theme"])
    }

    @Test func itMarksTheMatchedStartOfEachWord() {
        let text = "Sidefolk starts quietly when you log in."
        let ranges = SettingsSearch.matches(of: "quiet", in: text)
        #expect(ranges.map { String(text[$0]) } == ["quiet"])
        #expect(SettingsSearch.matches(of: "s", in: text).map { String(text[$0]) } == ["S", "s"])
    }
}
