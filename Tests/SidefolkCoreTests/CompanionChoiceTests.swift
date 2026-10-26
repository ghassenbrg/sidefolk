import Foundation
import Testing
@testable import SidefolkCore

@Suite struct CompanionChoiceTests {
    func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    @Test func olderSettingsKeepTheRobot() throws {
        let s = try decode(#"{"companionName": "Sidefolk", "size": "large"}"#)
        #expect(s.companion == .sidefolk)
        #expect(s.accent == .aqua)
        #expect(s.size == .large)
    }

    @Test func unknownValuesFallBackWithoutLosingTheRest() throws {
        let s = try decode(#"{"companion": "pebble", "accent": "purple", "companionName": "Bob"}"#)
        #expect(s.companion == .sidefolk)
        #expect(s.accent == .aqua)
        #expect(s.companionName == "Bob")
    }

    @Test func choiceAndAccentRoundTrip() throws {
        var s = AppSettings()
        s.choose(.spark)
        s.accent = .coral
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.companion == .spark)
        #expect(back.accent == .coral)
        #expect(back.companionName == "Spark")
    }

    @Test func defaultNameFollowsTheCompanion() {
        var s = AppSettings()
        s.choose(.mochi)
        #expect(s.companionName == "Mochi")
        s.choose(.spark)
        #expect(s.companionName == "Spark")
        s.choose(.sidefolk)
        #expect(s.companionName == "Sidefolk")
    }

    @Test func aCustomNameStays() {
        var s = AppSettings()
        s.companionName = "Biscuit"
        s.choose(.mochi)
        #expect(s.companion == .mochi)
        #expect(s.companionName == "Biscuit")
    }

    @Test func theCompanionAnswersToItsName() {
        let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test", companionNames: ["sidefolk", "Mochi"])
        let intent = parser.parse("Mochi, remind me in 20 min to call mom", now: TimeTest.wednesday10)?.intent
        #expect(intent == .remind(title: "Call mom", when: TimeTest.date(2025, 10, 22, 10, 20), recurrence: nil))
    }

    @Test func emptyOrDifferentlyCasedDefaultsAreNotCustom() {
        var s = AppSettings()
        s.companionName = "  "
        s.choose(.spark)
        #expect(s.companionName == "Spark")
        s.companionName = "mochi"
        s.choose(.sidefolk)
        #expect(s.companionName == "Sidefolk")
    }
}
