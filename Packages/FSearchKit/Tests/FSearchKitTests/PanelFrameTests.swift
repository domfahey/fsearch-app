import CoreGraphics
import Foundation
import Testing

@testable import FSearchKit

@Suite struct PanelFrameTests {
    let size = CGSize(width: 680, height: 460)

    /// The whole panel, search field included, lies inside the visible frame
    /// with a margin, and is centred horizontally.
    func check(_ visible: CGRect, _ name: String) {
        let o = PanelFrame.origin(size: size, in: visible)
        let frame = CGRect(origin: o, size: size)
        #expect(frame.maxY <= visible.maxY - PanelFrame.margin, "\(name): top \(frame.maxY) above \(visible.maxY)")
        #expect(frame.minY >= visible.minY + PanelFrame.margin, "\(name): bottom \(frame.minY) below \(visible.minY)")
        #expect(abs(frame.midX - visible.midX) < 0.5, "\(name): not centred")
    }

    @Test func fitsOnCommonScreens() {
        // Visible frames: the menu bar (and a bottom Dock) taken off.
        check(CGRect(x: 0, y: 0, width: 1512, height: 944), "MacBook Pro 14 (1512x982)")
        check(CGRect(x: 0, y: 70, width: 1440, height: 830), "MacBook Air 13 with Dock")
        check(CGRect(x: 0, y: 0, width: 1280, height: 775), "1280x800")
        check(CGRect(x: 0, y: 0, width: 2560, height: 1415), "27-inch 1440p")
        check(CGRect(x: 0, y: 0, width: 3008, height: 1667), "Studio Display")
        check(CGRect(x: 1512, y: -300, width: 1920, height: 1055), "second screen below and right")
        check(CGRect(x: -1080, y: 0, width: 1080, height: 1895), "portrait screen on the left")
    }

    /// The panel sits above the middle, a sixth of the height up, when there is room.
    @Test func sitsAboveTheMiddleOnTallScreens() {
        let v = CGRect(x: 0, y: 0, width: 2560, height: 1415)
        let o = PanelFrame.origin(size: size, in: v)
        #expect(o.y == v.midY - size.height / 2 + v.height / 6)
        #expect(o.x == v.midX - size.width / 2)
    }

    /// The old formula (`midY - 30 + height/6`) put the top edge past the menu
    /// bar on the built-in 1512x982 screen; the new one stays below it.
    @Test func neverAboveTheVisibleFrameOnTheBuiltInScreen() {
        let v = CGRect(x: 0, y: 0, width: 1512, height: 944)
        #expect(v.midY - 30 + v.height / 6 + size.height > v.maxY)
        let o = PanelFrame.origin(size: size, in: v)
        #expect(o.y + size.height <= v.maxY - PanelFrame.margin)
    }

    /// On a short screen the top margin wins over "a sixth above the middle".
    @Test func shortScreenPinsTheTopMargin() {
        let v = CGRect(x: 0, y: 0, width: 1024, height: 700)
        let o = PanelFrame.origin(size: size, in: v)
        #expect(o.y + size.height == v.maxY - PanelFrame.margin)
    }

    /// A screen too short for the panel and its margins keeps the top (the search field) visible.
    @Test func tinyScreenKeepsTheSearchFieldVisible() {
        let v = CGRect(x: 0, y: 100, width: 600, height: 400)
        let o = PanelFrame.origin(size: size, in: v)
        #expect(o.y + size.height == v.maxY)
        #expect(o.x == v.minX)  // wider than the screen: its left edge stays on it
    }
}
