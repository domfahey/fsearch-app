import FSearchKit
import SwiftUI
import Testing
@testable import FSearch

extension AppTests {
    @Suite @MainActor
    struct PanelInputTests {
        private typealias P = PanelInput.Press

        private func key(_ p: P, empty: Bool = false) -> PanelKey? { PanelInput.key(for: p, queryIsEmpty: empty) }

        @Test func arrowsAndEmacsKeys() {
            #expect(key(P(key: .upArrow)) == .up)
            #expect(key(P(key: .upArrow, command: true)) == .up)
            #expect(key(P(key: .downArrow)) == .down)
            #expect(key(P(key: "p", characters: "\u{10}", control: true)) == .up)
            #expect(key(P(key: "n", characters: "\u{0e}", control: true)) == .down)
            // ⌃⇧P and ⌘⌃N are not bindings.
            #expect(key(P(key: "p", shift: true, control: true)) == nil)
            #expect(key(P(key: "n", command: true, control: true)) == nil)
            #expect(key(P(key: "p", characters: "p")) == nil)
            // ⌃P/⌃N as control characters, as AppKit may deliver them.
            #expect(key(P(key: KeyEquivalent("\u{10}"), characters: "\u{10}", control: true)) == .up)
            #expect(key(P(key: KeyEquivalent("\u{0e}"), characters: "\u{0e}", control: true)) == .down)
            #expect(key(P(key: "P", control: true)) == .up)
            #expect(PanelInput.letter("\u{0e}") == "n")
            #expect(PanelInput.letter("Q") == "q")
        }

        @Test func returnAndEscape() {
            #expect(key(P(key: .return)) == .enter)
            #expect(key(P(key: .return, shift: true)) == .enter)
            #expect(key(P(key: .return, command: true)) == .cmdEnter)
            #expect(key(P(key: .escape)) == .escape)
        }

        @Test func commandLettersIgnoreCase() {
            #expect(key(P(key: "y", characters: "y", command: true)) == .cmdY)
            #expect(key(P(key: "Y", characters: "Y", command: true)) == .cmdY)  // Caps Lock
            #expect(key(P(key: "k", characters: "k", command: true)) == .cmdK)
            #expect(key(P(key: "C", characters: "C", command: true, shift: true)) == .cmdShiftC)
            #expect(key(P(key: "c", characters: "c", command: true)) == nil)  // ⌘C is the field's copy
            #expect(key(P(key: "y", characters: "y")) == nil)
        }

        @Test func deleteOnlyOnAnEmptyQuery() {
            #expect(key(P(key: .delete), empty: true) == .backspaceOnEmpty)
            #expect(key(P(key: .delete), empty: false) == nil)
            #expect(key(P(key: .delete, command: true), empty: true) == nil)
        }

        @Test func digitsOnlyWithCommand() {
            #expect(key(P(key: "3", characters: "3", command: true)) == .cmdDigit(3))
            #expect(key(P(key: "3", characters: "3")) == nil)
            #expect(key(P(key: "a", characters: "a", command: true)) == nil)
            #expect(key(P(key: "a", characters: "", command: true)) == nil)
        }

        @Test func returnOnAFallbackRowSwitchesMode() {
            // 2 files, then "Search inside files" (2) and "Find definitions" (3).
            #expect(PanelInput.route(.open(2), files: 2, query: "heron", mode: .names) == .switchMode(.content))
            #expect(PanelInput.route(.open(3), files: 2, query: "heron", mode: .names) == .switchMode(.symbols))
            #expect(PanelInput.route(.open(9), files: 2, query: "heron", mode: .names) == .ignore)
            #expect(PanelInput.route(.open(1), files: 2, query: "heron", mode: .names) == .perform(.open(1)))
        }

        @Test func fileActionsDontApplyToFallbackRows() {
            for e in [PanelEffect.reveal(2), .quickLook(2), .copyPath(2), .showActions(2)] {
                #expect(PanelInput.route(e, files: 2, query: "heron", mode: .names) == .ignore)
            }
            for e in [PanelEffect.reveal(0), .quickLook(1), .copyPath(0), .showActions(1), .hide, .none] {
                #expect(PanelInput.route(e, files: 2, query: "heron", mode: .names) == .perform(e))
            }
        }

        // "set" with 2 files: row 0 is the command, rows 1-2 the files, 3-4 the fallbacks.
        private func commandRows() -> PanelRows { PanelRows(files: 2, query: "set", mode: .names) }

        @Test func returnOnTheCommandRowRunsIt() {
            #expect(PanelInput.route(.open(0), rows: commandRows()) == .perform(.open(0)))
            #expect(PanelInput.route(.open(1), rows: commandRows()) == .perform(.open(1)))
            #expect(PanelInput.route(.open(2), rows: commandRows()) == .runCommand(.settings))
            #expect(PanelInput.route(.open(3), rows: commandRows()) == .switchMode(.content))
            #expect(PanelInput.route(.open(4), rows: commandRows()) == .switchMode(.symbols))
            #expect(PanelInput.route(.open(5), rows: commandRows()) == .ignore)
        }

        @Test func fileActionsIgnoreTheCommandRowAndKeepFileIndexes() {
            for e in [PanelEffect.reveal(2), .quickLook(2), .copyPath(2), .showActions(2), .reveal(3)] {
                #expect(PanelInput.route(e, rows: commandRows()) == .ignore)
            }
            #expect(PanelInput.route(.reveal(0), rows: commandRows()) == .perform(.reveal(0)))
            #expect(PanelInput.route(.showActions(1), rows: commandRows()) == .perform(.showActions(1)))
        }

        @Test func commandNKeysStillOpenFilesOnly() {
            var s = PanelState(query: "set", selection: 0, count: 5, files: 2)
            let effect = reduce(&s, .cmdDigit(1))
            #expect(PanelInput.route(effect, rows: commandRows()) == .perform(.open(0)))
            let past = reduce(&s, .cmdDigit(3))
            #expect(PanelInput.route(past, rows: commandRows()) == .perform(.none))
        }

        @Test func noCommandInContentMode() {
            let rows = PanelRows(files: 2, query: "settings", mode: .content)
            #expect(PanelInput.route(.open(0), rows: rows) == .perform(.open(0)))
        }

        @Test func runningTheSettingsCommandOpensSettings() {
            var opened = 0
            let saved = PanelController.openSettings
            PanelController.openSettings = { opened += 1 }
            defer { PanelController.openSettings = saved }
            PanelController.shared.run(.settings)
            #expect(opened == 1)
        }

        /// A key and its ⌘K menu item agree on whether the launcher goes away.
        @Test func effectsHideLikeTheirMenuItems() {
            #expect(PanelInput.menuAction(for: .open(0)) == .open)
            #expect(PanelInput.menuAction(for: .reveal(0)) == .reveal)
            #expect(PanelInput.menuAction(for: .quickLook(0)) == .quickLook)
            #expect(PanelInput.menuAction(for: .copyPath(0)) == .copyPath)
            #expect(PanelInput.menuAction(for: .showActions(0)) == nil)
            #expect(PanelInput.menuAction(for: .none) == nil)
            #expect(PanelInput.menuAction(for: .hide) == nil)
            // ↵ and ⌘↵ go to another app and put the launcher away; ⌘Y and ⌘⇧C don't.
            #expect(PanelInput.menuAction(for: .open(0))?.hidesPanel == true)
            #expect(PanelInput.menuAction(for: .reveal(0))?.hidesPanel == true)
            #expect(PanelInput.menuAction(for: .quickLook(0))?.hidesPanel == false)
            #expect(PanelInput.menuAction(for: .copyPath(0))?.hidesPanel == false)
        }
    }
}
