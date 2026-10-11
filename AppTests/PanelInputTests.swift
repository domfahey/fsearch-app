import AppKit
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

        /// Item 8: holding ↓/↑/⌃N/⌃P repeats; no other key acts on a repeat.
        @Test func onlyMovingRepeats() {
            #expect(key(P(key: .downArrow, isRepeat: true)) == .down)
            #expect(key(P(key: .upArrow, isRepeat: true)) == .up)
            #expect(key(P(key: "n", characters: "\u{0e}", control: true, isRepeat: true)) == .down)
            #expect(key(P(key: "p", characters: "\u{10}", control: true, isRepeat: true)) == .up)
            #expect(key(P(key: .return, isRepeat: true)) == nil)
            #expect(key(P(key: .return, command: true, isRepeat: true)) == nil)
            #expect(key(P(key: .escape, isRepeat: true)) == nil)
            #expect(key(P(key: "k", characters: "k", command: true, isRepeat: true)) == nil)
            #expect(key(P(key: .delete, isRepeat: true), empty: true) == nil)
        }

        /// Item 13: on a non-Latin layout ⌘Y types "н": the key code decides.
        @Test func commandLettersOnANonLatinLayout() {
            #expect(key(P(key: "н", characters: "н", command: true, keyCode: 0x10)) == .cmdY)
            #expect(key(P(key: "л", characters: "л", command: true, keyCode: 0x28)) == .cmdK)
            #expect(key(P(key: "С", characters: "С", command: true, shift: true, keyCode: 0x08)) == .cmdShiftC)
            #expect(key(P(key: "f", characters: "f", command: true, keyCode: 0x10)) == nil)  // Dvorak
            #expect(key(P(key: "н", characters: "н", keyCode: 0x10)) == nil)  // no ⌘: typed
        }

        @Test func deleteOnlyOnAnEmptyQuery() {
            #expect(key(P(key: .delete), empty: true) == .backspaceOnEmpty)
            #expect(key(P(key: .delete), empty: false) == nil)
            #expect(key(P(key: .delete, command: true), empty: true) == nil)
        }

        /// Backspace arrives as DEL or BS depending on the source (a keyboard,
        /// a synthesized event), and always as key code 51.
        @Test func backspaceInEveryForm() {
            #expect(key(P(key: KeyEquivalent("\u{7F}")), empty: true) == .backspaceOnEmpty)
            #expect(key(P(key: KeyEquivalent("\u{08}")), empty: true) == .backspaceOnEmpty)
            #expect(key(P(key: KeyEquivalent("x"), keyCode: 51), empty: true) == .backspaceOnEmpty)
            #expect(key(P(key: KeyEquivalent("\u{7F}")), empty: false) == nil)
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
            let effect = PanelState.reduce(&s, .cmdDigit(1))
            #expect(PanelInput.route(effect, rows: commandRows()) == .perform(.open(0)))
            let past = PanelState.reduce(&s, .cmdDigit(3))
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

        /// macOS 14+ ignores showSettingsWindow:, so the command performs the app
        /// menu's Settings… item (⌘,), the one SwiftUI's Settings scene adds.
        @Test func settingsCommandPerformsTheAppMenusSettingsItem() {
            let target = MenuTarget()
            let main = NSMenu(), appMenu = NSMenu()
            appMenu.addItem(NSMenuItem(title: "About FSearch", action: #selector(MenuTarget.other), keyEquivalent: ""))
            appMenu.addItem(NSMenuItem(title: "Hide", action: #selector(MenuTarget.other), keyEquivalent: "h"))
            let settings = NSMenuItem(title: "Settings…", action: #selector(MenuTarget.settings), keyEquivalent: ",")
            appMenu.addItem(settings)
            for item in appMenu.items { item.target = target }
            let top = NSMenuItem(title: "FSearch", action: nil, keyEquivalent: "")
            top.submenu = appMenu
            main.addItem(top)

            #expect(PanelController.performSettingsMenuItem(in: main))
            #expect(target.settingsHits == 1 && target.otherHits == 0)
        }

        @Test func noSettingsItemIsReportedNotGuessed() {
            let main = NSMenu()
            let shifted = NSMenuItem(title: "Other", action: #selector(MenuTarget.settings), keyEquivalent: ",")
            shifted.keyEquivalentModifierMask = [.command, .shift]
            let target = MenuTarget()
            shifted.target = target
            main.addItem(shifted)
            #expect(!PanelController.performSettingsMenuItem(in: main))
            #expect(!PanelController.performSettingsMenuItem(in: nil))
            #expect(target.settingsHits == 0)
        }

        /// The real opener does nothing in the inert unit-test host: no activation, no menu item.
        @Test func theSettingsOpenerIsInertInTheTestHost() {
            #expect(Presentation.inert)
            let target = MenuTarget()
            let main = NSMenu()
            let settings = NSMenuItem(title: "Settings…", action: #selector(MenuTarget.settings), keyEquivalent: ",")
            settings.target = target
            main.addItem(settings)
            #expect(!PanelController.openSettingsWindow(menu: main))
            #expect(target.settingsHits == 0)
        }

        /// Item 7: the id the list scrolls to for each selectable row.
        @Test func rowIDsForScrolling() {
            let shown: [ResultItem] = [.file(Wire.hit("/p/a")), .line(path: "/p/b", match: Match(line: 3, text: "x"))]
            let rows = PanelRows(files: 2, query: "set", mode: .names)
            #expect(PanelInput.rowID(at: 0, shown: shown, rows: rows) == "/p/a")
            #expect(PanelInput.rowID(at: 1, shown: shown, rows: rows) == "/p/b:3")
            #expect(PanelInput.rowID(at: 2, shown: shown, rows: rows) == "command-FSearch Settings")
            #expect(PanelInput.rowID(at: 3, shown: shown, rows: rows) == "fallback-content")
            #expect(PanelInput.rowID(at: 4, shown: shown, rows: rows) == "fallback-symbols")
            #expect(PanelInput.rowID(at: 5, shown: shown, rows: rows) == nil)
        }

        /// Item 6: ↵ before the results answer the query is held, then runs
        /// on the new results; never on the previous query's rows.
        @Test func resultKeysWaitForCurrentResults() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let model = env.app.search
            env.daemon.onSearch = { q in SearchReply(tookUs: 1, hits: [Wire.hit("/p/\(q).txt")]) }
            model.query = "old"
            await model.refresh()
            #expect(model.resultsAreCurrent)
            var held = HeldKey()
            #expect(PanelInput.gate(.enter, held: &held, model: model) == .enter)

            model.query = "new"  // pasted; its search hasn't answered yet
            #expect(!model.resultsAreCurrent)
            #expect(PanelInput.gate(.enter, held: &held, model: model) == nil)
            #expect(PanelInput.gate(.down, held: &held, model: model) == .down)
            #expect(PanelInput.gate(.cmdDigit(1), held: &held, model: model) == nil)
            #expect(PanelInput.replay(held: &held, model: model, visible: true) == nil)  // still stale
            await model.refresh()
            #expect(model.items == [.file(Wire.hit("/p/new.txt"))])
            #expect(PanelInput.replay(held: &held, model: model, visible: true) == .cmdDigit(1))
            #expect(PanelInput.replay(held: &held, model: model, visible: true) == nil)

            // Recents (an empty names query) never wait on a search.
            model.query = ""
            #expect(PanelInput.gate(.enter, held: &held, model: model) == .enter)
        }

        /// A held key replays only on results the user can see: never once the panel is hidden, and never on a failed
        /// or indexing settle (a ↵ on zero files would land on a fallback row and switch mode).
        @Test func aHeldKeyReplaysOnlyOnVisibleResults() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let model = env.app.search
            var held = HeldKey()
            env.daemon.onSearch = { q in SearchReply(tookUs: 1, hits: [Wire.hit("/p/\(q).txt")]) }
            model.query = "hidden"
            #expect(PanelInput.gate(.enter, held: &held, model: model) == nil)
            await model.refresh()
            #expect(PanelInput.replay(held: &held, model: model, visible: false) == nil)
            #expect(held.held == nil, "dropped, not kept for the next show")

            for error in [DaemonError.daemon("bad filter"), .indexing("indexing 10%")] {
                env.daemon.onSearch = { _ in throw error }
                model.query = "q\(error)"
                #expect(PanelInput.gate(.enter, held: &held, model: model) == nil)
                await model.refresh()
                #expect(model.resultsAreCurrent)
                #expect(PanelInput.replay(held: &held, model: model, visible: true) == nil, "\(error)")
                #expect(held.held == nil)
            }
        }

        /// A filter still being typed keeps the rows of the query it extends, so ↵ acts on them rather than waiting for a
        /// search that won't run until the filter is finished.
        @Test func aHalfTypedFilterDoesntHoldAKey() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let model = env.app.search
            env.daemon.onSearch = { q in SearchReply(tookUs: 1, hits: [Wire.hit("/p/\(q).txt")]) }
            model.query = "foo"
            await model.refresh()
            model.query = "foo ext:"
            await model.refresh()
            #expect(!model.resultsAreCurrent && model.items.map(\.path) == ["/p/foo.txt"])
            var held = HeldKey()
            #expect(PanelInput.gate(.enter, held: &held, model: model) == .enter)
            // In another mode, or over rows that aren't results, it still waits.
            model.mode = .content
            #expect(PanelInput.gate(.enter, held: &held, model: model) == nil)
            model.mode = .names
            env.daemon.onSearch = { _ in throw DaemonError.daemon("bad") }
            model.query = "bar"
            await model.refresh()
            model.query = "bar ext:"
            await model.refresh()
            #expect(PanelInput.gate(.enter, held: &held, model: model) == nil)
        }

        /// A pasted tail ("food ext:" over rows for "foo") only starts with the answered query: ↵ waits.
        @Test func aPastedHalfTypedTailHoldsAKey() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let model = env.app.search
            env.daemon.onSearch = { q in SearchReply(tookUs: 1, hits: [Wire.hit("/p/\(q).txt")]) }
            model.query = "foo"
            await model.refresh()
            model.query = "food ext:"
            #expect(!PanelInput.rowsAreCurrent(model))
            var held = HeldKey()
            #expect(PanelInput.gate(.enter, held: &held, model: model) == nil)
            await model.refresh()
            #expect(model.items.isEmpty && PanelInput.rowsAreCurrent(model), "the cleared list answers it")
            // Typing the filter word one key at a time keeps the rows of its last finished prefix.
            model.query = "foo ext"
            await model.refresh()
            model.query = "foo ext:"
            #expect(PanelInput.rowsAreCurrent(model) && model.items.map(\.path) == ["/p/foo ext.txt"])
        }

        /// New rows make a selection made on the old ones meaningless: it goes back to the top before a held key replays.
        @Test func newRowsResetTheSelection() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let model = env.app.search
            env.daemon.onSearch = { q in SearchReply(tookUs: 1, hits: [Wire.hit("/p/\(q)1"), Wire.hit("/p/\(q)2")]) }
            model.query = "old"
            await model.refresh()
            var held = HeldKey(), selection = 0
            model.query = "new"
            let before = PanelInput.answer(model)
            selection = 1  // ↓ on the old rows
            #expect(PanelInput.gate(.enter, held: &held, model: model) == nil)
            await model.refresh()
            let after = PanelInput.answer(model)
            let key = PanelInput.rowsChanged(from: before, to: after, selection: &selection, held: &held, model: model, visible: true)
            #expect(key == .enter && selection == 0)

            // The same rows answering again (an indexing poll) keep the selection.
            selection = 1
            #expect(
                PanelInput.rowsChanged(from: after, to: after, selection: &selection, held: &held, model: model, visible: true) == nil)
            #expect(selection == 1)
        }

        /// Item 12: folders, dotted ones included, and apps get their own icon, not their extension's.
        @Test func iconLookupForFoldersAndBundles() {
            #expect(IconCache.usesFileIcon(path: "/p/v1.2", isDirectory: true))
            #expect(IconCache.usesFileIcon(path: "/p/com.foo.bar", isDirectory: true))
            #expect(IconCache.usesFileIcon(path: "/p/folder", isDirectory: false))
            #expect(IconCache.usesFileIcon(path: "/Applications/Safari.app", isDirectory: false))
            #expect(!IconCache.usesFileIcon(path: "/p/a.txt", isDirectory: false))
            #expect(ResultRow.isDirectory(.file(Hit(path: "/p/v1.2", kind: "dir", size: 0, mtime: 0, score: 0))))
            #expect(!ResultRow.isDirectory(.file(Wire.hit("/p/a.txt"))))
            #expect(!ResultRow.isDirectory(.line(path: "/p/a.txt", match: Match(line: 1, text: ""))))
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

@MainActor
private final class MenuTarget: NSObject {
    var settingsHits = 0, otherHits = 0
    @objc func settings() { settingsHits += 1 }
    @objc func other() { otherHits += 1 }
}
