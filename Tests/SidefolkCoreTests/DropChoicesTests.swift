import Foundation
import Testing
@testable import SidefolkCore

/// The drop card's four choices by what was dropped (D84).
@Suite struct DropChoicesTests {
    @Test func eachKindHasFourChoicesTheLikeliestFirst() {
        #expect(DropChoices.choices(for: .file) == [.save, .watch, .ask, .openWith])
        #expect(DropChoices.choices(for: .folder) == [.save, .watch, .ask, .openWith])
        #expect(DropChoices.choices(for: .text) == [.save, .remind, .ask, .copy])
        #expect(DropChoices.choices(for: .link) == [.save, .watch, .ask, .remind])
    }

    static func offer(_ id: String = "dev.test.player", kinds: [ExtensionManifest.DropMeta.Kind] = [.link],
                      patterns: [String] = ["https://*.mp4", "https://*.m3u8", "https://*.mov"]) -> ExtensionDropAction {
        ExtensionDropAction(extensionId: id, extensionName: "Player", key: "play", title: "Play", kinds: kinds, patterns: patterns, tool: "ext.player.play",
                            input: ["url": "{value}"])
    }

    /// An extension's offer takes the reminder's place on a link, and adds to anything else's four (D100).
    @Test func anOfferTakesTheLinksReminderPlace() {
        #expect(DropChoices.choices(for: .link, offers: 1) == [.save, .watch, .ask])
        #expect(DropChoices.choices(for: .file, offers: 1) == [.save, .watch, .ask, .openWith])
    }

    @Test func offersFollowKindAndPattern() {
        let all = [Self.offer()]
        let film = "https://cdn.example.com/films/trip.MP4?token=abc"
        #expect(DropChoices.offers(for: .link, value: film, among: all).count == 1)
        #expect(DropChoices.offers(for: .link, value: "https://example.com/live/index.m3u8", among: all).count == 1)
        // A page with a video in it, or a plain-HTTP file, isn't one this author asked for.
        #expect(DropChoices.offers(for: .link, value: "https://www.youtube.com/watch?v=abc", among: all).isEmpty)
        #expect(DropChoices.offers(for: .link, value: "http://example.com/film.mp4", among: all).isEmpty)
        #expect(DropChoices.offers(for: .file, value: "/tmp/film.mp4", among: all).isEmpty)
        let files = [Self.offer(kinds: [.file], patterns: ["*.pdf"])]
        #expect(DropChoices.offers(for: .file, value: "/Users/a/Invoice April.PDF", among: files).count == 1)
        #expect(DropChoices.offers(for: .file, value: "/Users/a.pdf/notes.txt", among: files).isEmpty)
        // No pattern means anything of that kind; never more than a card holds.
        let many = (0..<5).map { Self.offer("dev.test.p\($0)", kinds: [.text], patterns: []) }
        #expect(DropChoices.offers(for: .text, value: "words", among: many).count == 3)
    }

    @Test func whatWasDroppedGoesWhereTheManifestSays() {
        #expect(Self.offer().input(for: "https://a.example/b.mp4") == ["url": "https://a.example/b.mp4"])
    }

    @Test func aGlobIsLinearAndWhole() {
        #expect(ExtensionDropAction.glob("*.mp4", matches: "a.mp4"))
        #expect(!ExtensionDropAction.glob("*.mp4", matches: "a.mp4x"))
        #expect(ExtensionDropAction.glob("a?c*", matches: "abcdef"))
        #expect(!ExtensionDropAction.glob(String(repeating: "*a", count: 40) + "b", matches: String(repeating: "a", count: 2000)))
    }
}

/// Miraya's "Play on TV" lives in its manifest now, not in the app (D100): installed, a video link offers it and runs its own tool; gone, the
/// link keeps its reminder.
@Suite struct DropActionFromManifestTests {
    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons)) func aVideoLinkOffersWhatItsExtensionDeclares() throws {
        let manifest = try ExtensionManifest.decode(Data(contentsOf: ExtFixtures.source("miraya").appendingPathComponent(ExtensionManifest.fileName)))
        let meta = try #require(manifest.drops.first)
        #expect(meta.tool == "play_on_tv" && manifest.tools["play_on_tv"] != nil)
        let action = ExtensionDropAction(extensionId: manifest.id, extensionName: manifest.name, key: meta.id, title: meta.title, kinds: meta.kinds, patterns: meta.patterns,
                                         tool: "ext.miraya.play_on_tv", input: meta.input)
        #expect(DropChoices.offers(for: .link, value: "https://cdn.example.com/films/trip.mp4", among: [action]).count == 1)
        #expect(DropChoices.offers(for: .link, value: "https://example.com/a/Clip.MOV", among: [action]).count == 1)
        #expect(DropChoices.offers(for: .link, value: "https://www.youtube.com/watch?v=abc", among: [action]).isEmpty)
        #expect(DropChoices.offers(for: .link, value: "http://example.com/film.mp4", among: [action]).isEmpty)
        #expect(action.input(for: "https://a.example/b.mp4") == ["url": "https://a.example/b.mp4"])
    }
}
