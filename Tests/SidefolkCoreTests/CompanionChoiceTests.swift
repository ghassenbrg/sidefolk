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
        #expect(s.style(for: .spark) == CompanionStyle(color: .aqua, accessory: .none))
        #expect(s.style(for: .nori) == CompanionStyle(color: .mint, accessory: .scarf))
        #expect(s.size == .large)
    }

    @Test func unknownValuesFallBackWithoutLosingTheRest() throws {
        let s = try decode(#"{"companion": "pebble", "accent": "purple", "companionName": "Bob"}"#)
        #expect(s.companion == .mochi)
        #expect(s.style(for: .spark).color == .aqua)
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
        s.choose(.spark)
        s.setStyle(CompanionStyle(color: .coral, accessory: .scarf), for: .spark)
        s.choose(.mochi)
        #expect(s.style(for: .mochi) == CompanionStyle(color: .mint, accessory: .none))
        #expect(s.style(for: .spark) == CompanionStyle(color: .coral, accessory: .scarf))
        #expect(s.style(for: .ember) == CompanionStyle(color: .aqua, accessory: .none))
    }

    /// Folks are helpers, never the companion (D54): choosing one changes nothing, and one chosen before hands
    /// over to Mochi, keeping a name the person gave it.
    @Test func folksAreNotCompanions() throws {
        var s = AppSettings()
        s.choose(.scout)
        #expect(s.companion == .mochi && s.companionName == "Mochi")
        #expect(CompanionChoice(rawValue: "guard") == .guard_)
        let folk = try decode(#"{"companion":"scout","companionName":"Scout"}"#)
        #expect(folk.companion == .mochi && folk.companionName == "Mochi")
        let named = try decode(#"{"companion":"guard","companionName":"Bodyguard"}"#)
        #expect(named.companion == .mochi && named.companionName == "Bodyguard")
    }

    @Test func aNewSetupStartsWithMochi() {
        let settings = AppSettings()
        #expect(settings.companion == .mochi)
        #expect(settings.companionName == "Mochi")
    }

    /// The original robot is retired (D56): one chosen before hands over to Mochi, keeping a name the person gave it,
    /// and choosing it changes nothing.
    @Test func aSavedRobotBecomesMochi() throws {
        let named = try decode(#"{"companion":"sidefolk","accent":"coral","companionName":"Biscuit"}"#)
        #expect(named.companion == .mochi && named.companionName == "Biscuit")
        let plain = try decode(#"{"companion":"sidefolk","companionName":"Sidefolk"}"#)
        #expect(plain.companion == .mochi && plain.companionName == "Mochi")
        var s = AppSettings()
        s.choose(.sidefolk)
        #expect(s.companion == .mochi)
        let spark = try decode(#"{"companion":"spark","companionName":"Sidefolk"}"#)
        #expect(spark.companion == .spark && spark.companionName == "Spark", "the robot's name was a default, not the person's")
    }

    @Test func defaultNameFollowsTheCompanion() {
        var s = AppSettings()
        s.choose(.mochi)
        #expect(s.companionName == "Mochi")
        s.choose(.spark)
        #expect(s.companionName == "Spark")
        s.choose(.ember)
        #expect(s.companionName == "Ember")
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
        s.choose(.kiko)
        #expect(s.companionName == "Kiko")
    }

    /// A companion from "Made by you" goes by its own name, which gives way like a built-in's default,
    /// and a name the person chose survives both ways.
    @Test func customCompanionsComeWithTheirOwnName() throws {
        var s = AppSettings()
        s.choose(custom: "miso", name: "Miso")
        #expect(s.companionName == "Miso" && s.customCompanion == "miso" && !s.hasCustomName)
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(saved.customCompanionName == "Miso")
        s.choose(.mochi)
        #expect(s.companionName == "Mochi" && s.customCompanion == nil)
        s.companionName = "Bun"
        s.choose(custom: "miso", name: "Miso")
        #expect(s.companionName == "Bun")
        s.choose(.spark)
        #expect(s.companionName == "Bun")
    }

    /// D51, D59: every companion comes in 3D and can be 2D, the gallery's (Ember, Kiko, Nimbo …) too; the Folks are 2D only,
    /// whatever the stored settings say.
    @Test func eachCompanionIsDrawnTheWaysItCanBe() throws {
        var s = AppSettings()
        #expect(s.dimension(for: .mochi) == .threeD && s.dimension(for: .ember) == .threeD)
        #expect(s.dimension(for: .pip) == .twoD)
        s.setDimension(.twoD, for: .mochi)
        s.setDimension(.twoD, for: .kiko)
        s.setDimension(.threeD, for: .scout)
        #expect(s.dimension(for: .mochi) == .twoD)
        #expect(s.dimension(for: .kiko) == .twoD && s.dimension(for: .scout) == .twoD)
        #expect(s.dimension(for: .spark) == .threeD)
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.dimension(for: .mochi) == .twoD)
        // Hand-edited or older settings can't put a 2D-only companion in 3D.
        let odd = try decode(#"{"companion": "nimbo", "dimensions": {"nimbo": "2d", "pip": "3d"}}"#)
        #expect(odd.companion == .nimbo && odd.companionName == "Mochi")
        #expect(odd.dimension(for: .nimbo) == .twoD && odd.dimension(for: .pip) == .twoD)
        // A map with a value no version knows is left out whole: every companion comes as it comes.
        let unknown = try decode(#"{"dimensions": {"nimbo": "2d", "spark": "4d"}}"#)
        #expect(unknown.dimension(for: .nimbo) == .threeD && unknown.dimension(for: .spark) == .threeD)
    }

    @Test func theGalleryCompanionsAnswerToTheirNames() {
        var s = AppSettings()
        s.choose(.ember)
        #expect(s.companionName == "Ember")
        s.choose(.nimbo)
        #expect(s.companionName == "Nimbo")
        s.choose(.folio)
        #expect(s.companionName == "Folio" && s.dimension(for: .folio) == .threeD)
        for (choice, name) in [(CompanionChoice.iris, "Iris"), (.nori, "Nori"), (.purl, "Purl"), (.rune, "Rune")] {
            s.choose(choice)
            #expect(s.companionName == name && s.dimension(for: choice) == .threeD && choice.dimensions == [.threeD, .twoD])
        }
    }
}
