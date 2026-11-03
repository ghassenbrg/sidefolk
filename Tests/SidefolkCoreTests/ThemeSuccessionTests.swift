import Foundation
import Testing
@testable import SidefolkCore

/// Themes that left Sidefolk (D92): a retired built-in becomes its successor, a theme that left the gallery stays and
/// its successor is offered once, and nothing else is touched.
@Suite struct ThemeSuccessionTests {
    func settings(_ theme: String, density: ThemeTokens.Density? = nil) -> AppSettings {
        var s = AppSettings()
        s.theme = theme
        s.density = density
        return s
    }

    @Test func aRetiredBuiltInBecomesItsSuccessor() {
        var s = settings("dev.sidefolk.theme.field-notes")
        let step = ThemeSuccession.step(&s) { _ in false }
        #expect(s.theme == "dev.sidefolk.theme.paper-garden")
        #expect(step == .moved(from: ThemeSuccession.retired["dev.sidefolk.theme.field-notes"]!, to: "dev.sidefolk.theme.paper-garden"))
        // Once moved, there is nothing more to say.
        #expect(ThemeSuccession.step(&s) { _ in true } == nil)
    }

    @Test func nightShiftKeepsItsCompactSpacingUnlessOneWasChosen() {
        var s = settings("dev.sidefolk.theme.night-shift")
        _ = ThemeSuccession.step(&s) { _ in false }
        #expect(s.theme == "dev.sidefolk.theme.night-studio" && s.density == .compact)
        var chosen = settings("dev.sidefolk.theme.night-shift", density: .regular)
        _ = ThemeSuccession.step(&chosen) { _ in false }
        #expect(chosen.density == .regular)
    }

    @Test func aGalleryThemeStillHereIsKeptAndItsSuccessorOfferedOnce() {
        var s = settings("dev.sidefolk.theme.daylight")
        let step = ThemeSuccession.step(&s) { $0 == "dev.sidefolk.theme.daylight" }
        #expect(s.theme == "dev.sidefolk.theme.daylight")
        #expect(step == .offer(ThemeSuccession.retired["dev.sidefolk.theme.daylight"]!, id: "dev.sidefolk.theme.daylight"))
        #expect(ThemeSuccession.step(&s) { _ in true } == nil)
    }

    @Test func aGalleryThemeThatIsGoneMovesToItsSuccessor() {
        var s = settings("dev.sidefolk.theme.daylight")
        #expect(ThemeSuccession.step(&s) { _ in false } != nil)
        #expect(s.theme == ThemeTokens.sidefolk.id)
    }

    /// The old default's id says nothing about who chose it: everyone moves to the new default once, and the whisper can say
    /// Harbor's still there, under its own id (D130).
    @Test func theOldDefaultMovesOnceToTheNewOne() {
        var s = settings("harbor")
        let step = ThemeSuccession.step(&s) { _ in true }
        #expect(s.theme == ThemeTokens.sidefolk.id)
        guard case .moved(let old, _)? = step else { Issue.record("not moved"); return }
        #expect(old.nameLivesOn)
        #expect(ThemeSuccession.step(&s) { _ in true } == nil)
    }

    @Test func currentThemesAndFollowedFoldersAreLeftAlone() {
        for id in ThemeLibrary.builtInOrder + ["com.you.sunset"] {
            var s = settings(id)
            #expect(ThemeSuccession.step(&s) { _ in true } == nil, "\(id)")
            #expect(s.theme == id)
        }
        var followed = settings("dev.sidefolk.theme.field-notes")
        followed.themeFolder = "/tmp/my-theme"
        #expect(ThemeSuccession.step(&followed) { _ in false } == nil)
    }

    /// Every successor is a theme this Sidefolk carries, and no retired id is still built in.
    @Test func everySuccessorShipsWithTheApp() {
        for (id, old) in ThemeSuccession.retired {
            #expect(ThemeLibrary.builtInOrder.contains(old.successor), "\(id) → \(old.successor)")
            #expect(!ThemeLibrary.builtInOrder.contains(id))
        }
    }

    /// The setting that remembers an offer survives a round trip, and older settings files read without it.
    @Test func theOfferIsRemembered() throws {
        var s = AppSettings()
        s.themeSuccessorsOffered = ["dev.sidefolk.theme.daylight"]
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.themeSuccessorsOffered == ["dev.sidefolk.theme.daylight"])
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).themeSuccessorsOffered.isEmpty)
    }
}
