import Foundation
import Testing

@testable import FSearchKit

@Suite struct PanelKeysTests {
    func state(_ q: String = "abc", _ mode: SearchMode = .names, sel: Int = 0, count: Int = 5) -> PanelState {
        PanelState(query: q, mode: mode, selection: sel, count: count)
    }

    @Test func movesWithinBounds() {
        var s = state()
        #expect(PanelState.reduce(&s, .down) == .none); #expect(s.selection == 1)
        s.selection = 4; _ = PanelState.reduce(&s, .down); #expect(s.selection == 4)
        s.selection = 0; _ = PanelState.reduce(&s, .up); #expect(s.selection == 0)
    }

    @Test func actionsUseTheSelection() {
        var s = state(sel: 2)
        #expect(PanelState.reduce(&s, .enter) == .open(2))
        #expect(PanelState.reduce(&s, .cmdEnter) == .reveal(2))
        #expect(PanelState.reduce(&s, .cmdY) == .quickLook(2))
        #expect(PanelState.reduce(&s, .cmdShiftC) == .copyPath(2))
        #expect(PanelState.reduce(&s, .cmdK) == .showActions(2))
    }

    @Test func cmdDigitOpensTheNthResult() {
        var s = state(count: 3)
        #expect(PanelState.reduce(&s, .cmdDigit(1)) == .open(0))
        #expect(PanelState.reduce(&s, .cmdDigit(3)) == .open(2))
        #expect(PanelState.reduce(&s, .cmdDigit(4)) == .none)
    }

    /// Each escape, in order: clear the query (and the selection), then drop
    /// the content/symbols chip, then hide.
    @Test(arguments: [
        (SearchMode.content, [(PanelEffect.none, "", SearchMode.content), (.none, "", .names), (.hide, "", .names)]),
        (.names, [(.none, "", .names), (.hide, "", .names)]),
    ])
    func escapeClearsThenBacksOutThenHides(_ mode: SearchMode, _ steps: [(PanelEffect, String, SearchMode)]) {
        var s = state("abc", mode, sel: 2)
        for (i, (effect, query, mode)) in steps.enumerated() {
            #expect(PanelState.reduce(&s, .escape) == effect, "escape \(i + 1)")
            #expect(s.query == query && s.mode == mode && s.selection == 0, "escape \(i + 1)")
        }
    }

    @Test func backspaceOnEmptyDropsTheChip() {
        var s = state("", .symbols)
        #expect(PanelState.reduce(&s, .backspaceOnEmpty) == .none); #expect(s.mode == .names)
        #expect(PanelState.reduce(&s, .backspaceOnEmpty) == .none); #expect(s.mode == .names)
    }

    @Test func resumeWindowIsSixtySecondsInclusive() {
        var session = PanelSession()
        let t = Date(timeIntervalSince1970: 1000)
        session.hidden(state("report", .content, sel: 3), at: t)
        #expect(session.opened(at: t.addingTimeInterval(60)) == state("report", .content, sel: 3))
        #expect(session.opened(at: t.addingTimeInterval(60.001)) == PanelState())
    }

    @Test func hidingAgainReplacesTheEarlierState() {
        var session = PanelSession()
        let t = Date(timeIntervalSince1970: 1000)
        session.hidden(state("first", .content, sel: 1), at: t)
        session.hidden(state("second", .symbols, sel: 2), at: t.addingTimeInterval(30))
        // 70 s after the first hide but 40 s after the second: the second resumes.
        #expect(session.opened(at: t.addingTimeInterval(70)) == state("second", .symbols, sel: 2))
    }

    // Fix round 1: clamp selection to existing rows.

    @Test func outOfRangeSelectionClampsBeforeActing() {
        var s = state(sel: 7, count: 3)
        #expect(PanelState.reduce(&s, .enter) == .open(2))
    }

    @Test func upFromOutOfRangeSelectionStepsFromTheLastRow() {
        var s = state(sel: 7, count: 3)
        _ = PanelState.reduce(&s, .up)
        #expect(s.selection == 1)
    }

    @Test func negativeSelectionClampsToFirstRow() {
        var s = state(sel: -1, count: 3)
        #expect(PanelState.reduce(&s, .enter) == .open(0))
    }

    // Fix round 1: backspace only drops the chip when the query is empty.

    @Test func backspaceWithQueryKeepsTheChip() {
        var s = state("abc", .symbols)
        #expect(PanelState.reduce(&s, .backspaceOnEmpty) == .none)
        #expect(s.mode == .symbols)
        #expect(s.query == "abc")
    }

    // Fix round 1: edge cases for digits and empty results.

    @Test func cmdDigitOutsideOneToNineIsIgnored() {
        var s = state(count: 20)
        #expect(PanelState.reduce(&s, .cmdDigit(0)) == .none)
        #expect(PanelState.reduce(&s, .cmdDigit(10)) == .none)
        #expect(PanelState.reduce(&s, .cmdDigit(-1)) == .none)
    }

    @Test func cmdDigitNineReachesTheNinthRow() {
        var s = state(count: 20)
        #expect(PanelState.reduce(&s, .cmdDigit(9)) == .open(8))
    }

    @Test func emptyResultsIgnoreEveryActionAndPinSelectionAtZero() {
        var s = state(count: 0)
        #expect(PanelState.reduce(&s, .enter) == .none)
        #expect(PanelState.reduce(&s, .cmdK) == .none)
        #expect(PanelState.reduce(&s, .cmdEnter) == .none)
        #expect(PanelState.reduce(&s, .cmdY) == .none)
        #expect(PanelState.reduce(&s, .cmdShiftC) == .none)
        #expect(PanelState.reduce(&s, .cmdDigit(1)) == .none)
        #expect(PanelState.reduce(&s, .up) == .none)
        #expect(s.selection == 0)
        #expect(PanelState.reduce(&s, .down) == .none)
        #expect(s.selection == 0)
    }
}

@Suite struct CommandLetterTests {
    @Test func matchesIgnoringCase() {
        // Caps Lock turns ⌘y into "Y"; Shift turns ⌘⇧c into "C".
        #expect(PanelKey.commandLetter("y", shift: false) == .cmdY)
        #expect(PanelKey.commandLetter("Y", shift: false) == .cmdY)
        #expect(PanelKey.commandLetter("k", shift: false) == .cmdK)
        #expect(PanelKey.commandLetter("K", shift: false) == .cmdK)
        #expect(PanelKey.commandLetter("c", shift: true) == .cmdShiftC)
        #expect(PanelKey.commandLetter("C", shift: true) == .cmdShiftC)
    }

    @Test func shiftMatters() {
        #expect(PanelKey.commandLetter("Y", shift: true) == nil)
        #expect(PanelKey.commandLetter("K", shift: true) == nil)
        #expect(PanelKey.commandLetter("c", shift: false) == nil)
        #expect(PanelKey.commandLetter("x", shift: false) == nil)
    }
}

@Suite struct CmdDigitFilesOnlyTests {
    @Test func cmdDigitPastTheFilesIsIgnored() {
        // Two files plus the two "use with..." rows: ⌘3 and ⌘4 don't switch mode.
        var s = PanelState(query: "abc", count: 4, files: 2)
        #expect(PanelState.reduce(&s, .cmdDigit(2)) == .open(1))
        #expect(PanelState.reduce(&s, .cmdDigit(3)) == .none)
        #expect(PanelState.reduce(&s, .cmdDigit(4)) == .none)
        #expect(s.mode == .names)
    }

    /// ⌘ letters match the character first (Dvorak, AZERTY), then, for a
    /// non-Latin layout whose character is no letter we bind, the ANSI key code.
    @Test func commandLettersFallBackToTheKeyCode() {
        #expect(PanelKey.commandLetter("y", shift: false, keyCode: nil) == .cmdY)
        #expect(PanelKey.commandLetter("н", shift: false, keyCode: 0x10) == .cmdY)  // Russian: the Y key
        #expect(PanelKey.commandLetter("л", shift: false, keyCode: 0x28) == .cmdK)  // Russian: the K key
        #expect(PanelKey.commandLetter("С", shift: true, keyCode: 0x08) == .cmdShiftC)
        #expect(PanelKey.commandLetter("ν", shift: false, keyCode: 0x10) == .cmdY)  // Greek
        #expect(PanelKey.commandLetter("н", shift: false, keyCode: nil) == nil)
        // A Latin character decides on its own: Dvorak's Y is on QWERTY's T key (0x11).
        #expect(PanelKey.commandLetter("y", shift: false, keyCode: 0x11) == .cmdY)
        #expect(PanelKey.commandLetter("f", shift: false, keyCode: 0x10) == nil)  // Dvorak F on the Y key
        #expect(PanelKey.commandLetter("н", shift: false, keyCode: 0x00) == nil)  // A key: not bound
        #expect(PanelKey.commandLetter("с", shift: false, keyCode: 0x08) == nil)  // ⌘C without Shift is copy
    }
}
