import QuartzCore

/// Moments and postures. A moment is one keyframe animation per moved layer plus a few one-shot
/// timers for its face and gaze beats; nothing repeats, and nothing runs once it is over, so the
/// D20 settling and the occlusion pause hold whatever the liveliness level.
extension Director {
    /// The state's pose as held in the current posture: what a moment's face returns to.
    var restPose: Pose {
        guard posture != .stand else { return look.pose }
        return Moods.posture(posture, on: look.pose) { rig.express($0, on: $1, mirrored: false) }
    }

    var performing: CharacterAntic? { antic?.name }

    /// Everything the body draws at rest (hats, held things and ear tips included), in canvas units.
    var bodyBounds: CGRect {
        Motion.still { rig.stage.layoutIfNeeded() }
        return Layers.visibleBounds(rig.gesture, in: rig.stage)
    }

    /// Sits, lies down or stands up (idle only); the body springs there, the ears flop.
    func setPosture(_ next: CharacterPosture, animated: Bool) {
        guard state == .idle, next != posture else { return }
        posture = next
        let animate = animated && live
        if animate && reducedMotion { crossfade(rig.stage) }
        rig.apply(currentFace, animate && !reducedMotion ? .spring : .instant)
    }

    /// Plays a moment from now. Under reduced motion only its faces show (crossfaded), still and brief.
    func perform(_ moment: Antic, name: CharacterAntic?) {
        guard live, !paused else { return }
        cancelAntic(smooth: true)
        let moment = moment.fitted(to: bodyBounds)
        antic = (name, moment)
        if !reducedMotion {
            for track in moment.tracks {
                for mover in rig.movers(track.part) {
                    let values = track.keys.map { Motion.transform($0.transform(turnScale: mover.turn)) }
                    let animation = Motion.keyframes("transform", values, duration: moment.duration, times: track.times)
                    // Answers to the person run at the display's pace; idle moments are capped like loops.
                    animation.preferredFrameRateRange = moment.snappy
                        ? CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                        : CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
                    mover.layer.add(animation, forKey: "antic")
                    anticLayers.append(mover.layer)
                }
            }
            // A moment replaces a gesture that is still playing on the same layer.
            rig.gesture.removeAnimation(forKey: "gesture")
        }
        let beats = Set(moment.faces.map(\.at) + (reducedMotion ? [] : moment.looks.map(\.at))).sorted()
        for at in beats {
            schedule(after: at * moment.duration) { [weak self] in self?.beat(at) }
        }
        // At its end every key is back at rest, so the animations can simply go.
        schedule(after: moment.duration) { [weak self] in self?.cancelAntic(smooth: false) }
        sharpen()
    }

    /// Ends the moment now: its animations glide back to rest when `smooth`, and the face and gaze
    /// return (a new state passes `restoreFace: false`: it applies its own pose next).
    func cancelAntic(smooth: Bool, restoreFace: Bool = true) {
        guard let (_, moment) = antic else { return }
        anticTimers.forEach { $0.invalidate() }
        anticTimers = []
        let snapshots = smooth ? Self.snapshot(anticLayers) : []
        anticLayers.forEach { $0.removeAnimation(forKey: "antic") }
        anticLayers = []
        Self.glide(snapshots)
        let showsFace = firedBeat.map { moment.mood(at: $0) != nil } ?? false
        antic = nil
        firedBeat = nil
        if restoreFace && showsFace {
            if reducedMotion { crossfade(rig.stage) }
            rig.apply(restPose, reducedMotion ? .instant : .ease(0.2))
        }
        if anticLook != nil {
            anticLook = nil
            rig.setGaze(hostGaze, .ease(0.3))
        }
    }

    // MARK: Offscreen

    /// Holds the frame of `moment` at `t` (0...1 of it): its keys set as model values, its face and
    /// look at that time. For frame strips; the live path animates the same numbers.
    func hold(_ moment: Antic, at t: Double) {
        // Measured at rest: the previous frame's keys are still set.
        Motion.still { Part.allCases.flatMap(rig.movers).forEach { $0.layer.setAffineTransform(.identity) } }
        let moment = moment.fitted(to: bodyBounds)
        Motion.still {
            for track in moment.tracks {
                for mover in rig.movers(track.part) {
                    mover.layer.setAffineTransform(track.key(at: t).transform(turnScale: mover.turn))
                }
            }
        }
        let face = moment.mood(at: t).map { rig.express($0, on: restPose, mirrored: moment.mirrored) } ?? restPose
        rig.apply(face, .instant)
        if let look = moment.look(at: t) { rig.setGaze(look ?? hostGaze, .instant) }
    }

    // MARK: Internals

    /// The pose shown now: the rest pose, or a moment's face on it (beats fire in order, so the
    /// last one fired is the face on screen).
    private var currentFace: Pose {
        guard let antic, let at = firedBeat, let mood = antic.antic.mood(at: at) else { return restPose }
        return rig.express(mood, on: restPose, mirrored: antic.antic.mirrored)
    }

    private func beat(_ at: Double) {
        guard let (_, moment) = antic else { return }
        firedBeat = at
        if let face = moment.faces.last(where: { $0.at == at }) {
            let pose = face.mood.map { rig.express($0, on: restPose, mirrored: moment.mirrored) } ?? restPose
            if reducedMotion { crossfade(rig.stage) }
            rig.apply(pose, reducedMotion ? .instant : .ease(0.16))
        }
        if !reducedMotion, let look = moment.looks.last(where: { $0.at == at }) {
            anticLook = look.look
            rig.setGaze(look.look ?? hostGaze, .ease(0.28))
        }
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: max(delay, 0.001), repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        anticTimers.append(timer)
    }
}
