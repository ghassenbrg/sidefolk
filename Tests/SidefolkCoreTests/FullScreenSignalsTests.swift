import CoreGraphics
import Testing
@testable import SidefolkCore

/// The windows measured on the founder's notched MacBook (1512 × 982, a 33-point menu bar), 2026-11-07.
struct FullScreenSignalsTests {
    let display = FullScreenSignals.Display(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), menuBar: 33)
    let icons = -2147483603

    func desktop(_ level: Int) -> FullScreenSignals.Window { .init(layer: level, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), front: false) }
    func front(_ y: CGFloat, _ height: CGFloat) -> FullScreenSignals.Window { .init(layer: 0, frame: CGRect(x: 0, y: y, width: 1512, height: height), front: true) }

    /// What stays on a full-screen space: three of the desktop's layers, not Finder's.
    var spaceLayers: [FullScreenSignals.Window] { [desktop(-2147483622), desktop(-2147483624), desktop(-2147483626)] }

    @Test func fullScreenChromeBelowTheNotchCounts() {
        // Its tab strip and its page are two windows that fill the display below the menu bar together.
        #expect(FullScreenSignals.inFullScreen(windows: spaceLayers + [front(33, 158), front(155, 827)], displays: [display], desktopIconLevel: icons))
        #expect(FullScreenSignals.inFullScreen(windows: spaceLayers + [front(33, 949)], displays: [display], desktopIconLevel: icons))
    }

    @Test func aWindowZoomedOnTheDesktopDoesNot() {
        // The same 1512 × 949, but Finder's desktop is on screen.
        #expect(!FullScreenSignals.inFullScreen(windows: spaceLayers + [desktop(icons), front(33, 949)], displays: [display], desktopIconLevel: icons))
    }

    @Test func noFinderDesktopAloneIsNotEnough() {
        // An ordinary window on a desktop without Finder's icons.
        #expect(!FullScreenSignals.inFullScreen(windows: spaceLayers + [.init(layer: 0, frame: CGRect(x: 214, y: 219, width: 1085, height: 682), front: true)],
                                                displays: [display], desktopIconLevel: icons))
        #expect(!FullScreenSignals.inFullScreen(windows: spaceLayers, displays: [display], desktopIconLevel: icons))
    }

    @Test func aWindowTheDisplaysSizeStillCounts() {
        #expect(FullScreenSignals.inFullScreen(windows: [desktop(icons), front(0, 982)], displays: [display], desktopIconLevel: icons))
    }

    @Test func aSecondDisplaysOwnFullScreenCounts() {
        let side = FullScreenSignals.Display(frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), menuBar: 25)
        let windows = [desktop(icons), FullScreenSignals.Window(layer: 0, frame: CGRect(x: 1512, y: 25, width: 1920, height: 1055), front: true)]
        #expect(FullScreenSignals.inFullScreen(windows: windows, displays: [display, side], desktopIconLevel: icons))
    }

    @Test func sidefolkInFrontKeepsTheLastAnswer() {
        var state = FullScreenState()
        state.observe(frontmostIsSidefolk: false, inFullScreen: true)
        state.observe(frontmostIsSidefolk: true, inFullScreen: false)
        #expect(state.inFullScreen)
        state.observe(frontmostIsSidefolk: false, inFullScreen: false)
        #expect(!state.inFullScreen)
    }
}
