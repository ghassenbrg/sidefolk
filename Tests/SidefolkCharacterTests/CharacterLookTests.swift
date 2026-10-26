import AppKit
import Testing
@testable import SidefolkCharacter

/// One view, either companion: the app's contract (state, hit testing, anchor frame) holds for both.
@MainActor @Suite struct CharacterLookTests {
    static func art(_ name: String) throws -> SpriteSet {
        try #require(SpriteSet(folder: SpriteSetTests.repo.appendingPathComponent("Resources/Companions/\(name)")))
    }

    @Test func everyStateHasPoses() {
        for state in CharacterState.gallery {
            #expect(!SpriteChoreography.look(for: state).poses.isEmpty, "\(state.name)")
        }
        #expect(SpriteChoreography.look(for: .working(.notepad)).poses == [.write1, .write2])
        #expect(SpriteChoreography.look(for: .working(.laptop)).poses == [.work1, .work2])
        #expect(SpriteChoreography.look(for: .alert).poses == [.alert])
        #expect(SpriteChoreography.look(for: .success).poses == [.done])
        #expect(SpriteChoreography.look(for: .error).poses == [.sad])
        #expect(SpriteChoreography.look(for: .sleeping).poses == [.sleep])
        #expect(SpriteChoreography.look(for: .dragging).poses == [.dangle])
        #expect(SpriteChoreography.look(for: .celebrating).poses == [.wave, .done])
    }

    @Test func switchingKeepsStateAndTheRobotsAnchor() throws {
        let view = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        // The robot's anchor is the app's original inset: 17% across, 10% down.
        #expect(view.characterFrame == NSRect(x: 34, y: 20, width: 132, height: 160))
        view.setState(.thinking, animated: false)
        view.badges = [.count(2)]
        view.look = .sprites(try Self.art("mochi"))
        #expect(view.state == .thinking)
        #expect(view.characterFrame.minY == 20)
        #expect(view.characterFrame.width < 132)
        view.look = .sidefolk(.coral)
        #expect(view.state == .thinking)
        #expect(view.characterFrame == NSRect(x: 34, y: 20, width: 132, height: 160))
    }

    @Test func spriteClicksFollowTheVisiblePose() throws {
        let view = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.look = .sprites(try Self.art("mochi"))
        let body = view.characterFrame
        #expect(view.characterPath.contains(CGPoint(x: body.midX, y: body.minY + body.height * 0.3)))
        // Between the ears and beside the body is see-through.
        #expect(!view.characterPath.contains(CGPoint(x: body.midX, y: body.maxY - 4)))
        #expect(!view.characterPath.contains(CGPoint(x: 10, y: 100)))
        // Dragged, the body hangs higher: the outline moves with it.
        view.setState(.dragging, animated: false)
        #expect(view.characterPath.boundingBoxOfPath.minY > body.minY + 6)
    }

    @Test func accentRecoloursInPlace() {
        let view = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.setState(.listening, animated: false)
        let before = view.layer?.sublayers?.first
        view.look = .sidefolk(.mint)
        #expect(view.layer?.sublayers?.first === before)
        #expect(view.state == .listening)
    }

    @Test func labelsUseTheCompanionsName() {
        #expect(CharacterView.accessibilityLabel(for: .listening, name: "Mochi") == "Mochi is listening")
        let view = CharacterView(frame: .zero)
        view.displayName = "Spark"
        #expect(view.accessibilityLabel() == "Spark is here")
    }
}
