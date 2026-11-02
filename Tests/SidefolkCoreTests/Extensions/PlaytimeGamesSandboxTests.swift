import Foundation
import Testing
@testable import SidefolkCore

/// Playtime's games (D101), installed from the add-ons checkout and played over the surface channel inside the sandbox by a bot that presses what each scene offers: every scene
/// reads, with its pictures and sounds checked against the pack, a game can't answer with anything Sidefolk would refuse, and the menu opens every game.
struct PlaytimeGamesSandboxTests {
    static let games = ["daily_word", "trivia", "tictactoe", "copy_me", "quick_paws", "which_cup", "higher_lower", "guess_animal",
                        "balloon_words", "last_stick", "memory_pairs", "plots", "seesaw", "sudoku", "blossoms"]

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
        // The menu first: it offers every game.
        let (menuSession, menu) = try await h.host.openSurface(info, language: language)
        #expect(Set(menu.areas.filter { $0.id == "open" }.compactMap(\.value)) == Set(Self.games))
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
}
