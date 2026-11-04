#if DEBUG
import AppKit
import ObjectiveC

/// A test run's panels stay off the person's screen too (AGENTS.md): invisible, taking no clicks and no key focus, however they're shown
/// or animated. `snap` still draws them. Done at the Objective-C level, since a Swift override of these breaks `panel.animator()`.
enum QuietPanels {
    private nonisolated(unsafe) static var sweeper: Timer?

    static func install() {
        guard WindowActivation.quiet else { return }
        nonisolated(unsafe) let alpha = #selector(setter: NSWindow.alphaValue), mouse = #selector(setter: NSWindow.ignoresMouseEvents)
        typealias SetAlpha = @convention(c) (AnyObject, Selector, CGFloat) -> Void
        typealias SetBool = @convention(c) (AnyObject, Selector, Bool) -> Void
        nonisolated(unsafe) let originalAlpha = unsafeBitCast(class_getMethodImplementation(NSWindow.self, alpha), to: SetAlpha.self)
        nonisolated(unsafe) let originalMouse = unsafeBitCast(class_getMethodImplementation(NSWindow.self, mouse), to: SetBool.self)
        nonisolated(unsafe) let hide: @convention(block) (AnyObject) -> Void = { window in
            originalAlpha(window, alpha, 0)
            originalMouse(window, mouse, true)
        }
        let setAlpha: @convention(block) (AnyObject, CGFloat) -> Void = { window, _ in originalAlpha(window, alpha, 0) }
        let setMouse: @convention(block) (AnyObject, Bool) -> Void = { window, _ in originalMouse(window, mouse, true) }
        class_replaceMethod(NSPanel.self, alpha, imp_implementationWithBlock(setAlpha), "v@:d")
        class_replaceMethod(NSPanel.self, mouse, imp_implementationWithBlock(setMouse), "v@:B")

        // Every way of being shown, so nothing is drawn even once first.
        let order = #selector(NSWindow.order(_:relativeTo:))
        typealias Order = @convention(c) (AnyObject, Selector, NSWindow.OrderingMode, Int) -> Void
        let originalOrder = unsafeBitCast(class_getMethodImplementation(NSWindow.self, order), to: Order.self)
        let setOrder: @convention(block) (AnyObject, NSWindow.OrderingMode, Int) -> Void = { window, mode, other in
            hide(window)
            originalOrder(window, order, mode, other)
        }
        class_replaceMethod(NSPanel.self, order, imp_implementationWithBlock(setOrder), "v@:qq")
        typealias Plain = @convention(c) (AnyObject, Selector) -> Void
        typealias Sender = @convention(c) (AnyObject, Selector, Any?) -> Void
        let regardless = #selector(NSWindow.orderFrontRegardless)
        let originalRegardless = unsafeBitCast(class_getMethodImplementation(NSWindow.self, regardless), to: Plain.self)
        let setRegardless: @convention(block) (AnyObject) -> Void = { window in
            hide(window)
            originalRegardless(window, regardless)
        }
        class_replaceMethod(NSPanel.self, regardless, imp_implementationWithBlock(setRegardless), "v@:")
        for selector in [#selector(NSWindow.orderFront(_:)), #selector(NSWindow.makeKeyAndOrderFront(_:))] {
            let original = unsafeBitCast(class_getMethodImplementation(NSWindow.self, selector), to: Sender.self)
            let shown: @convention(block) (AnyObject, Any?) -> Void = { window, sender in
                hide(window)
                original(window, selector, sender)
            }
            class_replaceMethod(NSPanel.self, selector, imp_implementationWithBlock(shown), "v@:@")
        }
        let never: @convention(block) (AnyObject) -> Bool = { _ in false }
        class_replaceMethod(FloatingPanel.self, #selector(getter: NSWindow.canBecomeKey), imp_implementationWithBlock(never), "B@:")

        // Whatever gets past those: an animation's last step, a window AppKit makes itself.
        sweeper = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                for window in NSApp.windows where window is NSPanel && window.alphaValue != 0 { hide(window) }
            }
        }
    }
}
#endif
