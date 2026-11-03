import Foundation
import Testing
@testable import SidefolkCore

/// Playtime's games (D101), installed from the add-ons checkout and played over the surface channel inside the sandbox by a bot that presses what each scene offers: every scene
/// reads, with its pictures and sounds checked against the pack, a game can't answer with anything Sidefolk would refuse, and the menu opens every game.
struct PlaytimeGamesSandboxTests {
    static let games = ["daily_word", "trivia", "tictactoe", "copy_me", "quick_paws", "which_cup", "higher_lower", "guess_animal",
                        "balloon_words", "last_stick", "memory_pairs", "rock_paper_scissors", "plots", "seesaw", "sudoku", "blossoms"]

    /// A move the scene offers, as a person might press.
    static func botMove(_ scene: SurfaceScene, step: Int) -> SurfaceMove? {
        if scene.after != nil { return .next }
        let areas = scene.areas.filter { !$0.disabled }
        guard !areas.isEmpty else { return nil }
        let area = areas[step % areas.count]
        return .click(area: area.id, value: area.value, ms: nil)
    }

    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons), arguments: ["en", "ja", "ar"])
    func everyGamesScenesRead(language: String) async throws {
        let h = try HostEnv()
        let installed = try await h.host.install(from: ExtFixtures.builtIn("playtime"))
        let info = try #require(h.host.surfaceShelf.all.first { $0.extensionId == installed.id && $0.surface == "play" })
        #expect(info.sounds && !info.activity && info.height <= SurfaceLimits.maxHeight)
        // The menu first: it offers every game, and Surprise me.
        let (menuSession, menu) = try await h.host.openSurface(info, language: language)
        let offered = Set(menu.areas.filter { $0.id == "open" }.compactMap(\.value))
        #expect(offered.isSuperset(of: Self.games) && offered.subtracting(Self.games).isSubset(of: ["random"]))
        await h.host.closeSurface(info: info, session: menuSession, reason: .finished)
        var now = Date()
        for game in Self.games {
            var (session, scene) = try await h.host.openSurface(info, language: language, arguments: ["game": .string(game)])
            #expect(scene.title != nil && scene.back, "\(game)")
            for step in 0..<24 {
                guard let move = Self.botMove(scene, step: step) else { break }
                now = now.addingTimeInterval(0.2)
                if let next = try await h.host.moveSurface(info: info, session: session, move: move, now: now) { scene = next }
            }
            await h.host.closeSurface(info: info, session: session, reason: .finished)
            session = ""
        }
    }

    /// The desktop's coin, dice and hands: an overlay that plays what it was given, comes back when it has landed, offers Again where it should and goes by itself.
    @Test(.enabled(if: ExtFixtures.hasAddons, ExtFixtures.noAddons), arguments: ["en", "ar"])
    func theTossOverlay(language: String) async throws {
        let h = try HostEnv()
        let installed = try await h.host.install(from: ExtFixtures.builtIn("playtime"))
        let info = try #require(h.host.surfaceShelf.all.first { $0.extensionId == installed.id && $0.surface == "toss" })
        #expect(info.presentation == .overlay && !info.activity)
        let cases: [([String: JSONValue], Bool)] = [(["kind": "coin", "flips": "101"], true), (["kind": "dice", "sides": 20, "rolls": "20", "modifier": 0], true),
                                                    (["kind": "dice", "sides": 6, "rolls": "1,2,3,4,5,6,1,2,3,4", "modifier": -3], true),
                                                    (["kind": "hands", "person": "rock", "companion": "paper"], false)]
        var now = Date()
        for (arguments, again) in cases {
            let (session, flying) = try await h.host.openSurface(info, language: language, arguments: arguments)
            #expect(flying.after != nil && flying.areas.isEmpty, "\(arguments)")
            now = now.addingTimeInterval(3)
            let landed = try #require(try await h.host.moveSurface(info: info, session: session, move: .next, now: now))
            #expect(landed.after == nil && landed.close, "\(arguments)")
            #expect(landed.areas.contains { $0.id == "again" } == again, "\(arguments)")
            await h.host.closeSurface(info: info, session: session, reason: .finished)
        }
    }
}
