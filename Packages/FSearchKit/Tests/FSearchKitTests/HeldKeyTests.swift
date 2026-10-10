import Foundation
import Testing

@testable import FSearchKit

@Suite struct HeldKeyTests {
    @Test func resultKeysAreTheOnesThatWait() {
        for k in [PanelKey.enter, .cmdEnter, .cmdY, .cmdK, .cmdShiftC, .cmdDigit(1), .cmdDigit(9)] {
            #expect(k.actsOnResults, "\(k)")
        }
        for k in [PanelKey.up, .down, .escape, .backspaceOnEmpty] {
            #expect(!k.actsOnResults, "\(k)")
        }
    }

    @Test func currentResultsActAtOnce() {
        var h = HeldKey()
        #expect(h.press(.enter, current: true, query: "a", mode: .names) == .enter)
        #expect(h.held == nil)
    }

    @Test func staleResultsHoldTheKeyUntilTheyAnswer() {
        var h = HeldKey()
        #expect(h.press(.enter, current: false, query: "heron", mode: .names) == nil)
        #expect(h.held == .enter)
        #expect(h.resultsArrived(query: "heron", mode: .names) == .enter)
        #expect(h.held == nil)
        #expect(h.resultsArrived(query: "heron", mode: .names) == nil)  // replayed once
    }

    @Test func navigationNeverWaits() {
        var h = HeldKey()
        #expect(h.press(.down, current: false, query: "a", mode: .names) == .down)
        #expect(h.press(.escape, current: false, query: "a", mode: .names) == .escape)
        #expect(h.held == nil)
    }

    @Test func theNewestKeyWins() {
        var h = HeldKey()
        _ = h.press(.enter, current: false, query: "a", mode: .names)
        _ = h.press(.cmdK, current: false, query: "a", mode: .names)
        #expect(h.resultsArrived(query: "a", mode: .names) == .cmdK)
    }

    /// A key held for one query never fires on another query's results.
    @Test func aChangedQueryOrModeDropsIt() {
        var h = HeldKey()
        _ = h.press(.enter, current: false, query: "a", mode: .names)
        #expect(h.resultsArrived(query: "ab", mode: .names) == nil)
        #expect(h.held == nil)
        _ = h.press(.enter, current: false, query: "a", mode: .names)
        #expect(h.resultsArrived(query: "a", mode: .content) == nil)
        _ = h.press(.cmdY, current: false, query: "a", mode: .names)
        h.cancel()
        #expect(h.resultsArrived(query: "a", mode: .names) == nil)
    }

    /// Escape (or anything that hides the panel) drops a held key.
    @Test func escapeDropsAHeldKey() {
        var h = HeldKey()
        _ = h.press(.enter, current: false, query: "a", mode: .names)
        _ = h.press(.escape, current: false, query: "a", mode: .names)
        #expect(h.held == nil)
    }
}
