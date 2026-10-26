import AppKit
import Testing
@testable import SidefolkCharacter

/// One view, any companion: the app's contract (state, hit testing, anchor frame) holds for all.
@MainActor @Suite struct CharacterLookTests {
    /// A 200 pt view: view points are canvas units.
    func view(_ species: CharacterSpecies, style: CharacterStyle? = nil) -> CharacterView {
        let view = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.look = CharacterLook(species, style: style)
        return view
    }

    @Test(arguments: CharacterSpecies.allCases)
    func everyCompanionHoldsEveryState(_ species: CharacterSpecies) {
        let v = view(species)
        for state in CharacterState.gallery {
            v.setState(state, animated: false)
            #expect(v.state == state)
            let outline = v.characterPath.boundingBoxOfPath
            #expect(outline.width > 50 && outline.height > 50, "\(species) \(state.name)")
            // Nothing pokes out of the window: the canvas is the view.
            #expect(outline.minX >= 0 && outline.maxX <= 200 && outline.maxY <= 200, "\(species) \(state.name)")
        }
        #expect(v.characterFrame.minY == 20)
    }

    @Test func switchingKeepsStateAndTheRobotsAnchor() {
        let v = view(.sidefolk)
        // The robot's anchor is the app's original inset: 17% across, 10% down.
        #expect(v.characterFrame == NSRect(x: 34, y: 20, width: 132, height: 160))
        v.setState(.thinking, animated: false)
        v.badges = [.count(2)]
        v.look = CharacterLook(.mochi)
        #expect(v.state == .thinking)
        #expect(v.characterFrame.width < 132)
        v.look = CharacterLook(.sidefolk, style: CharacterStyle(color: .coral, accessory: .none))
        #expect(v.state == .thinking)
        #expect(v.characterFrame == NSRect(x: 34, y: 20, width: 132, height: 160))
    }

    @Test func mochisClicksFollowItsShape() {
        let v = view(.mochi)
        let body = v.characterFrame
        #expect(v.characterPath.contains(CGPoint(x: 100, y: 95)))          // the face
        #expect(v.characterPath.contains(CGPoint(x: 70, y: 165)))          // an ear
        #expect(!v.characterPath.contains(CGPoint(x: 100, y: 160)))        // between the ears
        #expect(!v.characterPath.contains(CGPoint(x: 15, y: 100)))
        // Dragged, the body hangs higher: the outline moves with it.
        v.setState(.dragging, animated: false)
        #expect(v.characterPath.boundingBoxOfPath.minY > body.minY + 6)
    }

    @Test func earsDroopForTroubleAndPerkForNews() {
        let v = view(.mochi)
        let rest = v.characterPath.boundingBoxOfPath
        v.setState(.error, animated: false)
        let sad = v.characterPath.boundingBoxOfPath
        #expect(sad.maxY < rest.maxY - 4)
        #expect(sad.width > rest.width)
        let (left, right) = SoftExpressions.ears(.listening)
        #expect(left > 0 && right < 0)
    }

    @Test func softFacesChangeWithTheState() {
        let face = Species.mochi.face
        var sleeping = Choreography.look(for: .sleeping)
        SoftExpressions.adapt(&sleeping, for: .sleeping, face: face)
        #expect(sleeping.pose.eyeL == Ink.closed)
        #expect(sleeping.pose.shine == 0)
        var idle = Choreography.look(for: .idle)
        SoftExpressions.adapt(&idle, for: .idle, face: face)
        #expect(idle.pose.eyeL == Ink.bead)
        #expect(idle.pose.mouthShown == 0)
    }

    @Test func aStyleRedressesInPlace() {
        let v = view(.spark)
        v.setState(.listening, animated: false)
        let before = v.layer?.sublayers?.first
        v.look = CharacterLook(.spark, style: CharacterStyle(color: .coral, accessory: .scarf))
        #expect(v.layer?.sublayers?.first === before)
        #expect(v.state == .listening)
    }

    @Test func aScarfCatchesClicksToo() {
        let plain = view(.spark).characterPath
        let dressed = view(.spark, style: CharacterStyle(color: .aqua, accessory: .scarf)).characterPath
        #expect(!plain.contains(CGPoint(x: 120, y: 66)) || dressed.contains(CGPoint(x: 120, y: 66)))
        #expect(dressed.boundingBoxOfPath.width >= plain.boundingBoxOfPath.width)
    }

    @Test func labelsUseTheCompanionsName() {
        #expect(CharacterView.accessibilityLabel(for: .listening, name: "Mochi") == "Mochi is listening")
        let v = CharacterView(frame: .zero)
        v.displayName = "Spark"
        #expect(v.accessibilityLabel() == "Spark is here")
    }
}
