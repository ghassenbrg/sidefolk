import Foundation
import Testing
@testable import SidefolkCore

/// The drop card's four choices by what was dropped (D88).
@Suite struct DropChoicesTests {
    @Test func eachKindHasFourChoicesTheLikeliestFirst() {
        #expect(DropChoices.choices(for: .file) == [.save, .watch, .ask, .openWith])
        #expect(DropChoices.choices(for: .folder) == [.save, .watch, .ask, .openWith])
        #expect(DropChoices.choices(for: .text) == [.save, .remind, .ask, .copy])
        let page = URL(string: "https://example.com/pricing")!
        #expect(DropChoices.choices(for: .link, link: page, canPlayOnTV: true) == [.save, .watch, .ask, .remind])
    }

    @Test func aVideoLinkPlaysOnTheTVOnlyWithMiraya() {
        let film = URL(string: "https://cdn.example.com/films/trip.mp4")!
        #expect(DropChoices.choices(for: .link, link: film, canPlayOnTV: true).last == .playOnTV)
        #expect(DropChoices.choices(for: .link, link: film, canPlayOnTV: false).last == .remind)
    }

    @Test func onlyTheVideoItselfOverHTTPSIsAVideoLink() {
        #expect(DropChoices.isVideoLink(URL(string: "https://example.com/live/index.m3u8")!))
        #expect(DropChoices.isVideoLink(URL(string: "https://example.com/a/Clip.MOV")!))
        // A page with a video in it, or a plain-HTTP file, isn't one a TV can be handed.
        #expect(!DropChoices.isVideoLink(URL(string: "https://www.youtube.com/watch?v=abc")!))
        #expect(!DropChoices.isVideoLink(URL(string: "http://example.com/film.mp4")!))
    }
}
