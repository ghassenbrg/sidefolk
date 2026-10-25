import QuartzCore

/// How a pose change travels.
enum Transit {
    case spring, ease(CFTimeInterval), instant
}

/// Animation helpers. Everything here hands Core Animation a description and returns; the
/// interpolation runs on the render server, never in an app-side frame loop.
@MainActor
enum Motion {
    /// Sets the model value (no implicit animation) and, unless instant, animates to it from
    /// whatever is on screen right now, so interrupted transitions never jump.
    static func set(_ layer: CALayer, _ keyPath: String, _ value: Any, _ transit: Transit) {
        let model = layer.value(forKeyPath: keyPath)
        let shown = layer.presentation()?.value(forKeyPath: keyPath) ?? model
        // Already there, or already on the way there.
        if let model, (model as AnyObject).isEqual(value) { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: keyPath)
        CATransaction.commit()

        let animation: CABasicAnimation
        switch transit {
        case .instant:
            layer.removeAnimation(forKey: keyPath)
            return
        case .spring:
            let spring = CASpringAnimation(perceptualDuration: 0.42, bounce: 0.28)
            spring.keyPath = keyPath
            spring.duration = spring.settlingDuration
            animation = spring
        case .ease(let duration):
            animation = CABasicAnimation(keyPath: keyPath)
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        animation.fromValue = shown
        animation.toValue = value
        layer.add(animation, forKey: keyPath)
    }

    static func transform(_ t: CGAffineTransform) -> NSValue {
        NSValue(caTransform3D: CATransform3DMakeAffineTransform(t))
    }

    /// A forever-repeating back-and-forth (or one-way when `reverses` is false).
    static func loop(_ keyPath: String, from: Any, to: Any, duration: CFTimeInterval, reverses: Bool = true,
                     phase: CFTimeInterval = 0, timing: CAMediaTimingFunctionName = .easeInEaseOut) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.autoreverses = reverses
        animation.repeatCount = .infinity
        animation.timeOffset = phase
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        return animation
    }

    /// A forever-repeating keyframe cycle; `times` default to evenly spaced.
    static func cycle(_ keyPath: String, _ values: [Any], duration: CFTimeInterval, times: [Double]? = nil,
                      phase: CFTimeInterval = 0, discrete: Bool = false) -> CAKeyframeAnimation {
        let animation = keyframes(keyPath, values, duration: duration, times: times, discrete: discrete)
        animation.repeatCount = .infinity
        animation.timeOffset = phase
        return animation
    }

    /// A one-shot keyframe move that ends where it started (the model value never changes).
    static func keyframes(_ keyPath: String, _ values: [Any], duration: CFTimeInterval, times: [Double]? = nil,
                          discrete: Bool = false) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.duration = duration
        if let times { animation.keyTimes = times.map { NSNumber(value: $0) } }
        if discrete {
            animation.calculationMode = .discrete
        } else {
            animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut),
                                              count: max(values.count - 1, 1))
        }
        return animation
    }

    /// Changes model values with no implicit animation.
    static func still(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
