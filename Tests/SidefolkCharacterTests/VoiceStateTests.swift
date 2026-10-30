import AppKit
import Testing
@testable import SidefolkCharacter

/// Hearing (the microphone is on) and talking (the mouth follows the voice), for every companion (D34).
@MainActor @Suite struct VoiceStateTests {
    func view(_ species: CharacterSpecies) -> CharacterView {
        let view = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.look = CharacterLook(species)
        return view
    }

    @Test func hearingPutsBothEarsUp() {
        let (left, right) = SoftExpressions.ears(.hearing)
        #expect(left < 0 && right < 0)
        let v = view(.mochi)
        v.setState(.listening, animated: false)
        let listening = v.characterPath.boundingBoxOfPath
        v.setState(.hearing, animated: false)
        let hearing = v.characterPath.boundingBoxOfPath
        // Both ears up: taller and narrower than one ear up and one relaxed.
        #expect(hearing.maxY > listening.maxY)
        #expect(hearing.width < listening.width)
        #expect(CharacterView.accessibilityLabel(for: .hearing, name: "Mochi") == "Mochi is listening to you")
    }

    @Test func theTalkingMouthGrowsWithTheVoiceOnOneSkeleton() {
        let shut = SoftRig.talkingMouth(0, width: 5)
        let open = SoftRig.talkingMouth(1, width: 5)
        #expect(shut.points.count == 7 && open.points.count == 7)
        let height = { (s: Stroke) in s.path(at: .zero).boundingBoxOfPath.height + s.width }
        #expect(height(open) > height(shut) * 1.8)
    }

    /// Speaking adds no repeating animation: the mouth moves only when a level arrives, and stops with it.
    @Test(arguments: [CharacterSpecies.mochi, .spark, .scout])
    func talkingNeverLoops(_ species: CharacterSpecies) {
        let v = view(species)
        let window = NSWindow(contentRect: v.frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = v
        v.setState(.success, animated: false)
        let before = loops(in: v.layer)
        for level in [0.2, 0.9, 0.4, 0.7] { v.speak(level) }
        v.speak(nil)
        #expect(loops(in: v.layer) == before)
        window.contentView = nil
    }

    private func loops(in layer: CALayer?) -> Int {
        guard let layer else { return 0 }
        let own = (layer.animationKeys() ?? []).filter { layer.animation(forKey: $0)?.repeatCount == .infinity }.count
        return own + (layer.sublayers ?? []).reduce(0) { $0 + loops(in: $1) }
    }
}
