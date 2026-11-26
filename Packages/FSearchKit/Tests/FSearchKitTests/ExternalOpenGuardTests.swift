import Foundation
import Testing

@testable import FSearchKit

@Suite struct ExternalOpenGuardTests {
    // A monotonic clock: a wall-clock step (NTP, manual change) can't stretch or shrink the window.
    let t0 = ContinuousClock.now

    @Test func unarmedIgnoresNothing() {
        let g = ExternalOpenGuard()
        for k in [PanelKey.enter, .cmdEnter, .cmdDigit(1)] { #expect(!g.ignores(k, at: t0)) }
    }

    @Test func armedIgnoresActivationKeysForTheWindow() {
        var g = ExternalOpenGuard()
        g.arm(at: t0)
        for k in [PanelKey.enter, .cmdEnter, .cmdDigit(1), .cmdDigit(9)] {
            #expect(g.ignores(k, at: t0), "\(k)")
            #expect(g.ignores(k, at: t0.advanced(by: .milliseconds(490))), "\(k)")
            #expect(!g.ignores(k, at: t0.advanced(by: ExternalOpenGuard.window)), "\(k)")
        }
    }

    @Test func movingEscapeAndNonActivatingKeysAreNeverIgnored() {
        var g = ExternalOpenGuard()
        g.arm(at: t0)
        for k in [PanelKey.up, .down, .escape, .backspaceOnEmpty, .appMenu, .cmdY, .cmdShiftC, .cmdK] {
            #expect(!g.ignores(k, at: t0), "\(k)")
        }
    }

    @Test func disarmEndsTheWindow() {
        var g = ExternalOpenGuard()
        g.arm(at: t0)
        g.disarm()
        #expect(!g.ignores(.enter, at: t0))
    }

    @Test func windowIsHalfASecond() {
        #expect(ExternalOpenGuard.window == .milliseconds(500))
    }
}
