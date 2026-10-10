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
}
