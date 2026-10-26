import AppKit
import Testing
@testable import SidefolkCharacter

/// The alive layer (docs/research/lively-companions.md): moments, postures, the idle scheduler's
/// choices, petting and throwing. Minimal must stay the companion of D20.
@MainActor @Suite struct LivelinessTests {
    @Test(arguments: CharacterAntic.allCases)
    func everyMomentEndsWhereItStarted(_ antic: CharacterAntic) {
        let moment = Antics.make(antic)
        #expect(moment.duration > 0.3 && moment.duration < 4)
        for track in moment.tracks {
            #expect(track.keys.count == track.times.count, "\(antic) \(track.part)")
            #expect(track.times.first == 0 && track.times.last == 1, "\(antic) \(track.part)")
            #expect(zip(track.times, track.times.dropFirst()).allSatisfy { $0 <= $1 }, "\(antic) \(track.part)")
            for key in [track.keys.first!, track.keys.last!] {
                let t = key.transform(turnScale: 1)
                #expect(abs(t.a - 1) < 0.001 && abs(t.d - 1) < 0.001 && abs(t.b) < 0.001 && abs(t.tx) < 0.01 && abs(t.ty) < 0.01,
                        "\(antic) \(track.part) doesn't start and end at rest")
            }
        }
        // A face it shows goes away again by the end.
        if moment.faces.contains(where: { $0.mood != nil }) { #expect(moment.faces.last?.mood == nil || moment.faces.last!.at < 1) }
    }

    /// Rendered frames of every moment keep the whole body inside the window: nothing opaque
    /// touches the image's edge (hops, stretches and the tumble included).
    @Test(arguments: CharacterSpecies.allCases)
    func momentsStayInTheWindow(_ species: CharacterSpecies) {
        for antic in CharacterAntic.allCases {
            for posture in [CharacterPosture.stand, .lie] where posture == .stand || Mind.lying.contains(antic) {
                let frames = CharacterRenderer.frames(of: antic, count: 7, size: CGSize(width: 80, height: 80), scale: 1,
                                                      look: CharacterLook(species), posture: posture)
                for (i, frame) in frames.enumerated() {
                    #expect(!touchesEdge(frame), "\(species) \(antic) frame \(i) \(posture) leaves the window")
                }
            }
        }
    }

    @Test(arguments: CharacterSpecies.allCases)
    func postureIsForIdleOnly(_ species: CharacterSpecies) {
        let director = Director(CharacterLook(species), live: false)
        let standing = director.restPose
        director.setPosture(.sit, animated: false)
        #expect(director.posture == .sit)
        #expect(director.restPose.squash.height < standing.squash.height)
        #expect(director.restPose.feetSplay > 0)
        director.setPosture(.lie, animated: false)
        #expect(director.restPose.squash.height < 0.9)
        // Any other state stands up, and posture can't be changed there.
        director.show(.thinking, animated: false)
        #expect(director.posture == .stand)
        director.setPosture(.sit, animated: false)
        #expect(director.posture == .stand)
        let v = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        v.look = CharacterLook(species)
        v.setPosture(.lie, animated: false)
        let outline = v.characterPath.boundingBoxOfPath
        #expect(outline.minX >= 0 && outline.maxX <= 200 && outline.minY >= 0 && outline.maxY <= 200)
    }

    @Test func aMomentAnimatesThenAStateEndsIt() {
        let director = Director(CharacterLook(.mochi), live: true)
        director.perform(Antics.hop, name: .hop)
        #expect(director.performing == .hop)
        #expect(director.rig.gesture.animation(forKey: "antic") != nil)
        #expect(director.rig.gesture.animation(forKey: "antic")?.repeatCount == 0)
        director.show(.thinking, animated: true)
        #expect(director.performing == nil)
        #expect(director.rig.gesture.animation(forKey: "antic") == nil)
        #expect(director.anticTimers.isEmpty)
    }

    @Test func aBoopPlaysOnWhileTheAskPanelOpens() {
        let director = Director(CharacterLook(.mochi), live: true)
        director.perform(Antics.boop, name: .boop)
        director.show(.listening, animated: true)
        #expect(director.performing == .boop)
        director.show(.thinking, animated: true)
        #expect(director.performing == nil)
    }

    @Test func reducedMotionKeepsOnlyTheFaces() {
        let director = Director(CharacterLook(.mochi), live: true)
        director.reducedMotion = true
        director.perform(Antics.boop, name: .boop)
        #expect(director.performing == .boop)
        #expect(director.rig.gesture.animation(forKey: "antic") == nil)
        #expect(director.anticLayers.isEmpty)
    }

    @Test func aMomentLooksAwayThenGivesTheEyesBack() {
        let director = Director(CharacterLook(.mochi), live: true)
        director.setGaze(CGVector(dx: 0.5, dy: 0))
        director.perform(Antics.glance.flipped, name: .glance)
        director.cancelAntic(smooth: false)
        #expect(director.anticLook == nil)
        #expect(director.hostGaze == CGVector(dx: 0.5, dy: 0))
    }

    @Test func minimalIsTheCompanionOfD20() {
        let v = CharacterView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        #expect(v.liveliness == .minimal)
        let profile = Liveliness.minimal.profile
        #expect(profile.every == nil && profile.sitAfter == nil)
        #expect(profile.antics.isEmpty && !profile.newsReactions)
        #expect(!v.reactsToNews)
        #expect(Mind(profile: profile).nextTick(hour: 12, roll: 0.5) == nil)
    }

    // MARK: Choosing

    func decide(_ mind: inout Mind, posture: CharacterPosture = .stand, quiet: TimeInterval = 10, sinceKey: TimeInterval = 60,
                hour: Int = 14, window: CGRect? = CGRect(x: 0, y: 0, width: 800, height: 600), at now: Date = Date(),
                roll: Double = 0.5) -> Decision {
        mind.decide(posture: posture, quiet: quiet, sinceKey: sinceKey, now: now, hour: hour, window: window, pointer: .zero,
                    roll: { roll })
    }

    @Test func itHoldsStillWhileThePersonTypes() {
        var mind = Mind(profile: Liveliness.lively.profile)
        let now = Date()
        // One look at the window the words go into, then stillness.
        #expect(decide(&mind, sinceKey: 0.4, at: now) == .moment(.glance, toward: CGPoint(x: 400, y: 300)))
        for i in 1...10 {
            #expect(decide(&mind, sinceKey: 0.4, at: now.addingTimeInterval(Double(i) * 4)) == .still)
        }
    }

    @Test func quietTimeSitsThenLiesDownSoonerAtNight() {
        var mind = Mind(profile: Liveliness.balanced.profile)
        #expect(decide(&mind, quiet: 60) != .posture(.sit))
        #expect(decide(&mind, quiet: 101) == .posture(.sit))
        #expect(decide(&mind, posture: .sit, quiet: 230) == .posture(.lie))
        #expect(decide(&mind, quiet: 60, hour: 23) == .posture(.sit))
        // Lying down, only quiet moments fit.
        for roll in stride(from: 0.0, to: 1, by: 0.05) {
            if case .moment(let antic, _) = decide(&mind, posture: .lie, quiet: 10, roll: roll) {
                #expect(Mind.lying.contains(antic))
            }
        }
    }

    @Test func varietyAndRareMomentsStayRare() {
        var mind = Mind(profile: Liveliness.lively.profile)
        var last: CharacterAntic?
        var rare: [Date] = []
        let start = Date()
        for i in 0..<400 {
            let now = start.addingTimeInterval(Double(i) * 15)
            guard case .moment(let antic, _) = decide(&mind, at: now, roll: Double((i * 37) % 100) / 100) else { continue }
            #expect(antic != last, "the same moment twice in a row")
            last = antic
            if Mind.rare.contains(antic) { rare.append(now) }
        }
        #expect(!rare.isEmpty)
        #expect(zip(rare, rare.dropFirst()).allSatisfy { $1.timeIntervalSince($0) >= Mind.rareGap })
    }

    @Test func nightIsSleepierAndCalmer() {
        var mind = Mind(profile: Liveliness.lively.profile)
        for roll in stride(from: 0.0, to: 1, by: 0.02) {
            if case .moment(let antic, _) = decide(&mind, hour: 2, roll: roll) {
                #expect(antic != .hop && antic != .wiggle)
            }
        }
        #expect(mind.nextTick(hour: 2, roll: 0.5)! > mind.nextTick(hour: 14, roll: 0.5)!)
    }

    @Test func peeksAimAtTheActiveWindow() {
        var mind = Mind(profile: Liveliness.balanced.profile)
        var aimed = false
        for roll in stride(from: 0.0, to: 1, by: 0.01) {
            if case .moment(.peek, let target) = decide(&mind, window: CGRect(x: 1000, y: 200, width: 400, height: 300), roll: roll) {
                #expect(target == CGPoint(x: 1200, y: 350))
                aimed = true
            }
            // No window known: no peeks.
            if case .moment(let antic, _) = decide(&mind, window: nil, roll: roll) { #expect(antic != .peek) }
        }
        #expect(aimed)
    }

    // MARK: Hands

    @Test func strokingBackAndForthPets() {
        var detector = PettingDetector()
        var t: TimeInterval = 0
        var petted = false
        // Two passes over the body and the start of a third.
        for x in Array(stride(from: 80.0, through: 120, by: 4)) + Array(stride(from: 120.0, through: 80, by: -4))
            + Array(stride(from: 80.0, through: 100, by: 4)) {
            t += 0.016
            petted = petted || detector.add(CGPoint(x: x, y: 100), inside: true, at: t)
        }
        #expect(petted)
        // One pass across is not a pet; nor is a slow or interrupted stroke.
        var once = PettingDetector()
        #expect(!stride(from: 60.0, through: 140, by: 2).enumerated().contains { once.add(CGPoint(x: $1, y: 90), inside: true, at: Double($0) * 0.016) })
        var slow = PettingDetector()
        let back = [80.0, 120, 80, 120, 80]
        #expect(!back.enumerated().contains { slow.add(CGPoint(x: $1, y: 90), inside: true, at: Double($0) * 0.6) })
        var outside = PettingDetector()
        #expect(!back.enumerated().contains { outside.add(CGPoint(x: $1, y: 90), inside: $0 % 2 == 0, at: Double($0) * 0.05) })
    }

    @Test func aThrowLandsOnTheFloorInsideTheScreen() {
        let fling = Fling(from: CGPoint(x: 500, y: 400), velocity: CGVector(dx: 2400, dy: 900), floor: 0, span: 0...1200)
        #expect(Fling.isToss(CGVector(dx: 2400, dy: 900)) && !Fling.isToss(CGVector(dx: 300, dy: 100)))
        #expect(fling.duration >= 0.35 && fling.duration <= 1.2)
        let end = fling.position(at: fling.duration)
        #expect(abs(end.y) < 0.5)
        #expect(end.x > 500 && end.x <= 1200)
        for t in stride(from: 0, through: fling.duration, by: 0.05) {
            let p = fling.position(at: t)
            #expect(p.y >= 0 && p.x >= 0 && p.x <= 1200)
        }
        let soft = Fling(from: CGPoint(x: 500, y: 40), velocity: CGVector(dx: 1200, dy: 0), floor: 0, span: 0...1200)
        #expect(soft.impact < fling.impact)
    }

    // MARK: Helpers

    func touchesEdge(_ image: CGImage) -> Bool {
        let w = image.width, h = image.height
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[y * w * 4 + x * 4 + 3] }
        for i in 0..<w where alpha(i, 0) > 40 || alpha(i, h - 1) > 40 { return true }
        for j in 0..<h where alpha(0, j) > 40 || alpha(w - 1, j) > 40 { return true }
        return false
    }
}
