import Foundation
import Testing
@testable import FSearchKit

@Suite struct PanelKeysTests {
    func state(_ q: String = "abc", _ mode: SearchMode = .names, sel: Int = 0, count: Int = 5) -> PanelState {
        PanelState(query: q, mode: mode, selection: sel, count: count)
    }

    @Test func movesWithinBounds() {
        var s = state()
        #expect(reduce(&s, .down) == .none); #expect(s.selection == 1)
        s.selection = 4; _ = reduce(&s, .down); #expect(s.selection == 4)
        s.selection = 0; _ = reduce(&s, .up); #expect(s.selection == 0)
    }

    @Test func actionsUseTheSelection() {
        var s = state(sel: 2)
        #expect(reduce(&s, .enter) == .open(2))
        #expect(reduce(&s, .cmdEnter) == .reveal(2))
        #expect(reduce(&s, .cmdY) == .quickLook(2))
        #expect(reduce(&s, .cmdShiftC) == .copyPath(2))
        #expect(reduce(&s, .cmdK) == .showActions(2))
    }

    @Test func cmdDigitOpensTheNthResult() {
        var s = state(count: 3)
        #expect(reduce(&s, .cmdDigit(1)) == .open(0))
        #expect(reduce(&s, .cmdDigit(3)) == .open(2))
        #expect(reduce(&s, .cmdDigit(4)) == .none)
    }

    @Test func nothingToActOnWithNoResults() {
        var s = state(count: 0)
        #expect(reduce(&s, .enter) == .none)
        #expect(reduce(&s, .cmdK) == .none)
    }

    @Test func escapeClearsThenBacksOutThenHides() {
        var s = state("abc", .content)
        #expect(reduce(&s, .escape) == .none); #expect(s.query == "" && s.mode == .content)
        #expect(reduce(&s, .escape) == .none); #expect(s.mode == .names)
        #expect(reduce(&s, .escape) == .hide)
    }

    @Test func backspaceOnEmptyDropsTheChip() {
        var s = state("", .symbols)
        #expect(reduce(&s, .backspaceOnEmpty) == .none); #expect(s.mode == .names)
        #expect(reduce(&s, .backspaceOnEmpty) == .none); #expect(s.mode == .names)
    }

    @Test func resumesWithinSixtySeconds() {
        var session = PanelSession()
        let t = Date(timeIntervalSince1970: 1000)
        session.hidden(state("report", .content, sel: 3), at: t)
        #expect(session.opened(at: t.addingTimeInterval(59)) == state("report", .content, sel: 3))
        #expect(session.opened(at: t.addingTimeInterval(61)) == PanelState(query: "", mode: .names, selection: 0, count: 0))
    }

    // Fix round 1: clamp selection to existing rows.

    @Test func outOfRangeSelectionClampsBeforeActing() {
        var s = state(sel: 7, count: 3)
        #expect(reduce(&s, .enter) == .open(2))
    }

    @Test func upFromOutOfRangeSelectionStepsFromTheLastRow() {
        var s = state(sel: 7, count: 3)
        _ = reduce(&s, .up)
        #expect(s.selection == 1)
    }

    @Test func negativeSelectionClampsToFirstRow() {
        var s = state(sel: -1, count: 3)
        #expect(reduce(&s, .enter) == .open(0))
    }

    // Fix round 1: backspace only drops the chip when the query is empty.

    @Test func backspaceWithQueryKeepsTheChip() {
        var s = state("abc", .symbols)
        #expect(reduce(&s, .backspaceOnEmpty) == .none)
        #expect(s.mode == .symbols)
        #expect(s.query == "abc")
    }

    // Fix round 1: the resume window is inclusive at 60 s, exclusive after.

    @Test func resumeWindowIsInclusiveAtSixtySeconds() {
        var session = PanelSession()
        let t = Date(timeIntervalSince1970: 1000)
        session.hidden(state("report", .content, sel: 3), at: t)
        #expect(session.opened(at: t.addingTimeInterval(60)) == state("report", .content, sel: 3))
    }

    @Test func resumeWindowClosesJustAfterSixtySeconds() {
        var session = PanelSession()
        let t = Date(timeIntervalSince1970: 1000)
        session.hidden(state("report", .content, sel: 3), at: t)
        #expect(session.opened(at: t.addingTimeInterval(60.001)) == PanelState())
    }

    // Fix round 1: edge cases for digits, empty results, and escape.

    @Test func cmdDigitOutsideOneToNineIsIgnored() {
        var s = state(count: 20)
        #expect(reduce(&s, .cmdDigit(0)) == .none)
        #expect(reduce(&s, .cmdDigit(10)) == .none)
        #expect(reduce(&s, .cmdDigit(-1)) == .none)
    }

    @Test func cmdDigitNineReachesTheNinthRow() {
        var s = state(count: 20)
        #expect(reduce(&s, .cmdDigit(9)) == .open(8))
    }

    @Test func emptyResultsIgnoreEveryActionAndPinSelectionAtZero() {
        var s = state(count: 0)
        #expect(reduce(&s, .cmdEnter) == .none)
        #expect(reduce(&s, .cmdY) == .none)
        #expect(reduce(&s, .cmdShiftC) == .none)
        #expect(reduce(&s, .cmdDigit(1)) == .none)
        #expect(reduce(&s, .up) == .none)
        #expect(s.selection == 0)
        #expect(reduce(&s, .down) == .none)
        #expect(s.selection == 0)
    }

    @Test func escapeResetsSelectionToZero() {
        var s = state("abc", .names, sel: 2)
        #expect(reduce(&s, .escape) == .none)
        #expect(s.selection == 0)
    }

    @Test func escapeInNamesClearsQueryWithoutHiding() {
        var s = state("abc", .names, sel: 2)
        #expect(reduce(&s, .escape) == .none)
        #expect(s.query == "")
        #expect(s.mode == .names)
        #expect(reduce(&s, .escape) == .hide)
    }
}
