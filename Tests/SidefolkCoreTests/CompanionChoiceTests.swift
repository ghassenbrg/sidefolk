import Foundation
import Testing
@testable import SidefolkCore

@Suite struct CompanionChoiceTests {
    func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    @Test func settingsWithoutAnAppearanceUseTheRabbit() throws {
        let s = try decode(#"{"companionName": "Sidefolk", "size": "large"}"#)
        #expect(s.companion == .mochi)
        #expect(s.style(for: .mochi) == CompanionStyle(color: .aqua, accessory: .scarf))
        #expect(s.style(for: .sidefolk) == CompanionStyle(color: .aqua, accessory: .none))
        #expect(s.size == .large)
    }

    @Test func unknownValuesFallBackWithoutLosingTheRest() throws {
        let s = try decode(#"{"companion": "pebble", "accent": "purple", "companionName": "Bob"}"#)
        #expect(s.companion == .mochi)
        #expect(s.style(for: .sidefolk).color == .aqua)
        #expect(s.companionName == "Bob")
    }

    @Test func choiceAndStyleRoundTrip() throws {
        var s = AppSettings()
        s.choose(.spark)
        s.setStyle(CompanionStyle(color: .coral, accessory: .scarf), for: .spark)
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.companion == .spark)
        #expect(back.style(for: .spark) == CompanionStyle(color: .coral, accessory: .scarf))
        #expect(back.companionName == "Spark")
    }

    @Test func eachCompanionKeepsItsOwnStyle() {
        var s = AppSettings()
        s.setStyle(CompanionStyle(color: .mint, accessory: .none), for: .mochi)
        s.choose(.pip)
        s.setStyle(CompanionStyle(color: .coral, accessory: .scarf), for: .pip)
        s.choose(.mochi)
        #expect(s.style(for: .mochi) == CompanionStyle(color: .mint, accessory: .none))
        #expect(s.style(for: .pip) == CompanionStyle(color: .coral, accessory: .scarf))
        #expect(s.style(for: .scout) == CompanionStyle(color: .aqua, accessory: .none))
    }

    @Test func folksAnswerToTheirOwnNames() {
        var s = AppSettings()
        s.choose(.guard_)
        #expect(s.companionName == "Guard")
        s.choose(.scout)
        #expect(s.companionName == "Scout")
        #expect(CompanionChoice(rawValue: "guard") == .guard_)
    }

    @Test func aNewSetupStartsWithMochi() {
        let settings = AppSettings()
        #expect(settings.companion == .mochi)
        #expect(settings.companionName == "Mochi")
        #expect(CompanionChoice.allCases.contains(.sidefolk))
    }

    @Test func aSavedRobotAndItsCustomizationSurviveTheRebrand() throws {
        let settings = try decode(#"{"companion":"sidefolk","accent":"coral","companionName":"Biscuit"}"#)
        #expect(settings.companion == .sidefolk)
        #expect(settings.style(for: .sidefolk) == CompanionStyle(color: .coral, accessory: .none))
        #expect(settings.companionName == "Biscuit")
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
