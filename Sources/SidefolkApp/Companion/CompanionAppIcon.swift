import AppKit
import SidefolkCore

/// The companion as the Dock's icon, if the person wants it (D118). Only while the app runs: `applicationIconImage` paints
/// the Dock's copy and nothing on disk, so Finder and Launchpad keep Sidefolk's, and the signature stays good. The menu
/// bar's mark stays Sidefolk's too: it has to be one colour to follow the bar.
extension AppCoordinator {
    func applyAppIcon(_ settings: AppSettings) { CompanionAppIcon.apply(settings) }
}

enum CompanionAppIcon {
    static let side: CGFloat = 512
    /// Sidefolk's own, for what names the app itself (About, an update, the Pocket) whatever the Dock shows.
    /// Read before anything changes it: `apply` touches it first.
    static let sidefolk: NSImage = NSApp.applicationIconImage
    private static var showing: String?
    private static var current: NSImage?

    /// Settings change often, and this draws: only when what it would show changed.
    static func apply(_ settings: AppSettings) {
        _ = sidefolk
        let look = CompanionArt.look(for: settings)
        let wanted = settings.companionAppIcon ? "\(settings.localCompanion ?? settings.companion.rawValue).\(settings.customCompanion ?? "").\(look.style.color.rawValue).\(look.style.accessory.rawValue)" : nil
        guard wanted != showing else { return }
        showing = wanted
        current = wanted == nil ? nil : image(for: settings)
        // Nil gives back the bundle's own.
        NSApp.applicationIconImage = current
    }

    /// Becoming a regular app when a window opens can lose it.
    static func reapply() {
        if let current { NSApp.applicationIconImage = current }
    }

    /// The icon a companion carries (`appicons/<id>.png`, D118), or else its portrait on a tile in the app icon's shape.
    static func image(for settings: AppSettings) -> NSImage? {
        // A made-up companion wears a built-in's body, not its icon.
        let carried = settings.customCompanion == nil ? Companion3DStage.appIcon(settings.localCompanion ?? settings.companion.rawValue) : nil
        return carried ?? tile(CompanionArt.portrait(for: settings, side: side))
    }

    /// The macOS icon shape, inset as Apple's grid has it, so it sits beside its neighbours in the Dock.
    private static func tile(_ portrait: NSImage) -> NSImage {
        let canvas = NSSize(width: side, height: side)
        return NSImage(size: canvas, flipped: false) { rect in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: side * 0.098, dy: side * 0.098), xRadius: side * 0.18, yRadius: side * 0.18)
            NSGradient(starting: NSColor(calibratedWhite: 0.99, alpha: 1), ending: NSColor(calibratedWhite: 0.88, alpha: 1))?.draw(in: shape, angle: -90)
            NSGraphicsContext.current?.saveGraphicsState()
            shape.addClip()
            portrait.draw(in: rect.insetBy(dx: side * 0.15, dy: side * 0.15))
            NSGraphicsContext.current?.restoreGraphicsState()
            return true
        }
    }
}
