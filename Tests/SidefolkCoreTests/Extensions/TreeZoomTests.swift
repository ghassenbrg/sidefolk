import CoreGraphics
import Testing
@testable import SidefolkCore

/// A tree board zooms like a whiteboard (D233): within its range, around the pointer, and Fit never blows a small tree up.
struct TreeZoomTests {
    @Test func theScaleStaysInItsRange() {
        #expect(TreeZoom.clamped(0.1) == 0.25)
        #expect(TreeZoom.clamped(3) == 2)
        #expect(TreeZoom.clamped(1.3) == 1.3)
        #expect(TreeZoom.clamped(.nan) == 1, "a broken pinch leaves it at its own size")
    }

    @Test func fitShowsItAllButNeverEnlarges() {
        #expect(TreeZoom.fit(CGSize(width: 400, height: 300), in: CGSize(width: 1000, height: 800)) == 1)
        #expect(TreeZoom.fit(CGSize(width: 2000, height: 800), in: CGSize(width: 1000, height: 800)) == 0.5)
        #expect(TreeZoom.fit(CGSize(width: 20_000, height: 800), in: CGSize(width: 1000, height: 800)) == 0.25, "as small as it goes")
    }

    @Test func thePointUnderThePointerStaysPut() {
        // At 1×, scrolled 100 in, the pointer at 200 is over 300 on the board; at 2× that is 600, so the view starts at 400.
        let doubled = TreeZoom.offset(CGPoint(x: 100, y: 50), keeping: CGPoint(x: 200, y: 100), from: 1, to: 2)
        #expect(doubled == CGPoint(x: 400, y: 200))
        let back = TreeZoom.offset(doubled, keeping: CGPoint(x: 200, y: 100), from: 2, to: 1)
        #expect(back == CGPoint(x: 100, y: 50), "and zooming back returns to where it was")
        #expect(TreeZoom.offset(.zero, keeping: CGPoint(x: 10, y: 10), from: 1, to: 0.5) == .zero, "never before the start")
    }

    @Test func aCarriedCardScrollsTowardTheEdgeItIsAt() {
        let at = CGPoint(x: 30, y: 200)
        #expect(TreeZoom.nudged(at, toward: .maxYEdge) == CGPoint(x: 30, y: 214))
        #expect(TreeZoom.nudged(at, toward: .minXEdge) == CGPoint(x: 16, y: 200))
        #expect(TreeZoom.nudged(CGPoint(x: 5, y: 5), toward: .minYEdge) == CGPoint(x: 5, y: 0))
    }
}
