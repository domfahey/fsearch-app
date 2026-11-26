import Foundation
import Testing

@testable import FSearchKit

@Suite struct ExternalOpenGuardTests {
    let t0 = Date(timeIntervalSince1970: 1000)

    @Test func unarmedIgnoresNothing() {
        let g = ExternalOpenGuard()
        for k in [PanelKey.enter, .cmdEnter, .cmdDigit(1)] { #expect(!g.ignores(k, at: t0)) }
    }

    @Test func armedIgnoresActivationKeysForTheWindow() {
        var g = ExternalOpenGuard()
        g.arm(at: t0)
        for k in [PanelKey.enter, .cmdEnter, .cmdDigit(1), .cmdDigit(9)] {
            #expect(g.ignores(k, at: t0), "\(k)")
            #expect(g.ignores(k, at: t0.addingTimeInterval(0.49)), "\(k)")
            #expect(!g.ignores(k, at: t0.addingTimeInterval(0.5)), "\(k)")
        }
    }

    @Test func movingEscapeAndNonActivatingKeysAreNeverIgnored() {
        var g = ExternalOpenGuard()
        g.arm(at: t0)
        for k in [PanelKey.up, .down, .escape, .backspaceOnEmpty, .appMenu, .cmdY, .cmdShiftC, .cmdK] {
            #expect(!g.ignores(k, at: t0), "\(k)")
        }
    }

    @Test func disarmAndClockGoingBackwards() {
        var g = ExternalOpenGuard()
        g.arm(at: t0)
        #expect(g.ignores(.enter, at: t0.addingTimeInterval(-5)))  // clock stepped back: stay safe
        g.disarm()
        #expect(!g.ignores(.enter, at: t0))
    }
}
