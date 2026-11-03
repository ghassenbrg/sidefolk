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

    /// Someone updating from before D130 keeps everything they set: the move changes their theme and nothing else, read from
    /// the bytes a saved copy really holds.
    @Test func anExistingPersonsSettingsSurviveTheMove() throws {
        var saved = settings("harbor", density: .compact)
        saved.companionName = "Biscuit"
        saved.themeSuccessorsOffered = ["dev.sidefolk.theme.daylight"]
        saved.sidebarIcons = .colorful
        let onDisk = try JSONEncoder().encode(saved)
        var read = try JSONDecoder().decode(AppSettings.self, from: onDisk)
        #expect(read.theme == "harbor", "a saved old id is read as it was, for the move to see it")
        _ = ThemeSuccession.step(&read) { _ in true }
        var expected = saved
        expected.theme = ThemeTokens.sidefolk.id
        #expect(read == expected)
        // And it stays moved across another launch.
        let again = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(read))
        #expect(again == expected)
    }

    /// A person's own followed folder, the painted Harbor chosen on purpose, and settings saved with no theme at all.
    @Test func whatIsNotTheOldDefaultIsLeftAlone() throws {
        var following = settings("harbor")
        following.themeFolder = "/Users/you/Themes/sunset"
        #expect(ThemeSuccession.step(&following) { _ in true } == nil)
        #expect(following.theme == "harbor")
        var painted = settings("dev.sidefolk.theme.harbor")
        #expect(ThemeSuccession.step(&painted) { _ in true } == nil)
        #expect(painted.theme == "dev.sidefolk.theme.harbor")
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).theme == ThemeTokens.sidefolk.id)
    }

    /// Moving a built-in to the gallery must not take it from whoever wears it: the setting stays, and it's fetched (D130).
    @Test func aThemeThatMovedToTheGalleryIsFetchedAndNotLost() {
        for id in ThemeSuccession.movedToGallery.keys {
            var s = settings(id)
            #expect(ThemeSuccession.step(&s) { _ in false } == nil, "it isn't retired")
            #expect(s.theme == id)
            #expect(ThemeSuccession.toFetch(s) { _ in false } == id)
            #expect(ThemeSuccession.toFetch(s) { _ in true } == nil, "already here")
            s.themeFolder = "/Users/you/Themes/mine"
            #expect(ThemeSuccession.toFetch(s) { _ in false } == nil)
        }
        #expect(ThemeSuccession.toFetch(settings(ThemeTokens.sidefolk.id)) { _ in false } == nil)
        // A retired theme whose successor moved reaches it in two steps.
        var old = settings("dev.sidefolk.theme.field-notes")
        _ = ThemeSuccession.step(&old) { _ in false }
        #expect(ThemeSuccession.toFetch(old) { _ in false } == "dev.sidefolk.theme.paper-garden")
    }

    @Test func currentThemesAndFollowedFoldersAreLeftAlone() {
        for id in ThemeLibrary.builtInOrder + Array(ThemeSuccession.movedToGallery.keys) + ["com.you.sunset"] {
            var s = settings(id)
            #expect(ThemeSuccession.step(&s) { _ in true } == nil, "\(id)")
            #expect(s.theme == id)
        }
        var followed = settings("dev.sidefolk.theme.field-notes")
        followed.themeFolder = "/tmp/my-theme"
        #expect(ThemeSuccession.step(&followed) { _ in false } == nil)
    }

    /// Every successor is a theme this Sidefolk carries or fetches for whoever wears it (D130), and no retired id is still built in.
    @Test func everySuccessorCanBeWorn() {
        for (id, old) in ThemeSuccession.retired {
            #expect(ThemeLibrary.builtInOrder.contains(old.successor) || ThemeSuccession.movedToGallery[old.successor] != nil, "\(id) → \(old.successor)")
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
